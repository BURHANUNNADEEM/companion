/// All tunable numbers in one place (PRD F2: thresholds adjustable without
/// code changes — load from settings JSON via [CompanionConfig.fromJson]).
class CompanionConfig {
  // --- Struggle detection (PRD F2) ---
  final int backtrackCount; // >= N backs ...
  final Duration backtrackWindow; // ... within this window
  final Duration idleMin; // idle threshold never below this
  final Duration idleMax; // ... and never above this
  final double idleBaselineMultiplier; // personal pace × this = idle threshold
  final int repeatedTapCount;
  final Duration repeatedTapWindow;
  final int loopVisits; // same screen visited N times in loop window
  final Duration loopWindow;
  final Duration noCompletion;
  final int wrongTapCount; // taps off the guided target in one step

  /// Weighted score at/above which struggle triggers.
  final double triggerThreshold;
  final Map<String, double> weights;

  /// Quiet time after help is shown before it can be raised again.
  final Duration cooldown;

  // --- Help ladder ---
  final int successesForHighlight; // clean completions to drop from full → highlight
  final int successesForNone; // ... to drop to none
  final int successesForMastery; // ... to award 🌳

  // --- Suggestions (PRD F3) ---
  final int maxSuggestions;
  final int backoffAfterDismissals;
  final Duration backoffDuration;

  const CompanionConfig({
    this.backtrackCount = 3,
    this.backtrackWindow = const Duration(seconds: 20),
    this.idleMin = const Duration(seconds: 8),
    this.idleMax = const Duration(seconds: 20),
    this.idleBaselineMultiplier = 2.5,
    this.repeatedTapCount = 3,
    this.repeatedTapWindow = const Duration(seconds: 5),
    this.loopVisits = 3,
    this.loopWindow = const Duration(seconds: 40),
    this.noCompletion = const Duration(seconds: 45),
    this.wrongTapCount = 2,
    this.triggerThreshold = 1.0,
    this.weights = const {
      'backtracking': 1.0,
      'idle': 1.0,
      'repeatedTaps': 1.0,
      'looping': 0.7,
      'noCompletion': 0.6,
      'wrongTaps': 1.0,
    },
    this.cooldown = const Duration(seconds: 6),
    this.successesForHighlight = 1,
    this.successesForNone = 3,
    this.successesForMastery = 3,
    this.maxSuggestions = 3,
    this.backoffAfterDismissals = 3,
    this.backoffDuration = const Duration(minutes: 10),
  });

  /// Faster thresholds so struggle can be shown live in a 2-minute demo.
  static const demo = CompanionConfig(
    idleMin: Duration(seconds: 5),
    idleMax: Duration(seconds: 8),
    noCompletion: Duration(seconds: 25),
    cooldown: Duration(seconds: 4),
  );

  factory CompanionConfig.fromJson(Map<String, dynamic> j) {
    const d = CompanionConfig();
    Duration s(String k, Duration def) =>
        j[k] == null ? def : Duration(milliseconds: ((j[k] as num) * 1000).round());
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    return CompanionConfig(
      backtrackCount: i('backtrackCount', d.backtrackCount),
      backtrackWindow: s('backtrackWindowSec', d.backtrackWindow),
      idleMin: s('idleMinSec', d.idleMin),
      idleMax: s('idleMaxSec', d.idleMax),
      idleBaselineMultiplier:
          (j['idleBaselineMultiplier'] as num?)?.toDouble() ?? d.idleBaselineMultiplier,
      repeatedTapCount: i('repeatedTapCount', d.repeatedTapCount),
      repeatedTapWindow: s('repeatedTapWindowSec', d.repeatedTapWindow),
      loopVisits: i('loopVisits', d.loopVisits),
      loopWindow: s('loopWindowSec', d.loopWindow),
      noCompletion: s('noCompletionSec', d.noCompletion),
      wrongTapCount: i('wrongTapCount', d.wrongTapCount),
      triggerThreshold: (j['triggerThreshold'] as num?)?.toDouble() ?? d.triggerThreshold,
      weights: j['weights'] == null
          ? d.weights
          : (j['weights'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      cooldown: s('cooldownSec', d.cooldown),
      successesForHighlight: i('successesForHighlight', d.successesForHighlight),
      successesForNone: i('successesForNone', d.successesForNone),
      successesForMastery: i('successesForMastery', d.successesForMastery),
      maxSuggestions: i('maxSuggestions', d.maxSuggestions),
      backoffAfterDismissals: i('backoffAfterDismissals', d.backoffAfterDismissals),
      backoffDuration: s('backoffSec', d.backoffDuration),
    );
  }
}
