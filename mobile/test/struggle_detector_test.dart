import 'package:companion/services/struggle_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD F2 acceptance: each rule can be triggered in a scripted test, threshold adjustable without code change.
void main() {
  late DateTime now;
  StruggleDetector make([StruggleConfig? c]) => StruggleDetector(config: c, clock: () => now);
  void wait(int seconds) => now = now.add(Duration(seconds: seconds));
  // A threshold of 0.1 lets every single signal trigger on its own.
  const lowThreshold = StruggleConfig(threshold: 0.1);

  setUp(() => now = DateTime(2026, 10, 31, 9));

  test('backtracking: 3 backs within 20 s', () {
    final d = make(lowThreshold);
    d.onScreen('home');
    d.onBack();
    wait(5);
    d.onBack();
    expect(d.activeSignals(), isNot(contains('backtracking')));
    wait(5);
    d.onBack();
    expect(d.activeSignals(), contains('backtracking'));
    expect(d.evaluate()!.signals, contains('backtracking'));
  });

  test('backs spread over more than 20 s do not count', () {
    final d = make(lowThreshold);
    d.onBack();
    wait(15);
    d.onBack();
    wait(15);
    d.onBack();
    expect(d.activeSignals(), isNot(contains('backtracking')));
  });

  test('idle: 10 s on a screen without a tap', () {
    final d = make(lowThreshold);
    d.onScreen('home');
    wait(9);
    expect(d.activeSignals(), isNot(contains('idle')));
    wait(1);
    expect(d.activeSignals(), contains('idle'));
    expect(d.evaluate()!.signals, contains('idle'));
  });

  test('repeated taps: same target 3 times in 5 s', () {
    final d = make(lowThreshold);
    d.onTap('tile_call');
    wait(1);
    d.onTap('tile_photos');
    d.onTap('tile_call');
    wait(1);
    expect(d.activeSignals(), isNot(contains('repeated_taps')));
    d.onTap('tile_call');
    expect(d.activeSignals(), contains('repeated_taps'));
  });

  test('looping: the same 2-3 screens visited repeatedly', () {
    final d = make(lowThreshold);
    for (final s in ['home', 'settings', 'home', 'settings']) {
      d.onScreen(s);
      wait(2);
    }
    expect(d.activeSignals(), isNot(contains('looping')));
    d.onScreen('home');
    expect(d.activeSignals(), contains('looping'));
  });

  test('no completion: 45 s of navigation without finishing a task', () {
    final d = make(lowThreshold);
    d.onScreen('home');
    for (var i = 0; i < 44; i++) {
      wait(1);
      d.onActivity();
    }
    expect(d.activeSignals(), isNot(contains('no_completion')));
    wait(1);
    expect(d.activeSignals(), contains('no_completion'));
  });

  test('task completion resets navigation time', () {
    final d = make(lowThreshold);
    d.onScreen('home');
    wait(40);
    d.onTaskCompleted();
    wait(10);
    expect(d.activeSignals(), isNot(contains('no_completion')));
  });

  test('default weights: idle alone does not trigger, backtracking does', () {
    final d = make();
    d.onScreen('home');
    wait(12);
    expect(d.activeSignals(), ['idle']);
    expect(d.evaluate(), isNull);
    d.onBack();
    d.onBack();
    d.onBack();
    final r = d.evaluate();
    expect(r, isNotNull);
    expect(r!.score, greaterThanOrEqualTo(0.8));
  });

  test('cool-down prevents repeated prompts', () {
    final d = make(lowThreshold);
    d.onBack();
    d.onBack();
    d.onBack();
    expect(d.evaluate(), isNotNull);
    d.onBack();
    d.onBack();
    d.onBack();
    expect(d.evaluate(), isNull);
    wait(61);
    d.onBack();
    d.onBack();
    d.onBack();
    expect(d.evaluate(), isNotNull);
  });

  test('paused detector never triggers', () {
    final d = make(lowThreshold)..paused = true;
    d.onBack();
    d.onBack();
    d.onBack();
    expect(d.evaluate(), isNull);
  });

  test('threshold and rules come from the server config (no code change)', () {
    final cfg = StruggleConfig.fromJson({
      'threshold': 2.0,
      'cooldown_s': 5,
      'weights': {'backtracking': 0.5},
      'rules': {'back_count': 2, 'idle_s': 30},
    });
    expect(cfg.threshold, 2.0);
    expect(cfg.backCount, 2);
    expect(cfg.idleS, 30);
    expect(cfg.weights['backtracking'], 0.5);
    expect(cfg.weights['idle'], 0.5); // default kept
    final d = make(cfg);
    d.onBack();
    d.onBack();
    expect(d.activeSignals(), contains('backtracking'));
    expect(d.evaluate(), isNull); // 0.5 < 2.0
  });
}
