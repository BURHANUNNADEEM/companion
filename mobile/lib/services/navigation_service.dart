import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import 'contacts_store.dart';

/// Opens a platform screen. Abstracted so tests can verify which intents are fired.
abstract class IntentLauncher {
  Future<bool> openUri(Uri uri);
  Future<bool> openAndroidIntent({required String action, String? category, String? type, String? package});
}

class PlatformIntentLauncher implements IntentLauncher {
  @override
  Future<bool> openUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openAndroidIntent({required String action, String? category, String? type, String? package}) async {
    try {
      await AndroidIntent(
        action: action,
        category: category,
        type: type,
        package: package,
        flags: const [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Tier 1 intent navigation (Play-safe, F10). ONLY the intents in [kAllowedIntents] can be opened;
/// anything else is refused. Contacts are resolved on the device and never leave it.
class NavigationService {
  NavigationService(this.contacts, {IntentLauncher? launcher}) : launcher = launcher ?? PlatformIntentLauncher();

  final ContactsStore contacts;
  final IntentLauncher launcher;

  static String digits(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

  /// WhatsApp needs international format without '+': 03001234567 -> 923001234567.
  static String waNumber(String phone) {
    var d = digits(phone).replaceAll('+', '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = '92${d.substring(1)}';
    return d;
  }

  Future<bool> open(String intent, {Map<String, dynamic> params = const {}, Map<String, dynamic> slots = const {}}) async {
    if (!kAllowedIntents.contains(intent)) return false;
    String? phone;
    final contactParam = params.containsKey('helper') ? '__device_helper__' : params['contact'] as String?;
    if (params.containsKey('helper') || params.containsKey('contact')) {
      phone = contacts.resolve(contact: contactParam, relation: slots['relation'] as String?);
    }
    switch (intent) {
      case 'dial':
        return launcher.openUri(Uri(scheme: 'tel', path: phone == null ? '' : digits(phone)));
      case 'sms':
        return launcher.openUri(Uri(scheme: 'sms', path: phone == null ? '' : digits(phone)));
      case 'gallery':
        return launcher.openAndroidIntent(action: 'android.intent.action.MAIN', category: 'android.intent.category.APP_GALLERY');
      case 'camera':
        return launcher.openAndroidIntent(action: 'android.media.action.STILL_IMAGE_CAMERA');
      case 'whatsapp_chat':
        if (phone != null) return launcher.openUri(Uri.parse('https://wa.me/${waNumber(phone)}'));
        return launcher.openUri(Uri.parse('whatsapp://send'));
      case 'whatsapp_open':
        return launcher.openUri(Uri.parse('whatsapp://send'));
      case 'settings_wifi':
        return launcher.openAndroidIntent(action: 'android.settings.WIFI_SETTINGS');
      case 'settings_bluetooth':
        return launcher.openAndroidIntent(action: 'android.settings.BLUETOOTH_SETTINGS');
      case 'settings_sound':
        return launcher.openAndroidIntent(action: 'android.settings.SOUND_SETTINGS');
      case 'settings_display':
        return launcher.openAndroidIntent(action: 'android.settings.DISPLAY_SETTINGS');
      case 'maps_search':
        final dest = (params['destination'] as String?) ?? '';
        return launcher.openUri(Uri.parse(dest.isEmpty ? 'geo:0,0' : 'geo:0,0?q=${Uri.encodeComponent(dest)}'));
    }
    return false;
  }
}
