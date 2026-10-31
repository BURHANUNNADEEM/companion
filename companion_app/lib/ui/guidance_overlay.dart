import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';

/// Draws whatever the engine decided (GuidanceState). Sits above every screen.
/// - full:      dims everything except the target, pulsing ring, big text, voice
/// - highlight: glowing ring around the target + short text
/// - nudge:     small "Need a hand?" chip
/// - suggestions: "Need a hand?" card with task choices
/// The dim layer ignores touches, so the user taps the REAL button herself.
class GuidanceOverlay extends StatefulWidget {
  const GuidanceOverlay({super.key});
  @override
  State<GuidanceOverlay> createState() => _GuidanceOverlayState();
}

class _GuidanceOverlayState extends State<GuidanceOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Celebration? _celebration;
  Timer? _celebrationTimer;

  @override
  void initState() {
    super.initState();
    companion.addListener(_onChange);
  }

  void _onChange() {
    final c = companion.state.celebration;
    if (c != null) {
      _celebrationTimer?.cancel();
      setState(() => _celebration = c);
      _celebrationTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _celebration = null);
      });
    }
  }

  @override
  void dispose() {
    companion.removeListener(_onChange);
    _celebrationTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  bool get _enabled => FirebaseAuth.instance.currentUser != null && !companion.needsConsent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, companion]),
      builder: (context, _) {
        if (!_enabled) return const SizedBox.shrink();
        final s = companion.state;
        final rect = TargetRegistry.instance.rectOf(s.targetId);
        final children = <Widget>[];

        if (s.level == HelpLevel.full && rect != null) {
          children.add(Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _DimPainter(rect.inflate(8)))),
          ));
        }
        if (s.level.showsHighlight && rect != null) {
          final grow = 6 + 10 * _pulse.value;
          final r = rect.inflate(grow);
          children.add(Positioned(
            left: r.left,
            top: r.top,
            width: r.width,
            height: r.height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: (s.level == HelpLevel.full ? Colors.yellowAccent : Colors.orangeAccent)
                        .withValues(alpha: 0.6 + 0.4 * _pulse.value),
                    width: s.level == HelpLevel.full ? 6 : 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.orangeAccent.withValues(alpha: 0.5 * _pulse.value),
                        blurRadius: 24,
                        spreadRadius: 4),
                  ],
                ),
              ),
            ),
          ));
        }

        if (s.hasSuggestions) {
          children.add(_bottom(_SuggestionCard(suggestions: s.suggestions)));
        } else if (s.level == HelpLevel.nudge) {
          children.add(_bottom(_NudgeChip(textUr: s.textUr, textEn: s.textEn)));
        } else if (s.level.showsHighlight && s.textUr.isNotEmpty) {
          children.add(_bottom(_HelpCard(
            textUr: s.textUr,
            textEn: s.textEn,
            big: s.level == HelpLevel.full,
            step: s.totalSteps > 0 ? 'قدم ${s.stepIndex + 1} / ${s.totalSteps}' : null,
          )));
        }

        if (_celebration != null) {
          children.add(Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: _CelebrationCard(c: _celebration!),
          ));
        }

        if (children.isEmpty) return const SizedBox.shrink();
        return Stack(children: children);
      },
    );
  }

  Widget _bottom(Widget child) => Positioned(
        left: 12,
        right: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
        child: child,
      );
}

class _DimPainter extends CustomPainter {
  final Rect hole;
  _DimPainter(this.hole);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(28)));
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.62));
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}

class _HelpCard extends StatelessWidget {
  final String textUr;
  final String textEn;
  final bool big;
  final String? step;
  const _HelpCard({required this.textUr, required this.textEn, required this.big, this.step});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (step != null)
              Text(step!, style: const TextStyle(fontSize: 14, color: Colors.black45)),
            Text(textUr,
                style: TextStyle(fontSize: big ? 24 : 21, fontWeight: FontWeight.w600, height: 1.5)),
            const SizedBox(height: 4),
            Text(textEn.replaceAll('\n', ' '),
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 14, color: Colors.black54)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!big)
                  TextButton.icon(
                    onPressed: companion.showMe,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('سمجھائیں', style: TextStyle(fontSize: 18)),
                  ),
                TextButton(
                  onPressed: companion.notNow,
                  child: const Text('ابھی نہیں  •  Not now', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NudgeChip extends StatelessWidget {
  final String textUr;
  final String textEn;
  const _NudgeChip({required this.textUr, required this.textEn});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Colors.indigo.shade50,
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.support_agent, size: 30, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(textUr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            FilledButton(
              onPressed: companion.showMe,
              child: const Text('دکھائیں', style: TextStyle(fontSize: 18)),
            ),
            IconButton(onPressed: companion.notNow, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final List<String> suggestions;
  const _SuggestionCard({required this.suggestions});
  @override
  Widget build(BuildContext context) {
    final catalog = companion.engine.catalog;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('کیا میں مدد کروں؟ آپ کیا کرنا چاہتی ہیں؟',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('Need a hand? What would you like to do?',
                textDirection: TextDirection.ltr, style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            for (final id in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => companion.acceptSuggestion(id),
                  child: Text(catalog[id]?.titleUr ?? id, style: const TextStyle(fontSize: 21)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: companion.somethingElse,
                    child: const Text('کچھ اور', style: TextStyle(fontSize: 18)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: companion.notNow,
                    child: const Text('ابھی نہیں', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CelebrationCard extends StatelessWidget {
  final Celebration c;
  const _CelebrationCard({required this.c});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(24),
      color: c.justMastered ? Colors.green.shade600 : Colors.teal.shade500,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.stage.emoji, style: const TextStyle(fontSize: 54)),
            Text(c.messageUr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(c.messageEn,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 14, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
