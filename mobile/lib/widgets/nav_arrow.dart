import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bouncing, game-like arrow pointing at a target. [direction] is where the arrow points
/// (`down` = arrow above the target pointing down at it).
class NavArrow extends StatefulWidget {
  const NavArrow({super.key, required this.direction, this.size = 64, this.color = const Color(0xFFFFC107)});
  final String direction;
  final double size;
  final Color color;

  @override
  State<NavArrow> createState() => _NavArrowState();
}

class _NavArrowState extends State<NavArrow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _angle => switch (widget.direction) {
        'up' => math.pi,
        'left' => math.pi / 2,
        'right' => -math.pi / 2,
        _ => 0.0,
      };

  Offset get _axis => switch (widget.direction) {
        'up' => const Offset(0, -1),
        'left' => const Offset(-1, 0),
        'right' => const Offset(1, 0),
        _ => const Offset(0, 1),
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value) * 12;
        return Transform.translate(offset: _axis * t, child: child);
      },
      child: Transform.rotate(
        angle: _angle,
        child: Icon(Icons.arrow_downward_rounded, size: widget.size, color: widget.color, shadows: const [
          Shadow(blurRadius: 8, color: Colors.black54),
        ]),
      ),
    );
  }
}

/// Pulsing rounded rectangle around a target.
class PulseHighlight extends StatefulWidget {
  const PulseHighlight({super.key, required this.rect, this.color = const Color(0xFFFFC107)});
  final Rect rect;
  final Color color;

  @override
  State<PulseHighlight> createState() => _PulseHighlightState();
}

class _PulseHighlightState extends State<PulseHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final grow = 4 + _c.value * 8;
        final r = widget.rect.inflate(grow);
        return Positioned.fromRect(
          rect: r,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: widget.color, width: 5),
                boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5 - _c.value * 0.3), blurRadius: 24, spreadRadius: 4)],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dims everything except [hole].
class DimPainter extends CustomPainter {
  DimPainter(this.hole, {this.opacity = 0.72});
  final Rect? hole;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final cut = Path()..addRRect(RRect.fromRectAndRadius(hole!.inflate(8), const Radius.circular(24)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, cut), paint);
  }

  @override
  bool shouldRepaint(DimPainter old) => old.hole != hole || old.opacity != opacity;
}
