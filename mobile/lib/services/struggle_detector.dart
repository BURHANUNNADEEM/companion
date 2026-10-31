/// On-device struggle detection (F2). Pure Dart, no plugins, injectable clock -> fully testable.
///
/// Signals (PRD defaults, all adjustable from the backend /api/config without a code change):
///   backtracking   : >= 3 back actions within 20 s
///   idle           : >= 10 s on a screen without a tap
///   repeated_taps  : same target tapped >= 3 times within 5 s
///   looping        : the same 2-3 screens visited repeatedly
///   no_completion  : >= 45 s of navigation without completing a task
/// A weighted score >= threshold triggers a suggestion (with a cool-down).
class StruggleConfig {
  const StruggleConfig({
    this.threshold = 0.8,
    this.cooldownS = 60,
    this.weights = const {
      'backtracking': 0.8,
      'idle': 0.5,
      'repeated_taps': 0.8,
      'looping': 0.6,
      'no_completion': 0.4,
    },
    this.backCount = 3,
    this.backWindowS = 20,
    this.idleS = 10,
    this.repeatTaps = 3,
    this.repeatWindowS = 5,
    this.loopVisits = 3,
    this.noCompletionS = 45,
  });

  final double threshold;
  final int cooldownS;
  final Map<String, double> weights;
  final int backCount, backWindowS, idleS, repeatTaps, repeatWindowS, loopVisits, noCompletionS;

  factory StruggleConfig.fromJson(Map<String, dynamic> j) {
    const d = StruggleConfig();
    final w = Map<String, dynamic>.from(j['weights'] as Map? ?? {});
    final r = Map<String, dynamic>.from(j['rules'] as Map? ?? {});
    int i(String k, int def) => (r[k] as num?)?.toInt() ?? def;
    return StruggleConfig(
      threshold: (j['threshold'] as num?)?.toDouble() ?? d.threshold,
      cooldownS: (j['cooldown_s'] as num?)?.toInt() ?? d.cooldownS,
      weights: {for (final e in d.weights.entries) e.key: (w[e.key] as num?)?.toDouble() ?? e.value},
      backCount: i('back_count', d.backCount),
      backWindowS: i('back_window_s', d.backWindowS),
      idleS: i('idle_s', d.idleS),
      repeatTaps: i('repeat_taps', d.repeatTaps),
      repeatWindowS: i('repeat_window_s', d.repeatWindowS),
      loopVisits: i('loop_visits', d.loopVisits),
      noCompletionS: i('no_completion_s', d.noCompletionS),
    );
  }
}

class StruggleResult {
  StruggleResult(this.score, this.signals, this.screen);
  final double score;
  final List<String> signals;
  final String? screen;
  @override
  String toString() => 'StruggleResult($score, $signals)';
}

typedef Clock = DateTime Function();

class StruggleDetector {
  StruggleDetector({StruggleConfig? config, Clock? clock})
      : config = config ?? const StruggleConfig(),
        _now = clock ?? DateTime.now;

  StruggleConfig config;
  final Clock _now;

  final List<DateTime> _backs = [];
  final List<MapEntry<String, DateTime>> _taps = [];
  final List<MapEntry<String, DateTime>> _screens = [];
  DateTime? _lastInteraction;
  DateTime? _navStart;
  DateTime? _lastTrigger;
  String? _currentScreen;
  bool paused = false;

  void onScreen(String name) {
    final now = _now();
    _currentScreen = name;
    _screens.add(MapEntry(name, now));
    if (_screens.length > 12) _screens.removeAt(0);
    _touch(now);
  }

  void onTap(String target) {
    final now = _now();
    _taps.add(MapEntry(target, now));
    if (_taps.length > 20) _taps.removeAt(0);
    _touch(now);
  }

  void onBack() {
    final now = _now();
    _backs.add(now);
    if (_backs.length > 20) _backs.removeAt(0);
    _touch(now);
  }

  /// Any touch (not a specific target): resets the idle timer only.
  void onActivity() {
    _lastInteraction = _now();
  }

  /// Task finished: the user is not lost any more.
  void onTaskCompleted() => reset();

  void reset() {
    _backs.clear();
    _taps.clear();
    _screens.clear();
    _navStart = null;
    _lastInteraction = _now();
  }

  void _touch(DateTime now) {
    _lastInteraction = now;
    _navStart ??= now;
  }

  /// Which signals are active right now (no threshold / cooldown applied).
  List<String> activeSignals() {
    final now = _now();
    final c = config;
    final out = <String>[];
    final recentBacks = _backs.where((t) => now.difference(t).inMilliseconds <= c.backWindowS * 1000).length;
    if (recentBacks >= c.backCount) out.add('backtracking');

    if (_lastInteraction != null && now.difference(_lastInteraction!).inSeconds >= c.idleS) out.add('idle');

    final recentTaps = _taps.where((e) => now.difference(e.value).inMilliseconds <= c.repeatWindowS * 1000);
    final counts = <String, int>{};
    for (final e in recentTaps) {
      counts[e.key] = (counts[e.key] ?? 0) + 1;
    }
    if (counts.values.any((n) => n >= c.repeatTaps)) out.add('repeated_taps');

    final recentScreens = _screens.where((e) => now.difference(e.value).inSeconds <= 90).map((e) => e.key).toList();
    if (recentScreens.length >= c.loopVisits * 2 - 1) {
      final distinct = recentScreens.toSet();
      final visits = <String, int>{};
      for (final s in recentScreens) {
        visits[s] = (visits[s] ?? 0) + 1;
      }
      if (distinct.length >= 2 && distinct.length <= 3 && visits.values.any((n) => n >= c.loopVisits)) {
        out.add('looping');
      }
    }

    if (_navStart != null && now.difference(_navStart!).inSeconds >= c.noCompletionS) out.add('no_completion');
    return out;
  }

  double scoreOf(List<String> signals) =>
      signals.fold(0.0, (sum, s) => sum + (config.weights[s] ?? 0));

  /// Call about once a second and after every input. Returns a result when help should be offered.
  StruggleResult? evaluate() {
    if (paused) return null;
    final now = _now();
    if (_lastTrigger != null && now.difference(_lastTrigger!).inSeconds < config.cooldownS) return null;
    final signals = activeSignals();
    final score = scoreOf(signals);
    if (signals.isEmpty || score < config.threshold) return null;
    _lastTrigger = now;
    final result = StruggleResult(double.parse(score.toStringAsFixed(2)), signals, _currentScreen);
    // start fresh so one episode is reported once
    _backs.clear();
    _taps.clear();
    _screens.clear();
    _navStart = now;
    _lastInteraction = now;
    return result;
  }
}
