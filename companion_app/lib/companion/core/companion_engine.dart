import 'dart:async';
import 'dart:convert';

import 'caregiver_summary.dart';
import 'config.dart';
import 'event_log.dart';
import 'help_ladder.dart';
import 'models.dart';
import 'scam_checker.dart';
import 'storage.dart';
import 'struggle_detector.dart';
import 'suggestion_engine.dart';
import 'task_flows.dart';

/// Result of a tap, so the UI knows what to do next.
class TapOutcome {
  /// The tap was the step Companion was guiding to.
  final bool wasGuidedStep;

  /// The task finished with this tap.
  final bool taskCompleted;

  /// Real-world action to run now (open dialer / WhatsApp). Null for practice.
  final LaunchAction? launch;

  /// For practice tasks: offer a "Now try it for real" button that runs this.
  final LaunchAction? tryForReal;
  const TapOutcome({
    this.wasGuidedStep = false,
    this.taskCompleted = false,
    this.launch,
    this.tryForReal,
  });
  static const plain = TapOutcome();
}

/// The brain of Companion. Pure Dart. The UI:
///  1. calls [onScreen] when a screen appears, [onTap] for every tap on a
///     registered target, [onBack] on back presses, [tick] once per second;
///  2. renders [state] / listens to [states];
///  3. runs [TapOutcome.launch] with the launcher and speaks [GuidanceState.speakUr].
class CompanionEngine {
  final CompanionConfig cfg;
  final KeyValueStore store;
  final TaskCatalog catalog;
  final Clock clock;

  late final EventLog log;
  late final HelpLadder ladder;
  late final SuggestionEngine suggestions;
  late final StruggleDetector detector;
  final ScamChecker scam = ScamChecker();

  final _ctrl = StreamController<GuidanceState>.broadcast();
  GuidanceState _state = GuidanceState.idle;

  // active run
  TaskFlow? _task;
  int _step = 0;
  HelpLevel _runStart = HelpLevel.none;
  HelpLevel _level = HelpLevel.none;
  bool _runClean = true;
  String? _screen;
  List<String> _suggested = const [];

  static const _paceKey = '${storePrefix}pace';

  CompanionEngine({
    required this.store,
    required this.catalog,
    this.cfg = const CompanionConfig(),
    this.clock = systemClock,
  }) {
    log = EventLog(store, clock: clock);
    ladder = HelpLadder(cfg, store, clock: clock);
    suggestions = SuggestionEngine(cfg, store, defaults: TaskIds.all, clock: clock);
    detector = StruggleDetector(cfg, clock: clock);
    final pace = store.getString(_paceKey);
    if (pace != null) {
      try {
        detector.loadPace((jsonDecode(pace) as List).cast<int>());
      } catch (_) {}
    }
  }

  // ============================== outputs ==============================
  GuidanceState get state => _state;
  Stream<GuidanceState> get states => _ctrl.stream;
  String? get activeTaskId => _task?.id;
  Consent get consent => log.consent;
  SkillStage stageOf(String taskId) => ladder.stage(taskId);

  // ============================== consent ==============================
  Future<void> setConsent(Consent c) => log.setConsent(c);

  // ============================== inputs ==============================
  void onScreen(String screenId) {
    _screen = screenId;
    detector.onScreen(screenId);
    log.log(EventTypes.screenView, {'screen': screenId});
    if (_task != null) _syncStepToScreen();
    _evaluate(emitAnyway: true);
  }

  void onBack() {
    detector.onBack();
    log.log(EventTypes.back, {'screen': _screen});
    _evaluate();
  }

  /// Call every second from a Timer (idle detection).
  void tick() => _evaluate();

  TapOutcome onTap(String targetId) {
    log.log(EventTypes.tap, {'target': targetId, 'screen': _screen});

    // Tapped a home tile → start (or switch to) that task.
    final tileTask = catalog.taskForHomeTile(targetId);
    if (tileTask != null && (_task == null || _task!.id != tileTask || _step == 0)) {
      if (_suggested.contains(tileTask)) {
        suggestions.recordAccepted();
        log.log(EventTypes.suggestionAccepted, {'task': tileTask});
      }
      _suggested = const [];
      if (_task != null && _task!.id != tileTask) {
        log.log(EventTypes.taskAbandoned, {'task': _task!.id, 'step': _step});
      }
      if (_task?.id != tileTask) _beginTask(tileTask);
      detector.onTap(targetId);
      return _advance(); // tile tap = step 0 done
    }

    final t = _task;
    if (t != null && _step < t.steps.length && t.steps[_step].targetId == targetId) {
      detector.onTap(targetId);
      return _advance();
    }

    // A tap that is not the guided target, on the guided screen = wrong tap.
    final wrong = t != null && _step < t.steps.length && t.steps[_step].screenId == _screen;
    detector.onTap(targetId, wrong: wrong);
    if (wrong) log.log(EventTypes.wrongTap, {'task': t.id, 'step': _step});
    _evaluate(emitAnyway: true);
    return TapOutcome.plain;
  }

