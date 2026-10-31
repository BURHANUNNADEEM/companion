import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/app_state.dart';
import '../services/services.dart';
import '../services/voice_service.dart';

/// Push-to-talk sheet (F7). Shows live text while listening and ALWAYS offers a typed fallback.
/// Returns the transcript (or typed text), or null if cancelled.
Future<String?> showVoiceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const _VoiceSheet(),
  );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with SingleTickerProviderStateMixin {
  final _typed = TextEditingController();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  String _partial = '';
  bool _listening = false;
  late final VoiceService _voice;

  @override
  void initState() {
    super.initState();
    _voice = context.read<AppServices>().voice;
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  Future<void> _listen() async {
    final voice = _voice;
    final lang = context.read<AppState>().lang;
    setState(() {
      _listening = true;
      _partial = '';
    });
    final text = await voice.listen(lang, onPartial: (p) {
      if (mounted) setState(() => _partial = p);
    });
    if (!mounted) return;
    setState(() => _listening = false);
    if (text.trim().isNotEmpty) Navigator.pop(context, text.trim());
  }

  @override
  void dispose() {
    _voice.stopListening();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.1).animate(_pulse),
            child: GestureDetector(
              onTap: _listening ? null : _listen,
              child: CircleAvatar(
                radius: 52,
                backgroundColor: _listening ? const Color(0xFFB71C1C) : const Color(0xFF0B5D3B),
                child: const Icon(Icons.mic_rounded, size: 60, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_listening ? s.t('listening') : s.t('speak'),
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          // Visible text alongside audio (F7).
          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
            child: Text(_partial, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _typed,
            style: const TextStyle(fontSize: 22),
            decoration: InputDecoration(
              hintText: s.isUrdu ? 'یا یہاں لکھیں…' : 'Or type here…',
              suffixIcon: IconButton(
                iconSize: 34,
                icon: const Icon(Icons.send_rounded),
                onPressed: () {
                  if (_typed.text.trim().isNotEmpty) Navigator.pop(context, _typed.text.trim());
                },
              ),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(s.t('cancel'))),
        ],
      ),
    );
  }
}
