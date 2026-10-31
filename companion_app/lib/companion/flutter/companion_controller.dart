import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/caregiver_summary.dart';
import '../core/companion_engine.dart';
import '../core/config.dart';
import '../core/event_log.dart';
import '../core/models.dart';
import '../core/task_flows.dart';
import 'launcher.dart';
import 'shared_prefs_store.dart';
import 'tts_service.dart';

/// The one object the UI talks to. A ChangeNotifier, so use it with
/// ListenableBuilder / AnimatedBuilder / Provider.
class CompanionController extends ChangeNotifier {
  final CompanionEngine engine;
  final TtsService tts;
  final CompanionLauncher launcher;
  Timer? _timer;
  StreamSubscription<GuidanceState>? _sub;

  CompanionController(this.engine, this.tts, this.launcher);

  /// Call once in main() before runApp.
  static Future<CompanionController> create({
    required Contact helper,
    CompanionConfig config = CompanionConfig.demo,
  }) async {
    final store = await SharedPrefsStore.create();
    final engine = CompanionEngine(
      store: store,
      catalog: TaskCatalog(helper: helper),
      cfg: config,
    );
    final tts = TtsService();
    await tts.init();
    final c = CompanionController(engine, tts, CompanionLauncher());
    c._start();
    return c;
  }

  void _start() {
    _sub = engine.states.listen((s) {
      final say = s.speakUr;
      if (say != null) tts.say(say, en: s.celebration?.messageEn ?? s.textEn);
      notifyListeners();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => engine.tick());
  }

  // ---------- read ----------
  GuidanceState get state => engine.state;
  Consent get consent => engine.consent;
  bool get needsConsent => !engine.consent.tracking;
  SkillStage stageOf(String taskId) => engine.stageOf(taskId);
  CaregiverSummary caregiverSummary() => engine.caregiverSummary();

  // ---------- write ----------
  void screen(String screenId) => engine.onScreen(screenId);
  void back() => engine.onBack();

  /// Call from every CompanionTarget's onPressed. Opens the real app when the
  /// task's last step is done (after a short pause so the praise is seen).
  Future<TapOutcome> tap(String targetId) async {
    final o = engine.onTap(targetId);
    final launch = o.launch;
    if (launch != null) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await launcher.run(launch);
    }
    return o;
  }

  /// "Now try it for real" button after a practice task.
  Future<bool> tryForReal(LaunchAction a) => launcher.run(a);

  void acceptSuggestion(String taskId) => engine.acceptSuggestion(taskId);
  void notNow() {
    tts.stop();
    engine.dismissHelp();
  }

  void somethingElse() => engine.somethingElse();
  void showMe() => engine.askForHelp();
  ScamVerdict checkMessage(String text) {
    final v = engine.checkMessage(text);
    tts.say(v.spokenUr, en: '${v.level.labelEn}. ${v.actionEn} ${ScamVerdict.askFamilyEn}');
    return v;
  }

  Future<void> setConsent({required bool tracking, bool caregiverSharing = false}) async {
    await engine.setConsent(Consent(tracking: tracking, caregiverSharing: caregiverSharing));
    notifyListeners();
  }

  Future<void> resetDemo() => engine.resetDemo();
  void seedDemo(String taskId, {int clean = 2}) => engine.seedDemo(taskId, cleanCompletions: clean);
  Future<void> deleteAllData() async {
    await engine.deleteAllData();
    notifyListeners();
  }

  set voiceOn(bool v) {
    tts.enabled = v;
    if (!v) tts.stop();
    notifyListeners();
  }

  bool get voiceOn => tts.enabled;

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    engine.dispose();
    tts.stop();
    super.dispose();
  }
}

/// Reports screens and back presses automatically.
/// Give every route a name equal to a Screens.* id:
///   Navigator.pushNamed(context, Screens.contacts)
/// and add `navigatorObservers: [CompanionRouteObserver(controller)]` to MaterialApp.
class CompanionRouteObserver extends NavigatorObserver {
  final CompanionController c;
  CompanionRouteObserver(this.c);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final n = route.settings.name;
    if (n != null && route is PageRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.screen(n == '/' ? Screens.home : n));
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    c.back();
    final n = previousRoute?.settings.name;
    if (n != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.screen(n == '/' ? Screens.home : n));
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final n = newRoute?.settings.name;
    if (n != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.screen(n == '/' ? Screens.home : n));
    }
  }
}
