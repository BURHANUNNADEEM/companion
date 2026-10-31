import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/services.dart';
import '../services/struggle_detector.dart';
import '../widgets/big_tile.dart';
import '../widgets/guidance_overlay.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/voice_sheet.dart';
import 'family_screen.dart';
import 'navigation_guide_screen.dart';
import 'scam_check_screen.dart';
import 'settings_screen.dart';

/// Guided home screen (F1) with on-device struggle detection (F2), suggestions (F3),
/// coach-mark overlay (F4), voice (F7) and navigation (F10).
class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> with WidgetsBindingObserver {
  final _stackKey = GlobalKey();
  final Map<String, GlobalKey> _tileKeys = {for (final t in kHomeTiles) t.id: GlobalKey()};
  Timer? _ticker;
  String? _pendingTask; // Tier 1 action launched, waiting for the user to come back
  String? _lastTask;
  List<Suggestion> _cached = [];
  bool _overlayVisible = false;
  bool _backoff = false;
  List<Map<String, dynamic>> _guideCards = [];

  late final AppServices _svc;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    _state = context.read<AppState>();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _state.tracker?.screen('home');
      _prefetchSuggestions();
      _loadGuideCards();
      _svc.scamInput.listenForShares(_openScamCheckWithText);
    });
    // Evaluate struggle once a second -> overlay well within the 1 s budget (F4 acceptance).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _evaluate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _svc.scamInput.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final tracker = _state.tracker;
    if (s == AppLifecycleState.resumed) {
      if (_pendingTask != null) {
        tracker?.taskCompleted(_pendingTask!, source: 'tile');
        _lastTask = _pendingTask;
        _pendingTask = null;
        _prefetchSuggestions();
      }
      _state.detector.paused = false;
      tracker?.screen('home');
    } else if (s == AppLifecycleState.paused) {
      _state.detector.paused = true;
      tracker?.flush();
    }
  }

  // ---------------- suggestions & overlay ----------------
  Future<void> _prefetchSuggestions() async {
    try {
      final r = await _svc.api.suggestions(hour: DateTime.now().hour, lastTask: _lastTask);
      if (!mounted) return;
      setState(() {
        _cached = (r['suggestions'] as List).map((e) => Suggestion.fromJson(Map<String, dynamic>.from(e))).toList();
        _backoff = (r['backoff'] as Map?)?['active'] == true;
      });
    } catch (_) {
      // offline: local defaults keep the overlay working
    }
  }

  List<Suggestion> get _suggestionsOrDefaults {
    if (_cached.isNotEmpty) return _cached;
    return [
      for (final t in kHomeTiles.take(3))
        Suggestion(task: t.id, workflowId: t.workflowId, label: {'en': t.en, 'ur': t.ur}),
    ];
  }

  void _evaluate() {
    if (!mounted || _overlayVisible || ModalRoute.of(context)?.isCurrent != true) return;
    final StruggleResult? r = _state.detector.evaluate();
    if (r == null) return;
    final tracker = _state.tracker;
    tracker?.log('struggle_detected', itemId: _lastTask, props: {
      'score': r.score,
      'signals': r.signals,
      'screen': r.screen,
      'task': _lastTask,
    });
    if (_backoff) return; // backs off after repeated dismissals (F3)
    final top = _suggestionsOrDefaults;
    for (var i = 0; i < top.length; i++) {
      tracker?.log('suggestion_shown', itemId: top[i].task, props: {'rank': i + 1});
    }
    setState(() => _overlayVisible = true);
    _prefetchSuggestions(); // refresh in the background; overlay is already visible
  }

  void _dismissOverlay() {
    final top = _suggestionsOrDefaults;
    if (top.isNotEmpty) _state.tracker?.log('suggestion_dismissed', itemId: top.first.task, props: {'rank': 1});
    setState(() => _overlayVisible = false);
    _prefetchSuggestions();
  }

  Future<void> _acceptSuggestion(Suggestion sug, int rank) async {
    _state.tracker?.log('suggestion_accepted', itemId: sug.task, props: {'rank': rank});
    setState(() => _overlayVisible = false);
    await _startGuide(task: sug.task);
  }

  Future<void> _somethingElse() async {
    _state.tracker?.log('something_else_tapped');
    setState(() => _overlayVisible = false);
    await _speak();
  }

  // ---------------- actions ----------------
  Future<void> _onTile(TaskDef t) async {
    final tracker = _state.tracker;
    tracker?.tap('tile_${t.id}', screen: 'home');
    tracker?.taskStarted(t.id);
    if (t.inAppRoute == 'scam_check') {
      await _push(const ScamCheckScreen(), 'scam_check');
      return;
    }
    if (t.param == 'helper' && _state.contacts.helper == null) {
      showMessage(context, S.read(context).t('no_helper'));
      await _push(const FamilyScreen(), 'family');
      return;
    }
    final params = t.param == null ? <String, dynamic>{} : {t.param!: t.param == 'helper' ? '__device_helper__' : null};
    final ok = await _svc.nav.open(t.intent!, params: params);
    if (!mounted) return;
    if (ok) {
      _pendingTask = t.id; // completed when the user returns (1 tap, F1/F10 Tier 1)
    } else {
      showMessage(context, S.read(context).t('nav_failed'));
      await _startGuide(task: t.id);
    }
  }

  Future<void> _startGuide({String? task, String? utterance, String? workflowId}) async {
    final s = S.read(context);
    try {
      final raw = await _svc.api.plan(task: task, utterance: utterance, workflowId: workflowId);
      if (!mounted) return;
      final plan = NavPlan.fromJson(raw);
      if (!plan.ok) {
        showMessage(context, s.pick(plan.message, fallback: s.t('error_generic')));
        return;
      }
      final done = await _push(NavigationGuideScreen(plan: plan), 'nav_${plan.workflowId}');
      if (done == true) {
        _lastTask = plan.task;
        _prefetchSuggestions();
      }
    } catch (e) {
      if (!mounted) return;
      // Offline: Tier 1 tiles still work directly.
      final tile = task == null ? null : tileById(task);
      if (tile != null && tile.intent != null) {
        await _onTile(tile);
      } else {
        showApiError(context, e);
      }
    }
  }

  Future<void> _speak() async {
    final text = await showVoiceSheet(context);
    if (text == null || !mounted) return;
    await _startGuide(utterance: text);
  }

  Future<T?> _push<T>(Widget screen, String name) async {
    _state.detector.paused = true;
    final result = await Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      _state.detector.paused = false;
      _state.tracker?.screen('home');
      _loadGuideCards();
    }
    return result;
  }

  void _openScamCheckWithText(String text) {
    if (!mounted) return;
    _push(ScamCheckScreen(initialText: text, source: 'share'), 'scam_check');
  }

  Future<void> _loadGuideCards() async {
    try {
      final r = await _svc.api.get('/guide-cards');
      if (mounted) setState(() => _guideCards = (r['cards'] as List).cast<Map>().map(Map<String, dynamic>.from).toList());
    } catch (_) {}
  }

  Future<void> _dismissCard(Map<String, dynamic> card) async {
    setState(() => _guideCards.remove(card));
    try {
      await _svc.api.post('/guide-cards/${card['id']}/seen');
    } catch (_) {}
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = context.watch<AppState>();
    final lang = state.lang;
    final suggestions = _suggestionsOrDefaults;
    Rect? target;
    if (_overlayVisible && suggestions.isNotEmpty && _tileKeys.containsKey(suggestions.first.task)) {
      target = rectOf(_tileKeys[suggestions.first.task]!, ancestor: _stackKey.currentContext?.findRenderObject());
    }
    final firstLabel = suggestions.isEmpty ? '' : s.pick(suggestions.first.label);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) => state.tracker?.back(screen: 'home'),
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('hello')),
          actions: [
            IconButton(
              iconSize: 34,
              tooltip: s.t('family'),
              icon: const Icon(Icons.family_restroom),
              onPressed: () {
                state.tracker?.tap('open_family', screen: 'home');
                _push(const FamilyScreen(), 'family');
              },
            ),
            IconButton(
              iconSize: 34,
              tooltip: s.t('settings'),
              icon: const Icon(Icons.settings),
              onPressed: () {
                state.tracker?.tap('open_settings', screen: 'home');
                _push(const SettingsScreen(), 'settings');
              },
            ),
          ],
        ),
        body: Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => state.detector.onActivity(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final card in _guideCards) _guideCard(s, card),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.0,
                      children: [
                        for (final t in kHomeTiles)
                          BigTile(
                            key: _tileKeys[t.id],
                            semanticsId: 'tile_${t.id}',
                            label: t.label(lang),
                            icon: t.icon,
                            color: t.color,
                            onTap: () => _onTile(t),
                            onLongPress: () {
                              state.tracker?.tap('tile_${t.id}_howto', screen: 'home');
                              _startGuide(task: t.id);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(s.t('long_press_hint'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: SizedBox(
                  height: 76,
                  child: ElevatedButton.icon(
                    key: const ValueKey('speak_button'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF263238)),
                    onPressed: () {
                      state.tracker?.tap('speak', screen: 'home');
                      _speak();
                    },
                    icon: const Icon(Icons.mic_rounded, size: 40),
                    label: Text(s.t('speak'), style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
            if (_overlayVisible)
              Positioned.fill(
                child: GuidanceOverlay(
                  key: const ValueKey('guidance_overlay'),
                  targetRect: target,
                  title: s.t('need_hand'),
                  sentence: s.t('tap_here_to', {'task': firstLabel}),
                  choices: [
                    for (var i = 0; i < suggestions.length; i++)
                      OverlayChoice(s.pick(suggestions[i].label), () => _acceptSuggestion(suggestions[i], i + 1),
                          icon: tileById(suggestions[i].task)?.icon),
                  ],
                  notNowLabel: s.t('not_now'),
                  onNotNow: _dismissOverlay,
                  somethingElseLabel: s.t('something_else'),
                  onSomethingElse: _somethingElse,
                  readAloudLabel: s.t('read_aloud'),
                  onReadAloud: () => _svc.voice.speak('${s.t('need_hand')} ${s.t('tap_here_to', {'task': firstLabel})}', lang),
                  speakLabel: s.t('speak'),
                  onSpeak: () {
                    setState(() => _overlayVisible = false);
                    _speak();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _guideCard(S s, Map<String, dynamic> card) {
    final from = card['from'] as String? ?? s.t('family');
    return Card(
      color: const Color(0xFFFFF8E1),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('guide_card_from', {'name': from}), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(card['text'] as String? ?? '', style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.volume_up_rounded),
              onPressed: () => _svc.voice.speak(card['text'] as String? ?? '', s.lang),
            ),
            if (card['workflow_id'] != null)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _startGuide(workflowId: card['workflow_id'] as String),
                  child: Text(s.t('show_me_how')),
                ),
              ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => _dismissCard(card), child: Text(s.t('got_it'))),
          ]),
        ]),
      ),
    );
  }
}
