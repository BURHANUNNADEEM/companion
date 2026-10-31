import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';
import '../config.dart';
import '../ui/widgets.dart';
import 'call_pages.dart';

class WaContactsPage extends StatelessWidget {
  const WaContactsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF075E54),
          foregroundColor: Colors.white,
          title: const Text('واٹس ایپ (مشق)  •  WhatsApp (practice)'),
        ),
        body: const Column(
          children: [
            PracticeBanner(),
            Expanded(child: PeopleList(nextRoute: Screens.waChatPractice)),
          ],
        ),
      );
}

/// MOCK of a WhatsApp chat. Clearly labelled as practice.
class WaChatPracticePage extends StatelessWidget {
  const WaChatPracticePage({super.key});

  Future<void> _video(BuildContext context) async {
    final nav = Navigator.of(context);
    final outcome = await tapTarget(Targets.waVideo);
    if (!context.mounted) return;
    final real = outcome.tryForReal;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('شاباش! آپ نے ویڈیو کال کا بٹن ڈھونڈ لیا 🎉', style: TextStyle(fontSize: 22)),
        content: const Text(
          'یہ مشق تھی۔ اب اصلی واٹس ایپ میں یہی کریں: نام دبائیں، پھر اوپر کیمرے والا نشان۔\n\nThis was practice. Now try it in the real WhatsApp.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بعد میں', style: TextStyle(fontSize: 18))),
          if (real != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                companion.tryForReal(real);
              },
              child: const Text('اصلی واٹس ایپ کھولیں', style: TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
    if (nav.mounted) nav.pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        title: const Row(children: [
          CircleAvatar(backgroundColor: Color(0xFFE67700), child: Icon(Icons.person, color: Colors.white)),
          SizedBox(width: 10),
          Flexible(child: Text(helperNameUr, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          CompanionTarget(
            id: 'btn_wa_voice',
            child: IconButton(
              iconSize: 30,
              icon: const Icon(Icons.call),
              onPressed: () => tapTarget('btn_wa_voice'),
            ),
          ),
          CompanionTarget(
            id: Targets.waVideo,
            child: IconButton(
              iconSize: 30,
              icon: const Icon(Icons.videocam),
              onPressed: () => _video(context),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const PracticeBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                _Bubble('امی جان، کیسی ہیں؟ ویڈیو کال کریں!', mine: false),
                _Bubble('Ammi, how are you? Do a video call!', mine: false),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: const Row(children: [
              Icon(Icons.emoji_emotions_outlined, color: Colors.black45),
              SizedBox(width: 8),
              Expanded(child: Text('پیغام لکھیں…', style: TextStyle(color: Colors.black38, fontSize: 18))),
              Icon(Icons.mic, color: Color(0xFF075E54)),
            ]),
          ),
          const SizedBox(height: 150),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  const _Bubble(this.text, {required this.mine});
  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFDCF8C6) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: const TextStyle(fontSize: 19)),
        ),
      );
}