  /// User picked a suggestion from the "Need a hand?" sheet.
  void acceptSuggestion(String taskId) {
    suggestions.recordAccepted();
    log.log(EventTypes.suggestionAccepted, {'task': taskId});
    _suggested = const [];
    _beginTask(taskId, atLeast: HelpLevel.highlight);
    _emit(speak: _level.speaks);
  }

  /// "Not now" on any help.
  void dismissHelp() {
    if (_suggested.isNotEmpty) {
      suggestions.recordDismissed();
      log.log(EventTypes.suggestionDismissed);
      _suggested = const [];
    }
    if (_task != null) _level = HelpLevel.none;
    detector.acknowledge();
    _emit();
  }

  /// "Something else" on the suggestion sheet: UI shows all tasks.
  void somethingElse() {
    log.log(EventTypes.somethingElse);
    _suggested = const [];
    detector.acknowledge();
    _emit();
  }

  /// "Show me" button: user asks for help on purpose. Always allowed.
  void askForHelp() {
    if (_task == null) {
      _suggested = suggestions.suggest();
      if (_suggested.isEmpty) _suggested = TaskIds.all.take(cfg.maxSuggestions).toList();
      log.log(EventTypes.suggestionShown, {'tasks': _suggested, 'asked': true});
    } else {
      _level = HelpLevel.full;
      log.log(EventTypes.helpRaised, {'task': _task!.id, 'step': _step, 'asked': true});
    }
    detector.acknowledge();
    _emit(speak: _task != null);
  }

  /// Rule-based scam check. Text is NOT stored or logged.
  ScamVerdict checkMessage(String text) {
    final v = scam.check(text);
    log.log(EventTypes.scamCheck, {
      'level': v.level.name,
      'score': v.score,
      'rules': v.reasons.map((r) => r.ruleId).toList(),
    });
    return v;
  }

  // ============================== demo & privacy ==============================
  /// Clears learning progress and events (keeps consent). Use before a demo.
  Future<void> resetDemo() async {
    await ladder.reset();
    await suggestions.reset();
    await log.clearEvents();
    await store.remove(_paceKey);
    detector.loadPace(const []);
    _endRun();
    _emit();
  }

  /// Jump to "attempt 3" for a task without doing it 3 times on stage.
  void seedDemo(String taskId, {int cleanCompletions = 2}) {
    ladder.seed(taskId, clean: cleanCompletions);
    _emit();
  }

  /// PRD F5 "Delete my data": removes every Companion key from the phone.
  Future<void> deleteAllData() async {
    for (final k in store.keys.where((k) => k.startsWith(storePrefix)).toList()) {
      await store.remove(k);
    }
    await ladder.reset();
    await suggestions.reset();
    await log.clearEvents();
    await log.setConsent(Consent.none);
    await store.remove('${storePrefix}consent');
    detector.loadPace(const []);
    _endRun();
    _emit();
  }

  CaregiverSummary caregiverSummary() => CaregiverSummary.build(
        log: log,
        ladder: ladder,
        catalog: catalog,
        now: clock(),
      );

  void dispose() => _ctrl.close();

  // ============================== internals ==============================
  void _beginTask(String taskId, {HelpLevel atLeast = HelpLevel.none}) {
    final flow = catalog[taskId];
    if (flow == null) return;
    _task = flow;
    _step = 0;
    _runStart = ladder.startingLevel(taskId);
    _level = _runStart.index >= atLeast.index ? _runStart : atLeast;
    _runClean = true;
    ladder.recordStart(taskId);
    detector.resetEpisode();
    detector.guided = true;
    log.log(EventTypes.taskStarted, {'task': taskId, 'help': _runStart.name});
  }

