import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/services.dart';
import '../widgets/nav_arrow.dart';
import '../widgets/step_progress.dart';
import '../widgets/ui_helpers.dart';
import 'family_screen.dart';
import 'scam_check_screen.dart';

/// Game-like, step-by-step guidance for a validated NavPlan (F10).
///
/// Each step shows: progress stars, a preview of the target screen with a pulsing highlight and a
/// bouncing arrow at the server-provided position, ONE short hint (read aloud on request) and one big
/// button. Only allow-listed Tier 1 intents / in-app routes can run. Optional Tier 2 (Kotlin) Guide/Assist.
class NavigationGuideScreen extends StatefulWidget {
  const NavigationGuideScreen({super.key, required this.plan});
  final NavPlan plan;

  @override
  State<NavigationGuideScreen> createState() => _NavigationGuideScreenState();
}

class _NavigationGuideScreenState extends State<NavigationGuideScreen> with WidgetsBindingObserver {
  int _current = 0;
  bool _awaitingReturn = false;
  bool _finished = false;
  bool _tier2Available = false;
  bool _tier2Running = false;
  StreamSubscription? _tier2Sub;
  late final AppServices _svc;
  late final AppState _state;

  NavPlan get plan => widget.plan;
  NavStep get step => plan.steps[_current];

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    _state = context.read<AppState>();
    WidgetsBinding.instance.addObserver(this);
    _state.tracker?.screen('nav_${plan.workflowId}');
    _state.tracker?.log('nav_started', itemId: plan.workflowId, props: {
      'workflow_id': plan.workflowId,
      'task': plan.task,
      'steps_total': plan.steps.length,
      'tier': 'tier1',
    });
    if (plan.tier2Skill != null) {
      _svc.tier2.isEnabled().then((v) {
        if (mounted) setState(() => _tier2Available = v);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tier2Sub?.cancel();
    if (_tier2Running) _svc.tier2.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _awaitingReturn && !_tier2Running) {
      _awaitingReturn = false;
      _completeExternalSteps();
    }
  }

  // ---------------- step logic ----------------
  void _advance() {
    if (_current + 1 >= plan.steps.length) {
      _finish();
    } else {
      setState(() => _current++);
    }
  }

  /// The user did the remaining steps in the other app / screen: mark them done.
  void _completeExternalSteps() {
    while (_current < plan.steps.length &&
        (step.isExternal || step.actionKind == 'in_app_hint')) {
      if (_current + 1 >= plan.steps.length) {
        _finish();
        return;
      }
      setState(() => _current++);
    }
  }

  Future<void> _runPrimary() async {
    final s = S.read(context);
    _state.tracker?.tap('nav_step_${step.id}', screen: 'nav_${plan.workflowId}');
    switch (step.actionKind) {
      case 'open_intent':
        final ok = await _svc.nav.open(step.intent!, params: step.params, slots: plan.slots);
        if (!mounted) return;
        if (!ok) {
          showMessage(context, s.t('nav_failed'));
          return;
        }
        _awaitingReturn = true;
        _advance(); // completion: intent_launched
        break;
      case 'in_app_route':
        final screen = step.route == 'scam_check' ? const ScamCheckScreen() : const FamilyScreen();
        _advance();
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
        if (mounted) _completeExternalSteps();
        break;
      default: // external_hint / in_app_hint -> user confirms
        _advance();
    }
  }

  Future<void> _startTier2(String mode) async {
    final s = S.read(context);
    if (mode == 'assist') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.t('assist_confirm_title')),
          content: Text(s.t('assist_confirm_body'), style: const TextStyle(fontSize: 20)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('yes'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _tier2Sub?.cancel();
    _tier2Sub = _svc.tier2.events.listen(_onTier2Event);
    // Open the target screen with the Tier 1 intent first, then let the skill runner guide/assist.
    final first = plan.steps.first;
    if (first.actionKind == 'open_intent') {
      final ok = await _svc.nav.open(first.intent!, params: first.params, slots: plan.slots);
      if (!ok) {
        if (mounted) showMessage(context, s.t('nav_failed'));
        return;
      }
    }
    final err = await _svc.tier2.startSkill(plan.tier2Skill!, mode: mode, lang: s.lang);
    if (!mounted) return;
    if (err != null) {
      showMessage(context, s.t('tier2_aborted'));
      return;
    }
    setState(() => _tier2Running = true);
    _state.tracker?.log('nav_started', itemId: plan.tier2Skill, props: {'skill_id': plan.tier2Skill, 'tier': 'tier2', 'mode': mode});
  }

  void _onTier2Event(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'completed':
        setState(() => _tier2Running = false);
        _finish();
        break;
      case 'aborted':
        setState(() => _tier2Running = false);
        _state.tracker?.log('nav_aborted', itemId: plan.tier2Skill, props: {
          'skill_id': plan.tier2Skill,
          'tier': 'tier2',
          'reason': (e['reason'] as String?)?.replaceAll(RegExp(r'[^a-z_]'), ''),
          'task': plan.task,
        });
        showMessage(context, S.read(context).t('tier2_aborted'));
        break;
      case 'step':
        final idx = (e['step'] as num?)?.toInt();
        if (idx != null && idx + 1 < plan.steps.length) setState(() => _current = idx + 1);
        break;
    }
  }

  void _stopTier2() {
    _svc.tier2.stop();
    setState(() => _tier2Running = false);
  }

  void _finish() {
    if (_finished) return;
    setState(() {
      _finished = true;
      _current = plan.steps.length;
    });
    _state.tracker?.log('nav_completed', itemId: plan.workflowId,
        props: {'workflow_id': plan.workflowId, 'steps_total': plan.steps.length, 'task': plan.task});
    if (plan.task != null) _state.tracker?.taskCompleted(plan.task!, source: 'guide');
  }

  void _abort() {
    if (!_finished) {
      _state.tracker?.log('nav_aborted', itemId: plan.workflowId,
          props: {'workflow_id': plan.workflowId, 'step': _current, 'task': plan.task, 'reason': 'not_now'});
    }
    if (_tier2Running) _svc.tier2.stop();
    Navigator.of(context).pop(_finished);
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _state.tracker?.back(screen: 'nav_${plan.workflowId}');
          _abort();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.pick(plan.title)),
          leading: IconButton(iconSize: 32, icon: const Icon(Icons.close), onPressed: _abort, tooltip: s.t('not_now')),
        ),
        body: SafeArea(child: _finished ? _celebration(s) : _stepView(s)),
      ),
    );
  }

  Widget _stepView(S s) {
    final st = step;
    final hint = s.pick(st.hint);
    final primaryLabel = switch (st.actionKind) {
      'open_intent' || 'in_app_route' => s.t('go'),
      _ => s.t('i_did_it'),
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StepProgress(
          total: plan.steps.length,
          current: _current,
          label: s.t('step_of', {'n': '${_current + 1}', 'total': '${plan.steps.length}'}),
        ),
        const SizedBox(height: 10),
        if (_current == 0)
          Text(s.pick(plan.intro), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Center(child: _ScreenPreview(step: st, label: s.pick(st.targetLabel))),
        const SizedBox(height: 14),
        Card(
          color: const Color(0xFFE8F5E9),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Text(hint, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
              IconButton(
                iconSize: 40,
                tooltip: s.t('read_aloud'),
                icon: const Icon(Icons.volume_up_rounded),
                onPressed: () => _svc.voice.speak(hint, s.lang),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        if (_tier2Running) ...[
          Card(
            color: const Color(0xFFFFF3E0),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 4)),
                const SizedBox(width: 12),
                Expanded(child: Text(s.t('companion_helping'), style: const TextStyle(fontSize: 22))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
              onPressed: _stopTier2,
              icon: const Icon(Icons.stop_circle_rounded, size: 36),
              label: Text(s.t('stop')),
            ),
          ),
        ] else ...[
          SizedBox(
            height: 76,
            child: ElevatedButton.icon(
              key: const ValueKey('nav_primary'),
              onPressed: _runPrimary,
              icon: Icon(st.actionKind == 'open_intent' || st.actionKind == 'in_app_route'
                  ? Icons.play_arrow_rounded
                  : Icons.check_circle_rounded, size: 40),
              label: Text(primaryLabel, style: const TextStyle(fontSize: 26)),
            ),
          ),
          if (_tier2Available && _current == 0) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _startTier2('guide'),
              icon: const Icon(Icons.touch_app_rounded, size: 30),
              label: Text(s.t('help_me_tap')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _startTier2('assist'),
              icon: const Icon(Icons.smart_toy_rounded, size: 30),
              label: Text(s.t('do_it_for_me')),
            ),
          ],
        ],
        const SizedBox(height: 10),
        TextButton(onPressed: _abort, child: Text(s.t('not_now'))),
      ],
    );
  }

  Widget _celebration(S s) {
    final msg = s.pick(plan.done, fallback: s.t('well_done'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.2, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: const Icon(Icons.stars_rounded, size: 160, color: Color(0xFFFFB300)),
          ),
          const SizedBox(height: 12),
          Text(s.t('well_done'), style: Theme.of(context).textTheme.headlineSmall),
          Text(msg, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 10),
          StepProgress(total: plan.steps.length, current: plan.steps.length, label: ''),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 72,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.t('ok')),
            ),
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.volume_up_rounded),
            onPressed: () => _svc.voice.speak(msg, s.lang),
          ),
        ]),
      ),
    );
  }
}

