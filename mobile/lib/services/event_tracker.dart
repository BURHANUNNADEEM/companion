import 'dart:async';

import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'struggle_detector.dart';

/// Buffers ACTION-ONLY events and uploads them in batches (F2).
/// Nothing is recorded (not even in memory) until the user has consented to activity tracking.
class EventTracker {
  EventTracker(this.api, this.detector);

  final ApiClient api;
  final StruggleDetector detector;
  final String sessionId = const Uuid().v4().replaceAll('-', '').substring(0, 24);
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _timer;
  bool _enabled = false;

  bool get enabled => _enabled;

  set enabled(bool v) {
    _enabled = v;
    if (!v) _buffer.clear();
    _timer?.cancel();
    if (v) _timer = Timer.periodic(const Duration(seconds: 15), (_) => flush());
  }

  void log(String type, {String? itemId, Map<String, Object?> props = const {}}) {
    if (!_enabled) return;
    _buffer.add({
      'type': type,
      if (itemId != null) 'item_id': itemId,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'properties': {for (final e in props.entries) if (e.value != null) e.key: e.value},
    });
    if (_buffer.length > 500) _buffer.removeRange(0, _buffer.length - 500);
    if (_buffer.length >= 20) flush();
  }

  // Convenience wrappers that also feed the on-device struggle detector.
  void screen(String name) {
    detector.onScreen(name);
    log('screen_view', props: {'screen': name});
  }

  void tap(String target, {String? screen}) {
    detector.onTap(target);
    log('tap', itemId: target, props: {'target': target, 'screen': screen});
  }

  void back({String? screen}) {
    detector.onBack();
    log('back', props: {'screen': screen});
  }

  void taskStarted(String task) => log('task_started', itemId: task, props: {'task': task});

  void taskCompleted(String task, {String? source}) {
    detector.onTaskCompleted();
    log('task_completed', itemId: task, props: {'task': task, 'hour': DateTime.now().hour, 'source': source});
  }

  Future<void> flush() async {
    if (!_enabled || _buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      await api.post('/events', {'session_id': sessionId, 'events': batch});
    } on ApiException catch (e) {
      if (e.status == 403) {
        _enabled = false; // consent withdrawn on another device
        return;
      }
      if (e.isOffline || e.status >= 500) _buffer.insertAll(0, batch); // retry later
    }
  }

  void dispose() => _timer?.cancel();
}
