import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';

const _icons = <String, IconData>{
  'wifi': Icons.wifi,
  'hotspot': Icons.wifi_tethering,
  'sound': Icons.volume_up,
  'display': Icons.text_increase,
  'bluetooth': Icons.bluetooth,
};

/// "Phone settings" menu: small how-to lessons.
class SettingsMenuPage extends StatelessWidget {
  const SettingsMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: companion,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('فون کی سیٹنگ  •  Phone settings')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
          children: [
            const Text('کیا سیکھنا ہے؟', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final l in settingsLessons)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CompanionTarget(
                  id: Targets.settingsItem(l.id),
                  child: Material(
                    color: Colors.white,
                    elevation: 1,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        await tapTarget(Targets.settingsItem(l.id));
                        if (context.mounted) {
                          Navigator.pushNamed(context, Screens.settingsLesson, arguments: l.id);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.indigo.shade50,
                            child: Icon(_icons[l.id] ?? Icons.settings, size: 32, color: Colors.indigo),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.titleUr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                              Text(l.titleEn, textDirection: TextDirection.ltr,
                                  style: const TextStyle(fontSize: 15, color: Colors.black54)),
                            ]),
                          ),
                          Text(stageBadgeOf(l.id), style: const TextStyle(fontSize: 24)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String stageBadgeOf(String taskId) {
  final s = companion.stageOf(taskId);
  return s == SkillStage.newSkill ? '' : s.emoji;
}

/// One lesson: why + what to do, then a big button that opens the real settings.
class SettingsLessonPage extends StatelessWidget {
  const SettingsLessonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final id = ModalRoute.of(context)?.settings.arguments as String? ?? 'wifi';
    final l = lessonById(id) ?? settingsLessons.first;
    return Scaffold(
      appBar: AppBar(title: Text(l.titleUr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 200),
        children: [
          Center(child: Icon(_icons[l.id] ?? Icons.settings, size: 90, color: Colors.indigo)),
          const SizedBox(height: 12),
          Text(l.whyUr, style: const TextStyle(fontSize: 21, height: 1.6)),
          Text(l.whyEn, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          const Text('سیٹنگ کھلنے کے بعد:', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          for (var i = 0; i < l.stepsUr.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${i + 1}', style: const TextStyle(fontSize: 20))),
              title: Text(l.stepsUr[i], style: const TextStyle(fontSize: 20)),
              subtitle: Text(l.stepsEn[i], textDirection: TextDirection.ltr),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Text('گھبرائیں نہیں۔ سیٹنگ میں کچھ خراب نہیں ہوتا، اور واپس آنے کے لیے پیچھے والا تیر دبائیں۔',
                style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 20),
          CompanionTarget(
            id: Targets.openSettings,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: () async {
                final nav = Navigator.of(context);
                await tapTarget(Targets.openSettings); // opens the real settings screen
                if (nav.mounted) nav.pushNamedAndRemoveUntil('/', (_) => false);
              },
              icon: const Icon(Icons.open_in_new, size: 28),
              label: const Text('سیٹنگ کھولیں  •  Open settings', style: TextStyle(fontSize: 22)),
            ),
          ),
        ],
      ),
    );
  }
}
