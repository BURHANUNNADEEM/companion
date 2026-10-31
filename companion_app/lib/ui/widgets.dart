import 'package:flutter/material.dart';

import '../companion/companion.dart';

/// Big, high-contrast home tile (≥ 56dp target, ≥ 20sp text).
class BigTile extends StatelessWidget {
  final String targetId;
  final IconData icon;
  final String labelUr;
  final String labelEn;
  final Color color;
  final String? badge;
  final VoidCallback onPressed;
  const BigTile({
    super.key,
    required this.targetId,
    required this.icon,
    required this.labelUr,
    required this.labelEn,
    required this.color,
    required this.onPressed,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return CompanionTarget(
      id: targetId,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 46, color: Colors.white),
                      const SizedBox(height: 4),
                      Text(labelUr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(labelEn,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Text(badge!, style: const TextStyle(fontSize: 26)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A person row used in the contacts lists.
class PersonTile extends StatelessWidget {
  final String targetId;
  final String nameUr;
  final String nameEn;
  final Color color;
  final VoidCallback onTap;
  const PersonTile({
    super.key,
    required this.targetId,
    required this.nameUr,
    required this.nameEn,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: CompanionTarget(
        id: targetId,
        child: Material(
          color: Colors.white,
          elevation: 1,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: color,
                    child: Text(nameEn.characters.first,
                        style: const TextStyle(fontSize: 26, color: Colors.white)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nameUr, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                        Text(nameEn, style: const TextStyle(fontSize: 15, color: Colors.black54)),
                      ],
                    ),
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

/// Visible label for practice (mock) screens — required by the hackathon rules.
class PracticeBanner extends StatelessWidget {
  const PracticeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.amber.shade200,
        padding: const EdgeInsets.all(10),
        child: const Text(
          'مشق — یہ اصلی واٹس ایپ نہیں ہے، کوئی کال نہیں ہوگی  •  PRACTICE screen, no real call',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );
}

String stageBadge(SkillStage s) => s == SkillStage.newSkill ? '' : s.emoji;
