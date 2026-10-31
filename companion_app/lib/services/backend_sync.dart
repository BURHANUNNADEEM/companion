import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../api.dart';
import '../companion/companion.dart';

/// Best-effort sync with the FastAPI backend. The app works fully offline:
/// every call here is wrapped so a network failure never breaks the UI.
class BackendSync {
  final CompanionController c;
  BackendSync(this.c);

  Timer? _timer;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool lastCallOk = false;

  static const _timeout = Duration(seconds: 6);

  bool get _signedIn => FirebaseAuth.instance.currentUser != null;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => flushEvents());
  }

  void stop() => _timer?.cancel();

  /// Uploads events created since the last successful upload (actions only).
  Future<void> flushEvents() async {
    if (_busy || !_signedIn || !c.consent.tracking) return;
    final pending = c.engine.log.events.where((e) => e.at.isAfter(_lastSent)).take(500).toList();
    if (pending.isEmpty) return;
    _busy = true;
    try {
      final sid = c.engine.log.sessionId;
      final body = {
        'session_id': sid.length > 60 ? sid.substring(0, 60) : sid,
        'events': [
          for (final e in pending)
            {
              'event_type': e.type,
              'item_id': (e.props['task'] ?? e.props['target'] ?? e.props['screen'])?.toString(),
              'properties': _jsonSafe(e.props),
              'occurred_at': e.at.toUtc().toIso8601String(),
            }
        ],
      };
      final r = await apiPost('/api/events/batch', body).timeout(_timeout);
      lastCallOk = r.statusCode == 201;
      if (lastCallOk) _lastSent = pending.last.at;
    } catch (e) {
      lastCallOk = false;
      debugPrint('event sync failed: $e');
    } finally {
      _busy = false;
    }
  }

  Map<String, dynamic> _jsonSafe(Map<String, Object?> m) =>
      jsonDecode(jsonEncode(m, toEncodable: (o) => o.toString())) as Map<String, dynamic>;

  Future<void> putConsent({required bool tracking, required bool ai}) async {
    if (!_signedIn) return;
    try {
      await apiPut('/api/consent', {'tracking': tracking, 'ai_processing': ai}).timeout(_timeout);
    } catch (e) {
      debugPrint('consent sync failed: $e');
    }
  }

  /// Server scam check (rules + optional Gemini). Returns null when offline.
  Future<Map<String, dynamic>?> scamCheck(String text) async {
    if (!_signedIn) return null;
    try {
      final r = await apiPost('/api/scam/check', {'text': text, 'source': 'paste'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('scam check offline: $e');
      return null;
    }
  }

  /// Records task outcome on the server so progress is kept across devices.
  Future<void> reportTaskCompleted(String taskId, {required bool clean}) async {
    if (!_signedIn || !c.consent.tracking) return;
    try {
      final r = await apiPost('/api/tasks/$taskId/start', {}).timeout(_timeout);
      if (r.statusCode != 201) return;
      final id = (jsonDecode(r.body) as Map<String, dynamic>)['attempt_id'];
      if (!clean) {
        await apiPost('/api/tasks/attempts/$id/struggle', {'step_index': 0}).timeout(_timeout);
      }
      await apiPost('/api/tasks/attempts/$id/complete', {}).timeout(_timeout);
    } catch (e) {
      debugPrint('task sync failed: $e');
    }
  }

  Future<bool> deleteServerData() async {
    if (!_signedIn) return false;
    try {
      final r = await apiDelete('/api/me/data', {'confirm': 'DELETE'}).timeout(_timeout);
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('delete failed: $e');
      return false;
    }
  }

  Future<bool> ping() async {
    try {
      final r = await apiGet('/api/me').timeout(_timeout);
      lastCallOk = r.statusCode == 200;
    } catch (_) {
      lastCallOk = false;
    }
    return lastCallOk;
  }
}
