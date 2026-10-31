import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';
import '../config.dart';
import '../ui/widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    backend.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => companion.screen(Screens.home));
  }

  Future<void> _go(String target, String route) async {
    await tapTarget(target);
    if (mounted) Navigator.pushNamed(context, route);
  }

  Future<void> _askFamily() async {
    await tapTarget(Targets.tileAskFamily);
    await companion.tryForReal(const LaunchAction(LaunchKind.dial, phone: helperPhone));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: companion,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          title: const Text('کمپینین  •  Companion', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              tooltip: 'Progress',
              icon: const Icon(Icons.emoji_events_outlined, size: 30),
              onPressed: () => Navigator.pushNamed(context, '/progress'),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined, size: 30),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('السلام علیکم! آج کیا کرنا ہے؟',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const Text('What would you like to do today?',
                    textDirection: TextDirection.ltr, style: TextStyle(fontSize: 15, color: Colors.black54)),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.15,
                    children: [
                      BigTile(
                        targetId: Targets.tileCall,
                        icon: Icons.call,
                        labelUr: 'فون',
                        labelEn: 'Call',
                        color: const Color(0xFF2E9D57),
                        badge: stageBadge(companion.stageOf(TaskIds.call)),
                        onPressed: () => _go(Targets.tileCall, Screens.contacts),
                      ),
                      BigTile(
                        targetId: Targets.tileWhatsapp,
                        icon: Icons.videocam,
                        labelUr: 'واٹس ایپ',
                        labelEn: 'WhatsApp video',
                        color: const Color(0xFF128C7E),
                        badge: stageBadge(companion.stageOf(TaskIds.whatsappVideo)),
                        onPressed: () => _go(Targets.tileWhatsapp, Screens.waContacts),
                      ),
                      BigTile(
                        targetId: Targets.tileCheckMessage,
                        icon: Icons.shield_outlined,
                        labelUr: 'پیغام چیک کریں',
                        labelEn: 'Check a message',
                        color: const Color(0xFF3B5BDB),
                        badge: stageBadge(companion.stageOf(TaskIds.scamCheck)),
                        onPressed: () => _go(Targets.tileCheckMessage, Screens.scamCheck),
                      ),
                      BigTile(
                        targetId: Targets.tileSettings,
                        icon: Icons.settings_suggest,
                        labelUr: 'فون کی سیٹنگ',
                        labelEn: 'Phone settings',
                        color: const Color(0xFF5F3DC4),
                        onPressed: () async {
                          await tapTarget(Targets.tileSettings);
                          if (context.mounted) Navigator.pushNamed(context, Screens.settingsMenu);
                        },
                      ),
                      BigTile(
                        targetId: Targets.tileBank,
                        icon: Icons.account_balance,
                        labelUr: 'بینک کی مشق',
                        labelEn: 'Banking practice',
                        color: const Color(0xFF0B7285),
                        badge: stageBadge(companion.stageOf(TaskIds.bankPractice)),
                        onPressed: () => _go(Targets.tileBank, Screens.bankPractice),
                      ),
                      BigTile(
                        targetId: Targets.tileAskFamily,
                        icon: Icons.family_restroom,
                        labelUr: 'گھر والوں سے پوچھیں',
                        labelEn: 'Ask my family',
                        color: const Color(0xFFD9480F),
                        onPressed: _askFamily,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: OutlinedButton.icon(
                    onPressed: companion.showMe,
                    icon: const Icon(Icons.help_outline, size: 30),
                    label: const Text('مدد چاہیے؟  •  Show me', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
