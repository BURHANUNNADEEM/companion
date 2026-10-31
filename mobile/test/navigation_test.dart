import 'package:companion/models/models.dart';
import 'package:companion/services/contacts_store.dart';
import 'package:companion/services/navigation_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> step({String kind = 'open_intent', String? intent = 'dial', String? route, Map? params}) => {
      'index': 0,
      'id': 's',
      'screen': 'companion_home',
      'target': {'id': 'tile_call', 'label': {'en': 'Call', 'ur': 'کال'}},
      'highlight': {'x': 0.1, 'y': 0.2, 'w': 0.3, 'h': 0.1},
      'arrow': 'down',
      'hint': {'en': 'Tap', 'ur': 'دبائیں'},
      'action': {'kind': kind, if (intent != null) 'intent': intent, if (route != null) 'route': route, if (params != null) 'params': params},
      'completion': {'type': 'intent_launched'},
    };

Map<String, dynamic> plan(List<Map<String, dynamic>> steps) => {
      'status': 'ok',
      'workflow_id': 'call_contact',
      'task': 'call',
      'title': {'en': 'Call', 'ur': 'کال'},
      'intro': {'en': 'Let us call', 'ur': 'آئیں کال کریں'},
      'steps': steps,
      'limits': {'max_steps': 10, 'timeout_seconds': 30},
    };

class FakeLauncher implements IntentLauncher {
  final List<String> opened = [];
  @override
  Future<bool> openUri(Uri uri) async {
    opened.add(uri.toString());
    return true;
  }

  @override
  Future<bool> openAndroidIntent({required String action, String? category, String? type, String? package}) async {
    opened.add('intent:$action${category == null ? '' : '#$category'}');
    return true;
  }
}

void main() {
  group('NavPlan validation (client-side defence in depth)', () {
    test('valid plan parses with steps, highlight and arrow', () {
      final p = NavPlan.fromJson(plan([step(params: {'contact': 'son'}), step(kind: 'external_hint', intent: null)]));
      expect(p.ok, isTrue);
      expect(p.steps.length, 2);
      expect(p.steps.first.intent, 'dial');
      expect(p.steps.first.highlight.w, 0.3);
      expect(p.steps.last.isExternal, isTrue);
    });

    test('unknown action kind makes the whole plan refused', () {
      final p = NavPlan.fromJson(plan([step(), step(kind: 'tap_coordinates', intent: null)]));
      expect(p.ok, isFalse);
      expect(p.steps, isEmpty);
    });

    test('intent outside the allow-list is refused', () {
      expect(NavPlan.fromJson(plan([step(intent: 'open_bank_app')])).ok, isFalse);
    });

    test('in-app route outside the allow-list is refused', () {
      expect(NavPlan.fromJson(plan([step(kind: 'in_app_route', intent: null, route: 'delete_everything')])).ok, isFalse);
      expect(NavPlan.fromJson(plan([step(kind: 'in_app_route', intent: null, route: 'scam_check')])).ok, isTrue);
    });

    test('more than 10 steps is refused', () {
      expect(NavPlan.fromJson(plan(List.generate(11, (_) => step()))).ok, isFalse);
    });

    test('highlight values are clamped to the screen', () {
      final s = step();
      s['highlight'] = {'x': -1, 'y': 5, 'w': 0.5, 'h': 2};
      final p = NavPlan.fromJson(plan([s]));
      expect(p.steps.first.highlight.x, 0);
      expect(p.steps.first.highlight.y, 1);
    });

    test('server refusal is passed through', () {
      final p = NavPlan.fromJson({'status': 'refused', 'reason': 'sensitive', 'message': {'en': 'no', 'ur': 'نہیں'}, 'steps': []});
      expect(p.ok, isFalse);
      expect(p.message['ur'], 'نہیں');
    });
  });

  group('Tier 1 intents', () {
    late FakeLauncher launcher;
    late NavigationService nav;

    setUp(() {
      launcher = FakeLauncher();
      final contacts = ContactsStore()
        ..contacts = [FamilyContact('Ali', '0300-1234567', 'son'), FamilyContact('Sara', '0321 7654321', 'daughter')];
      nav = NavigationService(contacts, launcher: launcher);
    });

    test('dial resolves the contact on the device', () async {
      expect(await nav.open('dial', params: {'contact': 'son'}), isTrue);
      expect(launcher.opened.last, 'tel:03001234567');
      await nav.open('dial', params: {'contact': null}, slots: {'relation': 'daughter'});
      expect(launcher.opened.last, 'tel:03217654321');
      await nav.open('dial', params: {'helper': '__device_helper__'});
      expect(launcher.opened.last, 'tel:03001234567');
    });

    test('WhatsApp chat uses an international number', () async {
      await nav.open('whatsapp_chat', params: {'contact': 'Ali'});
      expect(launcher.opened.last, 'https://wa.me/923001234567');
    });

    test('settings screens and maps', () async {
      await nav.open('settings_wifi');
      expect(launcher.opened.last, 'intent:android.settings.WIFI_SETTINGS');
      await nav.open('maps_search', params: {'destination': 'Jinnah Hospital'});
      expect(launcher.opened.last, 'geo:0,0?q=Jinnah%20Hospital');
    });

    test('anything outside the allow-list is never opened', () async {
      expect(await nav.open('open_bank_app'), isFalse);
      expect(await nav.open('factory_reset'), isFalse);
      expect(launcher.opened, isEmpty);
    });

    test('every home tile intent is allowed', () {
      for (final t in kHomeTiles) {
        if (t.intent != null) expect(kAllowedIntents, contains(t.intent));
      }
    });
  });
}
