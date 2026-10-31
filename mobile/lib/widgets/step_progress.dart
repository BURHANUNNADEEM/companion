import 'package:flutter/material.dart';

/// Game-like progress: one circle per step, completed steps become gold stars.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.total, required this.current, required this.label});
  final int total;
  final int current; // index of current step; == total when finished
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: i < current
                    ? const Icon(Icons.star_rounded, key: ValueKey('done'), size: 44, color: Color(0xFFFFB300))
                    : Container(
                        key: ValueKey('todo$i${i == current}'),
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == current ? const Color(0xFF0B5D3B) : Colors.grey.shade300,
                        ),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: i == current ? Colors.white : Colors.black54)),
                      ),
              ),
              if (i < total - 1)
                Container(
                  width: 28,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i < current ? const Color(0xFFFFB300) : Colors.grey.shade300,
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