  TapOutcome _advance() {
    final t = _task!;
    detector.onStepSuccess();
    store.setString(_paceKey, jsonEncode(detector.paceSamplesMs));
    log.log(EventTypes.stepCompleted, {'task': t.id, 'step': _step, 'help': _level.name});
    _step++;

    if (_step >= t.steps.length) {
      final cel = ladder.recordCompletion(t.id, t.titleUr, t.titleEn,
          clean: _runClean, startedAt: _runStart);
      suggestions.recordCompleted(t.id);
      log.log(EventTypes.taskCompleted, {'task': t.id, 'clean': _runClean, 'help': _runStart.name});
      if (cel.justMastered) log.log(EventTypes.mastered, {'task': t.id});
      final launch = t.finalAction.kind == LaunchKind.none ? null : t.finalAction;
      if (launch != null && !t.isPractice) log.log(EventTypes.navStarted, {'task': t.id});
      _endRun();
      _emit(celebration: cel, speakText: cel.messageUr);
      return TapOutcome(
        wasGuidedStep: true,
        taskCompleted: true,
        launch: t.isPractice ? null : launch,
        tryForReal: t.isPractice ? launch : null,
      );
    }

    _level = _runStart; // each new step starts at the run's base level
    _emit(speak: _level.speaks);
    return const TapOutcome(wasGuidedStep: true);
  }

  void _endRun() {
    _task = null;
    _step = 0;
    _level = HelpLevel.none;
    _runStart = HelpLevel.none;
    _suggested = const [];
    detector.resetEpisode();
    detector.guided = false;
  }

  /// If the user went back to an earlier screen of the task, rewind to it.
  void _syncStepToScreen() {
    final t = _task!;
    if (t.steps[_step].screenId == _screen) return;
    for (var i = _step - 1; i >= 0; i--) {
      if (t.steps[i].screenId == _screen) {
        _step = i;
        return;
      }
    }
  }

  void _evaluate({bool emitAnyway = false}) {
    final r = detector.evaluate();
    if (!r.triggered) {
      if (emitAnyway) _emit();
      return;
    }
    detector.acknowledge();
    final sig = r.signals.map((s) => s.name).toList();
    if (_task != null) {
      _runClean = false;
      ladder.recordStruggle(_task!.id, _step);
      final before = _level;
      _level = _level.raise();
      log.log(EventTypes.struggle, {'task': _task!.id, 'step': _step, 'signals': sig});
      log.log(EventTypes.helpRaised, {'task': _task!.id, 'from': before.name, 'to': _level.name});
      _emit(speak: _level.speaks);
    } else {
      final s = suggestions.suggest();
      log.log(EventTypes.struggle, {'signals': sig});
      if (s.isNotEmpty) {
        _suggested = s;
        log.log(EventTypes.suggestionShown, {'tasks': s});
      }
      _emit();
    }
  }

  Celebration? _lastCelebration; // one-shot: emitted once, then cleared

  void _emit({bool speak = false, Celebration? celebration, String? speakText}) {
    if (celebration != null) _lastCelebration = celebration;
    final t = _task;
    GuidanceState s;
    if (t == null) {
      s = GuidanceState(
        screenId: _screen,
        suggestions: _suggested,
        celebration: _lastCelebration,
        speakUr: speakText,
        textUr: _suggested.isEmpty ? '' : 'کیا میں مدد کروں؟',
        textEn: _suggested.isEmpty ? '' : 'Need a hand?',
        level: _suggested.isEmpty ? HelpLevel.none : HelpLevel.nudge,
      );
    } else {
      final st = t.steps[_step];
      final onRightScreen = st.screenId == _screen;
      final level = _level;
      String ur, en;
      if (!onRightScreen) {
        ur = 'واپس جانے کے لیے پیچھے والا تیر دبائیں';
        en = 'Press back to return';
      } else if (level == HelpLevel.nudge) {
        ur = 'کیا میں مدد کروں؟ ${st.hintUr}';
        en = 'Need a hand? ${st.hintEn}';
      } else if (level == HelpLevel.full) {
        ur = '${st.textUr}\n${st.whyUr}';
        en = '${st.textEn}\n${st.whyEn}';
      } else {
        ur = st.textUr;
        en = st.textEn;
      }
      s = GuidanceState(
        taskId: t.id,
        stepIndex: _step,
        totalSteps: t.steps.length,
        screenId: _screen,
        targetId: onRightScreen && level.showsHighlight ? st.targetId : null,
        level: level,
        textUr: ur,
        textEn: en,
        speakUr: speakText ?? (speak && onRightScreen ? '${st.textUr}۔ ${st.whyUr}' : null),
        celebration: _lastCelebration,
      );
    }
    _state = s;
    _lastCelebration = null;
    if (!_ctrl.isClosed) _ctrl.add(s);
  }
}
