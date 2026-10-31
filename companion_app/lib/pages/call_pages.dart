import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';
import '../config.dart';
import '../ui/widgets.dart';

/// Other people in the list. Tapping them during the guided task counts as a
/// "wrong tap" (that is what lets the app notice confusion).
const otherPeople = [
  ('sara', 'سارہ (بیٹی)', 'Sara (daughter)', Color(0xFF9C36B5)),
  ('bilal', 'بلال (پوتا)', 'Bilal (grandson)', Color(0xFF1971C2)),
  ('doctor', 'ڈاکٹر صاحب', 'Doctor', Color(0xFF5C940D)),
];

class PeopleList extends StatelessWidget {
  final String nextRoute;
  const PeopleList({super.key, required this.nextRoute});

  Future<void> _tapOther(BuildContext context, String id) async {
    await tapTarget(Targets.contact(id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('آج ہم علی کو فون کرنا سیکھ رہے ہیں۔ علی کا نام ڈھونڈیں۔', style: TextStyle(fontSize: 18)),
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 160),
      children: [
        for (final p in otherPeople.take(1))
          PersonTile(targetId: Targets.contact(p.$1), nameUr: p.$2, nameEn: p.$3, color: p.$4,
              onTap: () => _tapOther(context, p.$1)),
        PersonTile(
          targetId: Targets.contact('son'),
          nameUr: helperNameUr,
          nameEn: helperNameEn,
          color: const Color(0xFFE67700),
          onTap: () async {
            await tapTarget(Targets.contact('son'));
            if (context.mounted) Navigator.pushNamed(context, nextRoute);
          },
        ),
        for (final p in otherPeople.skip(1))
          PersonTile(targetId: Targets.contact(p.$1), nameUr: p.$2, nameEn: p.$3, color: p.$4,
              onTap: () => _tapOther(context, p.$1)),
      ],
    );
  }
}

class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('کس کو فون کریں؟  •  Who to call?')),
        body: const PeopleList(nextRoute: Screens.confirmCall),
      );
}

class ConfirmCallPage extends StatelessWidget {
  const ConfirmCallPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('کال  •  Call')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const CircleAvatar(
              radius: 64,
              backgroundColor: Color(0xFFE67700),
              child: Icon(Icons.person, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(helperNameUr, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const Text(helperNameEn, style: TextStyle(fontSize: 18, color: Colors.black54)),
            const SizedBox(height: 8),
            const Text('کال ملانی ہے؟', style: TextStyle(fontSize: 24)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [
                  CompanionTarget(
                    id: 'btn_call_red',
                    child: FloatingActionButton.large(
                      heroTag: 'red',
                      backgroundColor: Colors.red,
                      onPressed: () async {
                        await tapTarget('btn_call_red');
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Icon(Icons.call_end, size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('واپس', style: TextStyle(fontSize: 20)),
                ]),
                Column(children: [
                  CompanionTarget(
                    id: Targets.callGreen,
                    child: FloatingActionButton.large(
                      heroTag: 'green',
                      backgroundColor: Colors.green,
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await tapTarget(Targets.callGreen); // opens the real dialer after the praise
                        if (nav.mounted) nav.pushNamedAndRemoveUntil('/', (_) => false);
                      },
                      child: const Icon(Icons.call, size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('کال ملائیں', style: TextStyle(fontSize: 20)),
                ]),
              ],
            ),
            const SizedBox(height: 180),
          ],
        ),
      ),
    );
  }
}
