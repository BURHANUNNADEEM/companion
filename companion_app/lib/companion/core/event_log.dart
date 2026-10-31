import 'dart:convert';
import 'dart:math';

import 'models.dart';
import 'storage.dart';

/// Consent choices (PRD F5). Nothing is logged before [tracking] is true.
class Consent {
  final bool tracking;
  final bool caregiverSharing;
  const Consent({this.tracking = false, this.caregiverSharing = false});
  static const none = Consent();
  Map<String, Object> toJson() => {'tracking': tracking, 'caregiverSharing': caregiverSharing};
  factory Consent.fromJson(Map<String, dynamic> j) => Consent(
        tracking: j['tracking'] as bool? ?? false,
        caregiverSharing: j['caregiverSharing'] as bool? ?? false,
      );
}

/// On-device event log. Stores the last [maxEvents] events only, actions only.
class EventLog {
  static const _eventsKey = '${storePrefix}events';
  static const _consentKey = '${storePrefix}consent';
  final KeyValueStore store;
  final Clock clock;
  final int maxEvents;
  final String sessionId;
  final List<AppEvent> _events = [];
  Consent _consent = Consent.none;

  EventLog(this.store, {this.clock = systemClock, this.maxEvents = 2000})
      : sessionId = _newSessionId() {
    final c = store.getString(_consentKey);
    if (c != null) _consent = Consent.fromJson(jsonDecode(c) as Map<String, dynamic>);
    final raw = store.getString(_eventsKey);
    if (raw != null) {
      try {
        _events.addAll((jsonDecode(raw) as List)
            .map((e) => AppEvent.fromJson(e as Map<String, dynamic>)));
      } catch (_) {/* corrupted → start fresh */}
    }
  }

  static String _newSessionId() =>
      '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  Consent get consent => _consent;
  List<AppEvent> get events => List.unmodifiable(_events);

  Future<void> setConsent(Consent c) async {
    _consent = c;
    await store.setString(_consentKey, jsonEncode(c.toJson()));
  }

  /// Logs only if tracking consent was given. Returns the event (or null).
  AppEvent? log(String type, [Map<String, Object?> props = const {}]) {
    if (!_consent.tracking) return null;
    final e = AppEvent(type, clock(), sessionId, props);
    _events.add(e);
    if (_events.length > maxEvents) _events.removeRange(0, _events.length - maxEvents);
    _persistSoon();
    return e;
  }

  bool _dirty = false;
  void _persistSoon() {
    if (_dirty) return;
    _dirty = true;
    Future.microtask(() async {
      _dirty = false;
      await store.setString(_eventsKey, jsonEncode(_events.map((e) => e.toJson()).toList()));
    });
  }

  Iterable<AppEvent> ofType(String type) => _events.where((e) => e.type == type);

  Future<void> clearEvents() async {
    _events.clear();
    await store.remove(_eventsKey);
  }
}
