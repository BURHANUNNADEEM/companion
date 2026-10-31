import 'package:flutter/material.dart';

import 'nav_arrow.dart';

class OverlayChoice {
  OverlayChoice(this.label, this.onTap, {this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

/// Coach-mark overlay (F4): dimmed screen, pulsing highlight on the suggested tile, ONE short kind sentence,
/// optional read-aloud, choices, an always-visible "Not now" and "Something else".
class GuidanceOverlay extends StatelessWidget {
  const GuidanceOverlay({
    super.key,
    required this.title,
    required this.sentence,
    required this.choices,
    required this.notNowLabel,
    required this.onNotNow,
    this.somethingElseLabel,
    this.onSomethingElse,
    this.readAloudLabel,
    this.onReadAloud,
    this.speakLabel,
    this.onSpeak,
    this.targetRect,
  });

  final String title;
  final String sentence;
  final List<OverlayChoice> choices;
  final String notNowLabel;
  final VoidCallback onNotNow;
  final String? somethingElseLabel;
  final VoidCallback? onSomethingElse;
  final String? readAloudLabel;
  final VoidCallback? onReadAloud;
  final String? speakLabel;
  final VoidCallback? onSpeak;
  final Rect? targetRect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final rect = targetRect;
      final cardAtTop = rect != null && rect.center.dy > box.maxHeight * 0.55;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // swallow taps on the dimmed area
              child: CustomPaint(painter: DimPainter(rect)),
            ),
          ),
          if (rect != null) PulseHighlight(rect: rect),
          if (rect != null)
            Positioned(
              left: rect.center.dx - 32,
              top: cardAtTop ? rect.bottom + 4 : rect.top - 74,
              child: IgnorePointer(child: NavArrow(direction: cardAtTop ? 'up' : 'down')),
            ),
          if (rect != null)
            Positioned.fromRect(
              rect: rect,
              child: Semantics(
                button: true,
                label: choices.isNotEmpty ? choices.first.label : title,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: choices.isNotEmpty ? choices.first.onTap : null,
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            top: cardAtTop ? 12 : null,
            bottom: cardAtTop ? null : 12,
            child: SafeArea(child: _card(context)),
          ),
        ],
      );
    });
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      elevation: 12,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.waving_hand_rounded, color: Color(0xFFFFB300), size: 34),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
              if (onReadAloud != null)
                IconButton(
                  iconSize: 36,
                  tooltip: readAloudLabel,
                  onPressed: onReadAloud,
                  icon: const Icon(Icons.volume_up_rounded),
                ),
            ]),
            const SizedBox(height: 6),
            Text(sentence, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            for (final c in choices) ...[
              ElevatedButton.icon(
                onPressed: c.onTap,
                icon: Icon(c.icon ?? Icons.touch_app_rounded, size: 30),
                label: Text(c.label),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              if (onSomethingElse != null)
                Expanded(
                  child: OutlinedButton(onPressed: onSomethingElse, child: Text(somethingElseLabel ?? '')),
                ),
              if (onSomethingElse != null) const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: onNotNow, child: Text(notNowLabel))),
            ]),
            if (onSpeak != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(onPressed: onSpeak, icon: const Icon(Icons.mic, size: 30), label: Text(speakLabel ?? '')),
            ],
          ],
        ),
      ),
    );
  }
}
