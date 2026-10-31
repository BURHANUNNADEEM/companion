import 'dart:convert';

import 'config.dart';
import 'storage.dart';

/// On-device task suggestions (PRD F3, moved from backend to phone).
///
/// score(task) = 2 × P(task | last task) + 1 × share at this time of day
///             + 0.3 × overall share + small default prior.
/// Never executes anything; UI always also shows "Something else".
/// Backs off after N consecutive dismissals.
class SuggestionEngine {
  static const _key = '${storePrefix}suggestions';
  final CompanionConfig cfg;
  final KeyValueStore store;
  final Clock clock;
  final List<String> defaults;

  Map<String, Map<String, int>> _transitions = {};
  Map<String, Map<String, int>> _byBucket = {};
  Map<String, int> _totals = {};
  String? _lastTask;
  int _dismissStreak = 0;
  DateTime? _backoffUntil;

  SuggestionEngine(this.cfg, this.store, {required this.defaults, this.clock = systemClock}) {
    final raw = store.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, Map<String, int>> nested(Object? o) => (o as Map? ?? {}).map(
          (k, v) => MapEntry(k as String, (v as Map).map((a, b) => MapEntry(a as String, b as int))));
      _transitions = nested(j['transitions']);
      _byBucket = nested(j['byBucket']);
      _totals = (j['totals'] as Map? ?? {}).map((k, v) => MapEntry(k as String, v as int));
      _lastTask = j['last'] as String?;
    } catch (_) {}
  }

  static String bucketFor(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 12) return 'morning';
    if (h >= 12 && h < 17) return 'afternoon';
    if (h >= 17 && h < 22) return 'evening';
    return 'night';
  }

  bool get inBackoff => _backoffUntil != null && clock().isBefore(_backoffUntil!);

  /// Top tasks right now. Empty while backing off.
  List<String> suggest() {
    if (inBackoff) return const [];
    final bucket = bucketFor(clock());
    final trans = _lastTask == null ? const <String, int>{} : (_transitions[_lastTask] ?? const {});
    final transSum = trans.values.fold<int>(0, (a, b) => a + b);
    final bucketMap = _byBucket[bucket] ?? const <String, int>{};
    final bucketSum = bucketMap.values.fold<int>(0, (a, b) => a + b);
    final totalSum = _totals.values.fold<int>(0, (a, b) => a + b);

    final candidates = {...defaults, ..._totals.keys};
    final scored = candidates.map((t) {
      final prior = defaults.contains(t) ? 0.1 * (defaults.length - defaults.indexOf(t)) / defaults.length : 0.0;
      final s = (transSum == 0 ? 0 : 2.0 * (trans[t] ?? 0) / transSum) +
          (bucketSum == 0 ? 0 : 1.0 * (bucketMap[t] ?? 0) / bucketSum) +
          (totalSum == 0 ? 0 : 0.3 * (_totals[t] ?? 0) / totalSum) +
          prior;
      return MapEntry(t, s);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(cfg.maxSuggestions).map((e) => e.key).toList();
  }

  void recordCompleted(String taskId) {
    final bucket = bucketFor(clock());
    if (_lastTask != null) {
      final m = _transitions.putIfAbsent(_lastTask!, () => {});
      m[taskId] = (m[taskId] ?? 0) + 1;
    }
    final b = _byBucket.putIfAbsent(bucket, () => {});
    b[taskId] = (b[taskId] ?? 0) + 1;
    _totals[taskId] = (_totals[taskId] ?? 0) + 1;
    _lastTask = taskId;
    _save();
  }

  void recordAccepted() => _dismissStreak = 0;

  void recordDismissed() {
    _dismissStreak++;
    if (_dismissStreak >= cfg.backoffAfterDismissals) {
      _backoffUntil = clock().add(cfg.backoffDuration);
      _dismissStreak = 0;
    }
  }

  Future<void> reset() async {
    _transitions = {};
    _byBucket = {};
    _totals = {};
    _lastTask = null;
    _dismissStreak = 0;
    _backoffUntil = null;
    await store.remove(_key);
  }

  void _save() => store.setString(
      _key,
      jsonEncode({
        'transitions': _transitions,
        'byBucket': _byBucket,
        'totals': _totals,
        'last': _lastTask,
      }));
}
