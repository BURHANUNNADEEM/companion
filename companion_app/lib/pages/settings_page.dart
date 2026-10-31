import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';
import '../config.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _serverOk;

  @override
  void initState() {
    super.initState();
    backend.ping().then((ok) {
      if (mounted) setState(() => _serverOk = ok);
    });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 18))));

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سارا ڈیٹا مٹا دیں؟  •  Delete my data?'),
        content: const Text('آپ کی ترقی، سرگرمی اور اجازتیں فون اور سرور دونوں سے مٹ جائیں گی۔'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('نہیں')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ہاں، مٹا دیں'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final server = await backend.deleteServerData();
    await companion.deleteAllData();
    if (!mounted) return;
    _toast(server ? 'سب مٹا دیا گیا (فون + سرور)' : 'فون سے مٹا دیا گیا (سرور تک نہیں پہنچ سکے)');
    goHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سیٹنگ  •  Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over),
            title: const Text('آواز میں سمجھائیں  •  Voice help', style: TextStyle(fontSize: 19)),
            subtitle: Text(companion.tts.urduAvailable
                ? 'Urdu voice found'
                : 'Urdu voice not installed: install it in phone text-to-speech settings'),
            value: companion.voiceOn,
            onChanged: (v) => setState(() => companion.voiceOn = v),
          ),
          ListTile(
            leading: Icon(Icons.cloud, color: _serverOk == true ? Colors.green : Colors.grey),
            title: const Text('Server', style: TextStyle(fontSize: 19)),
            subtitle: Text(_serverOk == null
                ? 'Checking $apiBaseUrl …'
                : _serverOk!
                    ? 'Connected to $apiBaseUrl'
                    : 'Offline ($apiBaseUrl). The app still works on this phone.'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Demo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset demo (first-time help)', style: TextStyle(fontSize: 18)),
            subtitle: const Text('Clears learning progress on this phone'),
            onTap: () async {
              await companion.resetDemo();
              _toast('Reset done: next tasks start with full help');
            },
          ),
          ListTile(
            leading: const Icon(Icons.fast_forward),
            title: const Text('Jump to attempt 3 (Call)', style: TextStyle(fontSize: 18)),
            subtitle: const Text('Shows lighter help; the next success earns 🌳'),
            onTap: () {
              companion.seedDemo(TaskIds.call, clean: 2);
              _toast('Call task: highlight-only help now');
            },
          ),
          ListTile(
            leading: const Icon(Icons.fast_forward),
            title: const Text('Jump to attempt 3 (WhatsApp)', style: TextStyle(fontSize: 18)),
            onTap: () {
              companion.seedDemo(TaskIds.whatsappVideo, clean: 2);
              _toast('WhatsApp task: highlight-only help now');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('میرا ڈیٹا مٹائیں  •  Delete my data', style: TextStyle(fontSize: 19)),
            onTap: _confirmDelete,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('سائن آؤٹ  •  Sign out', style: TextStyle(fontSize: 19)),
            onTap: () async {
              backend.stop();
              await FirebaseAuth.instance.signOut();
              if (context.mounted) goHome(context);
            },
          ),
        ],
      ),
    );
  }
}
