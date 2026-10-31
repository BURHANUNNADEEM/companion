import 'config.dart';
import 'models.dart';
import 'storage.dart';

/// On-device struggle detection (PRD F2).
///
/// Feed it every screen view, tap and back press. Call [evaluate] on each
/// event and once per second (idle check). Idle is measured against the
/// user's OWN pace: once we have 3+ step timings, the idle threshold becomes
/// median step time × [CompanionConfig.idleBaselineMultiplier], clamped to
/// [idleMin, idleMax]. Older users are allowed to be slow; only a change
/// from their usual pace counts.
class StruggleDetector {
  final CompanionConfig cfg;
  final Clock clock;

  final List<DateTime> _backs = [];
  final List<MapEntry<String, DateTime>> _taps = [];
  final List<MapEntry<String, DateTime>> _screens = [];
  final List<Duration> _paceSamples = [];
  String? _currentScreen;
  DateTime _lastActivity;
  DateTime _stepStart;
  DateTime? _navStart;
  int _wrongTaps = 0;
  DateTime? _cooldownUntil;

  /// True while a guided task is running. When false (just browsing the home
  /// screen) idle needs the longer [CompanionConfig.idleMax] before it counts.
  bool guided = false;

  StruggleDetector(this.cfg, {this.clock = systemClock})
      : _lastActivity = clock(),
        _stepStart = clock();

  // ---------------- inputs ----------------
  void onScreen(String screenId) {
    final now = clock();
    _currentScreen = screenId;
    _screens.add(MapEntry(screenId, now));
    _touch(now);
  }

  void onTap(String targetId, {bool wrong = false}) {
    final now = clock();
    _taps.add(MapEntry(targetId, now));
    if (wrong) _wrongTaps++;
    _touch(now);
  }

  void onBack() {
    final now = clock();
    _backs.add(now);
    _touch(now);
  }

  /// Call when the user correctly completes a guided step.
  void onStepSuccess() {
    final now = clock();
    final d = now.difference(_stepStart);
    if (d > Duration.zero && d < const Duration(minutes: 3)) {
      _paceSamples.add(d);
      if (_paceSamples.length > 30) _paceSamples.removeAt(0);
    }
    _stepStart = now;
    _wrongTaps = 0;
    _touch(now);
  }

  /// Call when a task finishes or a new one starts.
  void resetEpisode() {
    final now = clock();
    _backs.clear();
    _taps.clear();
    _screens.clear();
    _wrongTaps = 0;
    _navStart = null;
    _stepStart = now;
    _lastActivity = now;
  }

  /// Call after help was shown, so the same signals don't fire again at once.
  void acknowledge() {
    final now = clock();
    _backs.clear();
    _taps.clear();
    _screens.clear();
    _wrongTaps = 0;
    _lastActivity = now;
    _navStart = now;
    _cooldownUntil = now.add(cfg.cooldown);
  }

  void _touch(DateTime now) {
    _lastActivity = now;
    _navStart ??= now;
  }

  // ---------------- personal pace ----------------
  Duration get idleThreshold {
    if (!guided) return cfg.idleMax;
    if (_paceSamples.length < 3) return cfg.idleMin;
    final sorted = [..._paceSamples]..sort();
    final median = sorted[sorted.length ~/ 2];
    final t = median * cfg.idleBaselineMultiplier;
    if (t < cfg.idleMin) return cfg.idleMin;
    if (t > cfg.idleMax) return cfg.idleMax;
    return t;
  }

  List<int> get paceSamplesMs => _paceSamples.map((d) => d.inMilliseconds).toList();
  void loadPace(List<int> ms) {
    _paceSamples
      ..clear()
      ..addAll(ms.map((m) => Duration(milliseconds: m)));
  }

  // ---------------- evaluation ----------------
  StruggleResult evaluate() {
    final now = clock();
    _prune(now);
    final s = <StruggleSignal>{};

    if (_backs.length >= cfg.backtrackCount) s.add(StruggleSignal.backtracking);

    if (_currentScreen != null && now.difference(_lastActivity) >= idleThreshold) {
      s.add(StruggleSignal.idle);
    }

    final tapCounts = <String, int>{};
    for (final t in _taps) {
      tapCounts[t.key] = (tapCounts[t.key] ?? 0) + 1;
    }
    if (tapCounts.values.any((c) => c >= cfg.repeatedTapCount)) {
      s.add(StruggleSignal.repeatedTaps);
    }

    final screenCounts = <String, int>{};
    for (final v in _screens) {
      screenCounts[v.key] = (screenCounts[v.key] ?? 0) + 1;
    }
    if (screenCounts.length >= 2 && screenCounts.values.any((c) => c >= cfg.loopVisits)) {
      s.add(StruggleSignal.looping);
    }

    if (_navStart != null && now.difference(_navStart!) >= cfg.noCompletion) {
      s.add(StruggleSignal.noCompletion);
    }

    if (_wrongTaps >= cfg.wrongTapCount) s.add(StruggleSignal.wrongTaps);

    var score = 0.0;
    for (final sig in s) {
      score += cfg.weights[sig.name] ?? 1.0;
    }
    final cooling = _cooldownUntil != null && now.isBefore(_cooldownUntil!);
    return StruggleResult(score, s, !cooling && score >= cfg.triggerThreshold);
  }

  void _prune(DateTime now) {
    _backs.removeWhere((t) => now.difference(t) > cfg.backtrackWindow);
    _taps.removeWhere((t) => now.difference(t.value) > cfg.repeatedTapWindow);
    _screens.removeWhere((t) => now.difference(t.value) > cfg.loopWindow);
  }
}
