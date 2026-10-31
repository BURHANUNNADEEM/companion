import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_globals.dart';
import '../companion/companion.dart';

const demoScamSms =
    'Mubarak ho! Aap ki BISP raqam Rs 25,000 approve ho gayi hai. Processing fee 500 bhej kar foran link par click karein: bisp-gov.xyz/claim';

/// One display model for both the server verdict and the offline verdict.
class _Result {
  final String level; // likely_scam | be_careful | probably_fine
  final String labelUr, labelEn, actionUr, actionEn, lessonUr, lessonEn, spokenUr;
  final List<(String, String)> reasons; // (ur, en)
  final String source;
  _Result(this.level, this.labelUr, this.labelEn, this.reasons, this.actionUr, this.actionEn,
      this.lessonUr, this.lessonEn, this.spokenUr, this.source);

  factory _Result.fromServer(Map<String, dynamic> j) => _Result(
        j['verdict'] as String,
        j['label_ur'] as String,
        j['label_en'] as String,
        [
          for (final r in (j['reasons'] as List))
            ((r as Map)['reason_ur'] as String, r['reason_en'] as String)
        ],
        j['action_ur'] as String,
        j['action_en'] as String,
        j['lesson_ur'] as String,
        j['lesson_en'] as String,
        j['spoken_ur'] as String,
        j['ai_used'] == true ? 'server (rules + AI)' : 'server (rules)',
      );

  factory _Result.fromLocal(ScamVerdict v) => _Result(
        const ['probably_fine', 'be_careful', 'likely_scam'][v.level.index],
        v.level.labelUr,
        v.level.labelEn,
        [for (final r in v.reasons) (r.reasonUr, r.reasonEn)],
        v.actionUr,
        v.actionEn,
        v.lessonUr,
        v.lessonEn,
        v.spokenUr,
        'on this phone (offline)',
      );

  Color get color => switch (level) {
        'likely_scam' => const Color(0xFFC92A2A),
        'be_careful' => const Color(0xFFE67700),
        _ => const Color(0xFF2B8A3E),
      };
  IconData get icon => switch (level) {
        'likely_scam' => Icons.gpp_bad,
        'be_careful' => Icons.warning_amber,
        _ => Icons.verified_user,
      };
}

class ScamCheckPage extends StatefulWidget {
  const ScamCheckPage({super.key});
  @override
  State<ScamCheckPage> createState() => _ScamCheckPageState();
}

class _ScamCheckPageState extends State<ScamCheckPage> {
  final _text = TextEditingController();
  _Result? _result;
  bool _loading = false;

  Future<void> _paste() async {
    await tapTarget(Targets.pasteButton);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    setState(() => _text.text = t.isEmpty ? demoScamSms : t);
  }

  Future<void> _check() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پہلے پیغام پیسٹ کریں', style: TextStyle(fontSize: 18))));
      return;
    }
    await tapTarget(Targets.checkButton);
    setState(() => _loading = true);
    final local = companion.engine.checkMessage(text); // offline verdict + logs outcome only
    final server = await backend.scamCheck(text);
    final r = server != null ? _Result.fromServer(server) : _Result.fromLocal(local);
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
    });
    companion.tts.say(r.spokenUr, en: '${r.labelEn}. ${r.actionEn} ${ScamVerdict.askFamilyEn}');
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('پیغام چیک کریں  •  Check a message')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 200),
        children: [
          const Text('جو پیغام عجیب لگے، اسے کاپی کر کے یہاں لائیں۔',
              style: TextStyle(fontSize: 20)),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            maxLines: 5,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'پیغام یہاں…  •  Message here…',
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: CompanionTarget(
                id: Targets.pasteButton,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('پیسٹ  •  Paste', style: TextStyle(fontSize: 19)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _text.text = demoScamSms),
              child: const Text('نمونہ', style: TextStyle(fontSize: 17)),
            ),
          ]),
          const SizedBox(height: 10),
          CompanionTarget(
            id: Targets.checkButton,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
              onPressed: _loading ? null : _check,
              icon: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
                  : const Icon(Icons.shield),
              label: const Text('چیک کریں  •  Check', style: TextStyle(fontSize: 21)),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 18),
            Card(
              color: r.color,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(r.icon, color: Colors.white, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.labelUr,
                          style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(r.labelEn, style: const TextStyle(fontSize: 16, color: Colors.white70)),
                    ]),
                  ),
                ]),
              ),
            ),
            for (final reason in r.reasons.take(3))
              ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.redAccent),
                title: Text(reason.$1, style: const TextStyle(fontSize: 19)),
                subtitle: Text(reason.$2, textDirection: TextDirection.ltr),
              ),
            _InfoBox(icon: Icons.back_hand, color: Colors.blue.shade50, titleUr: 'کیا کریں', ur: r.actionUr, en: r.actionEn),
            _InfoBox(icon: Icons.lightbulb, color: Colors.amber.shade50, titleUr: 'یاد رکھیں', ur: r.lessonUr, en: r.lessonEn),
            _InfoBox(
                icon: Icons.family_restroom,
                color: Colors.green.shade50,
                titleUr: 'مشورہ',
                ur: ScamVerdict.askFamilyUr,
                en: ScamVerdict.askFamilyEn),
            Text('Checked: ${r.source}', textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.black38)),
          ],
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String titleUr, ur, en;
  const _InfoBox({required this.icon, required this.color, required this.titleUr, required this.ur, required this.en});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titleUr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(ur, style: const TextStyle(fontSize: 19)),
              Text(en, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.black54)),
            ]),
          ),
        ]),
      );
}
