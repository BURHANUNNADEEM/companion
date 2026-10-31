import 'package:flutter/material.dart';

import '../app_globals.dart';

/// First launch: plain-language consent. Nothing is tracked before this.
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});
  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _tracking = true;
  bool _ai = false;

  Future<void> _start() async {
    await companion.setConsent(tracking: _tracking, caregiverSharing: _tracking);
    await backend.putConsent(tracking: _tracking, ai: _ai);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.favorite, size: 64, color: Colors.indigo),
            const SizedBox(height: 12),
            const Text('خوش آمدید!', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const Text(
              'کمپینین آپ کو فون چلانا سکھاتا ہے۔ پہلی بار ہم پوری مدد کریں گے، اور ہر بار تھوڑی کم — یہاں تک کہ آپ خود کر لیں۔ آپ کچھ خراب نہیں کر سکتیں۔',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, height: 1.6),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              value: _tracking,
              onChanged: (v) => setState(() => _tracking = v),
              title: const Text('آپ کون سے بٹن دباتی ہیں، یہ یاد رکھیں', style: TextStyle(fontSize: 19)),
              subtitle: const Text(
                  'Remember which buttons I use (never what I type), so help can fade as I learn. Needed for guidance.'),
            ),
            SwitchListTile(
              value: _ai,
              onChanged: (v) => setState(() => _ai = v),
              title: const Text('مشکل پیغامات AI سے چیک کروائیں', style: TextStyle(fontSize: 19)),
              subtitle: const Text(
                  'When our rules are unsure, send the message (numbers and names removed) to Google Gemini. Off by default.'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
              onPressed: _tracking ? _start : null,
              child: const Text('شروع کریں  •  Start', style: TextStyle(fontSize: 24)),
            ),
            if (!_tracking)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('رہنمائی کے لیے پہلی اجازت ضروری ہے۔  Guidance needs the first permission.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ),
            const SizedBox(height: 10),
            const Text('آپ جب چاہیں سیٹنگ میں جا کر اپنا سارا ڈیٹا مٹا سکتی ہیں۔',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
