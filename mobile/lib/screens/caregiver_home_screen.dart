import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/services.dart';
import '../widgets/ui_helpers.dart';
import 'family_screen.dart' show SummaryView;
import 'settings_screen.dart';

/// Caregiver mode (F9): accept invite code, privacy-respecting summaries, in-app alerts, guide cards.
class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  final _code = TextEditingController();
  List<Map<String, dynamic>> _parents = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _pendingLinks = [];
  Timer? _poll;
  late final AppServices _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    _reload();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _reload()); // in-app alerts
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final sum = await _svc.api.get('/caregiver/summary');
      final al = await _svc.api.get('/caregiver/alerts');
      final links = await _svc.api.get('/caregiver/links');
      if (!mounted) return;
      setState(() {
        _parents = (sum['parents'] as List).cast<Map>().map(Map<String, dynamic>.from).toList();
        _alerts = (al['alerts'] as List).cast<Map>().map(Map<String, dynamic>.from).toList();
        _pendingLinks = (links['links'] as List)
            .cast<Map>()
            .map(Map<String, dynamic>.from)
            .where((l) => l['status'] == 'pending')
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _accept() async {
    final s = S.read(context);
    try {
      await _svc.api.post('/caregiver/accept', {'code': _code.text.trim()});
      _code.clear();
      if (mounted) showMessage(context, s.t('linked_wait'));
      _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _seen(Map<String, dynamic> a) async {
    try {
      await _svc.api.post('/caregiver/alerts/${a['id']}/seen');
      _reload();
    } catch (_) {}
  }

  Future<void> _sendGuide(Map<String, dynamic> parent) async {
    final s = S.read(context);
    final text = TextEditingController();
    String? workflow;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(s.t('send_guide')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: text, maxLength: 280, maxLines: 3, decoration: InputDecoration(hintText: s.t('guide_text'))),
            DropdownButton<String?>(
              isExpanded: true,
              value: workflow,
              hint: Text(s.t('show_me_how')),
              items: const [
                DropdownMenuItem(value: null, child: Text('—')),
                DropdownMenuItem(value: 'open_photos', child: Text('Photos / تصویریں')),
                DropdownMenuItem(value: 'call_contact', child: Text('Call / کال')),
                DropdownMenuItem(value: 'whatsapp_video_call', child: Text('WhatsApp video / واٹس ایپ ویڈیو')),
                DropdownMenuItem(value: 'wifi_on', child: Text('Wi-Fi / وائی فائی')),
                DropdownMenuItem(value: 'scam_check', child: Text('Check a message / پیغام چیک')),
              ],
              onChanged: (v) => setD(() => workflow = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('send_guide'))),
          ],
        ),
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    try {
      await _svc.api.post('/caregiver/guide-cards', {
        'parent_id': parent['parent_id'],
        'text': text.text.trim(),
        if (workflow != null) 'workflow_id': workflow,
      });
      if (mounted) showMessage(context, s.t('sent'));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final unseen = _alerts.where((a) => a['seen'] != true).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('caregiver_title')),
        actions: [
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: s.t('enter_invite_code')),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _accept, child: Text(s.t('link'))),
            ]),
            if (_pendingLinks.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.t('linked_wait'), style: const TextStyle(fontSize: 18))),
            const SizedBox(height: 16),
            Row(children: [
              Text(s.t('alerts'), style: Theme.of(context).textTheme.titleLarge),
              if (unseen > 0) ...[
                const SizedBox(width: 8),
                CircleAvatar(radius: 16, backgroundColor: Colors.red, child: Text('$unseen', style: const TextStyle(color: Colors.white))),
              ],
            ]),
            if (_alerts.isEmpty) Text(s.t('no_alerts'), style: const TextStyle(fontSize: 20)),
            for (final a in _alerts.take(20))
              Card(
                color: a['seen'] == true ? null : const Color(0xFFFFEBEE),
                child: ListTile(
                  minVerticalPadding: 12,
                  leading: Icon(
                    switch (a['type']) {
                      'scam_shared' => Icons.shield,
                      'inactivity' => Icons.bedtime,
                      _ => Icons.help_outline,
                    },
                    size: 34,
                  ),
                  title: Text(s.pick((a['payload'] as Map?)?['message']), style: const TextStyle(fontSize: 20)),
                  subtitle: Text(DateTime.parse(a['created_at'] as String).toLocal().toString().substring(0, 16)),
                  onTap: a['seen'] == true ? null : () => _seen(a),
                ),
              ),
            const SizedBox(height: 16),
            if (_parents.isEmpty) Text(s.t('no_parents'), style: const TextStyle(fontSize: 20)),
            for (final p in _parents) ...[
              Text(p['display_name'] as String? ?? '—', style: Theme.of(context).textTheme.titleLarge),
              SummaryView(summary: p),
              OutlinedButton.icon(
                onPressed: () => _sendGuide(p),
                icon: const Icon(Icons.lightbulb_outline, size: 28),
                label: Text(s.t('send_guide')),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
