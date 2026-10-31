import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';

/// "My progress": what she can do now and the step to practise next.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = companion.caregiverSummary();
    return Scaffold(
      appBar: AppBar(title: const Text('میری ترقی  •  My progress')),
      body: !s.sharingAllowed
          ? const Center(child: Text('ترقی دیکھنے کے لیے سیٹنگ میں اجازت دیں', style: TextStyle(fontSize: 20)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final k in s.skills)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: Text(k.stage.emoji, style: const TextStyle(fontSize: 40)),
                      title: Text(k.titleUr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${k.stage.labelUr}  •  ${k.stage.labelEn}', style: const TextStyle(fontSize: 17)),
                        Text('مکمل: ${k.completions}   بغیر مدد: ${k.independent}',
                            style: const TextStyle(fontSize: 16)),
                        if (k.stuckStepUr != null)
                          Text('یہاں رکتی ہیں: ${k.stuckStepUr}',
                              style: const TextStyle(fontSize: 16, color: Colors.deepOrange)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                if (s.teachNextUr.isNotEmpty) ...[
                  const Text('اگلی مشق  •  Practise next',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  for (var i = 0; i < s.teachNextUr.length; i++)
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(s.teachNextUr[i], style: const TextStyle(fontSize: 18)),
                      subtitle: Text(s.teachNextEn[i], textDirection: TextDirection.ltr),
                    ),
                ],
                const Divider(height: 28),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text('پیغام چیک کیے: ${s.scamChecks}   دھوکے پکڑے: ${s.likelyScams}',
                      style: const TextStyle(fontSize: 18)),
                ),
                ListTile(
                  leading: const Icon(Icons.today),
                  title: Text('آج مدد کی ضرورت پڑی: ${s.struggleEpisodesToday} بار',
                      style: const TextStyle(fontSize: 18)),
                ),
              ],
            ),
    );
  }
}
