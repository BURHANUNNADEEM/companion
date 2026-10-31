import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/services.dart';
import '../widgets/ui_helpers.dart';

/// "Check this message" (F6): paste, share-in or screenshot OCR -> Likely scam / Be careful / Probably fine,
/// one plain reason, one recommended action, "ask your family", read-aloud and "Tell my family".
class ScamCheckScreen extends StatefulWidget {
  const ScamCheckScreen({super.key, this.initialText, this.source = 'paste'});
  final String? initialText;
  final String source;

  @override
  State<ScamCheckScreen> createState() => _ScamCheckScreenState();
}

class _ScamCheckScreenState extends State<ScamCheckScreen> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText ?? '');
  late String _source = widget.source;
  ScamResult? _result;
  bool _busy = false;
  bool _shared = false;
  late final AppServices _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    context.read<AppState>().tracker?.screen('scam_check');
    if ((widget.initialText ?? '').isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _paste() async {
    final t = await _svc.scamInput.paste();
    if (t != null && mounted) setState(() {
      _text.text = t;
      _source = 'paste';
      _result = null;
    });
  }

  Future<void> _screenshot() async {
    try {
      final t = await _svc.scamInput.pickScreenshotText();
      if (t != null && mounted) setState(() {
        _text.text = t;
        _source = 'screenshot';
        _result = null;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _check() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = ScamResult.fromJson(await _svc.api.scamCheck(_text.text.trim(), _source));
      if (!mounted) return;
      setState(() {
        _result = r;
        _shared = false;
      });
      context.read<AppState>().tracker?.taskCompleted('scam_check', source: _source);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tellFamily() async {
    final s = S.read(context);
    try {
      final r = await _svc.api.post('/scam/share/${_result!.id}');
      if (!mounted) return;
      final n = (r['caregivers_notified'] as num?)?.toInt() ?? 0;
      setState(() => _shared = n > 0);
      showMessage(context, n > 0 ? s.t('told_family') : s.t('no_family_linked'));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  static const _colors = {
    'likely_scam': Color(0xFFB71C1C),
    'be_careful': Color(0xFFE65100),
    'probably_fine': Color(0xFF1B7F3B),
  };
  static const _icons = {
    'likely_scam': Icons.dangerous_rounded,
    'be_careful': Icons.warning_amber_rounded,
    'probably_fine': Icons.verified_user_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('scam_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('scam_sub'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                key: const ValueKey('paste_button'),
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_rounded, size: 30),
                label: Text(s.t('paste')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _screenshot,
                icon: const Icon(Icons.image_search_rounded, size: 30),
                label: Text(s.t('pick_screenshot'), textAlign: TextAlign.center),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(s.t('ocr_note'), style: const TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            maxLines: 6,
            minLines: 3,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(hintText: s.t('message_here')),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _check,
              icon: const Icon(Icons.shield_rounded, size: 34),
              label: Text(s.t('check'), style: const TextStyle(fontSize: 26)),
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_result != null) _resultCard(s, _result!),
        ],
      ),
    );
  }

  Widget _resultCard(S s, ScamResult r) {
    final e = r.explanation;
    final color = _colors[r.verdict] ?? Colors.grey;
    final speakText = '${s.pick(e['label'])}. ${s.pick(e['reason'])} ${s.pick(e['action'])} ${s.pick(e['ask_family'])}';
    return Card(
      margin: const EdgeInsets.only(top: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: color, width: 4)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(_icons[r.verdict], color: color, size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.pick(e['label']),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color)),
            ),
            IconButton(
              iconSize: 40,
              tooltip: s.t('read_aloud'),
              icon: const Icon(Icons.volume_up_rounded),
              onPressed: () => _svc.voice.speak(speakText, s.lang),
            ),
          ]),
          const SizedBox(height: 8),
          Text(s.pick(e['reason']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(s.pick(e['action']), style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(s.pick(e['ask_family']), style: const TextStyle(fontSize: 20, fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _shared ? null : _tellFamily,
            icon: const Icon(Icons.family_restroom, size: 30),
            label: Text(_shared ? s.t('told_family') : s.t('tell_family')),
          ),
          TextButton(
            onPressed: () => setState(() {
              _result = null;
              _text.clear();
            }),
            child: Text(s.t('check_another')),
          ),
        ]),
      ),
    );
  }
}
