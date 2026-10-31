import 'package:flutter/material.dart';

import '../theme.dart';

/// Large, high-contrast home tile (F1). Tap = do it, long-press = "show me how".
class BigTile extends StatelessWidget {
  const BigTile({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.semanticsId,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      identifier: semanticsId,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTap * 2, minWidth: AppTheme.minTap),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 52, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