/// Phone-shaped preview of the target screen with the highlight + arrow at the plan's position.
class _ScreenPreview extends StatelessWidget {
  const _ScreenPreview({required this.step, required this.label});
  final NavStep step;
  final String label;

  @override
  Widget build(BuildContext context) {
    const w = 210.0, h = 373.0; // 9:16
    final hl = step.highlight;
    final rect = Rect.fromLTWH(hl.x * w, hl.y * h, hl.w * w, hl.h * h);
    // Arrow placed on the side the step says, pointing at the target.
    final arrowPos = switch (step.arrow) {
      'up' => Offset(rect.center.dx - 26, rect.bottom + 2),
      'left' => Offset(rect.right + 2, rect.center.dy - 26),
      'right' => Offset(rect.left - 54, rect.center.dy - 26),
      _ => Offset(rect.center.dx - 26, rect.top - 56),
    };
    return Container(
      width: w + 16,
      height: h + 16,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFF263238), borderRadius: BorderRadius.circular(28)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Directionality(
          textDirection: TextDirection.ltr, // positions are screen coordinates
          child: Stack(children: [
            Positioned.fill(child: Container(color: Colors.white)),
            Positioned.fill(child: CustomPaint(painter: DimPainter(rect, opacity: 0.55))),
            PulseHighlight(rect: rect),
            Positioned(left: arrowPos.dx, top: arrowPos.dy, child: NavArrow(direction: step.arrow, size: 52)),
            Positioned(
              left: 8,
              right: 8,
              bottom: rect.center.dy > h / 2 ? null : 8,
              top: rect.center.dy > h / 2 ? 8 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFFC107), borderRadius: BorderRadius.circular(12)),
                child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
