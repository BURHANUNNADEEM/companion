import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/app_state.dart';
import '../services/contacts_store.dart';
import '../services/services.dart';
import '../widgets/ui_helpers.dart';

/// Parent's family screen: saved helper/contacts (on device only), caregiver invites (F9),
/// approve/revoke links, and "what my family can see" preview.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _email = TextEditingController();
  List<Map<String, dynamic>> _links = [];
  Map<String, dynamic>? _preview;
  String? _demoCode;
  late final AppServices _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    context.read<AppState>().tracker?.screen('family');
    _reload();
  }

  Future<void> _reload() async {
    try {
      final l = await _svc.api.get('/caregiver/links');
      final p = await _svc.api.get('/me/sharing-preview');
      if (!mounted) return;
      setState(() {
        _links = (l['links'] as List).cast<Map>().map(Map<String, dynamic>.from).toList();
        _preview = Map<String, dynamic>.from(p as Map);
      });
    } catch (_) {}
  }

  Future<void> _invite() async {
    final s = S.read(context);
    if (!_email.text.contains('@')) return;
    try {
      final r = await _svc.api.post('/caregiver/invite', {'email': _email.text.trim()});
      if (!mounted) return;
      setState(() => _demoCode = r['dev_invite_code'] as String?);
      _email.clear();
      showMessage(context, s.t('invite_sent'));
      _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _approve(String id) async {
    try {
      await _svc.api.post('/caregiver/approve/$id');
      _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _revoke(String id) async {
    try {
      await _svc.api.delete('/caregiver/link/$id');
      _reload();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _editContact([int? index]) async {
    final s = S.read(context);
    final store = context.read<AppState>().contacts;
    final existing = index == null ? null : store.contacts[index];
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    var relation = existing?.relation ?? 'son';
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(s.t('helper_section')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s.t('helper_name'))),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('helper_phone')),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: relation,
                decoration: InputDecoration(labelText: s.t('helper_relation')),
                items: [
                  for (final e in kRelations.entries)
                    DropdownMenuItem(value: e.key, child: Text(s.isUrdu ? e.value[1] : e.value[0])),
                ],
                onChanged: (v) => setD(() => relation = v ?? relation),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    if (saved != true || phone.text.trim().isEmpty) return;
    final contact = FamilyContact(name.text.trim(), phone.text.trim(), relation);
    setState(() {
      if (index == null) {
        store.contacts.add(contact);
      } else {
        store.contacts[index] = contact;
      }
    });
    await store.save();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final store = context.watch<AppState>().contacts;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('family_title'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('helper_section'), style: Theme.of(context).textTheme.titleLarge),
            for (var i = 0; i < store.contacts.length; i++)
              Card(
                child: ListTile(
                  minVerticalPadding: 14,
                  leading: Icon(i == 0 ? Icons.star_rounded : Icons.person, size: 36, color: const Color(0xFF0B5D3B)),
                  title: Text(store.contacts[i].name, style: const TextStyle(fontSize: 22)),
                  subtitle: Text(store.contacts[i].phone, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 18)),
                  onTap: () => _editContact(i),
                  trailing: IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => store.contacts.removeAt(i));
                      await store.save();
                    },
                  ),
                ),
              ),
            OutlinedButton.icon(onPressed: _editContact, icon: const Icon(Icons.add, size: 30), label: Text(s.t('add_contact'))),
            const Divider(height: 36),
            Text(s.t('invite_section'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: s.t('invite_email')),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _invite, child: Text(s.t('send_invite'))),
            if (_demoCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(s.t('demo_code', {'code': _demoCode!}),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 8),
            for (final l in _links) _linkTile(s, l),
            const Divider(height: 36),
            Text(s.t('what_family_sees'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _previewCard(s),
          ],
        ),
      ),
    );
  }

  Widget _linkTile(S s, Map<String, dynamic> l) {
    final status = l['status'] as String;
    final awaiting = l['awaiting_parent_approval'] == true;
    final label = status == 'active' ? s.t('active') : (awaiting ? s.t('waiting_approve') : s.t('waiting_accept'));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text((l['caregiver_name'] as String?) ?? (l['invite_email'] as String), style: const TextStyle(fontSize: 22)),
          Text(label, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Row(children: [
            if (awaiting)
              Expanded(child: ElevatedButton(onPressed: () => _approve(l['id'] as String), child: Text(s.t('approve')))),
            if (awaiting) const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _revoke(l['id'] as String), child: Text(s.t('remove')))),
          ]),
        ]),
      ),
    );
  }

  Widget _previewCard(S s) {
    final p = _preview;
    if (p == null) return const SizedBox.shrink();
    if (p['sharing'] != true) return Text(s.t('sharing_off'), style: const TextStyle(fontSize: 20));
    final sum = Map<String, dynamic>.from(p['summary'] as Map);
    return SummaryView(summary: sum);
  }
}

/// Shared by the parent preview and the caregiver dashboard so both see EXACTLY the same data.
class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.summary});
  final Map<String, dynamic> summary;

  int _sum(dynamic m) => m is Map ? m.values.fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0)) : 0;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final last = summary['last_active'] as String?;
    final whenText = last == null ? s.t('never') : _ago(DateTime.parse(last).toLocal(), s);
    final scam = Map<String, dynamic>.from(summary['scam_checks'] as Map? ?? {});
    final verdicts = Map<String, dynamic>.from(scam['verdicts'] as Map? ?? {});
    final friction = (summary['friction_tasks'] as List? ?? []).cast<Map>();
    final perDay = Map<String, dynamic>.from(summary['tasks_completed_per_day'] as Map? ?? {});
    final maxDay = perDay.values.fold<int>(1, (a, b) => ((b as num).toInt() > a) ? (b).toInt() : a);
    const style = TextStyle(fontSize: 20);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t('last_active', {'when': whenText}), style: style),
          if (summary.containsKey('tasks_completed_per_day')) ...[
            Text(s.t('tasks_today', {'n': '${_sum(summary['tasks_completed_per_day'])}'}), style: style),
            const SizedBox(height: 6),
            SizedBox(
              height: 60,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final v in perDay.values)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 6 + 54 * ((v as num).toInt() / maxDay),
                        color: const Color(0xFF0B5D3B),
                      ),
                    ),
                ]),
              ),
            ),
            Text(s.t('struggles_week', {'n': '${_sum(summary['struggle_episodes_per_day'])}'}), style: style),
          ],
          if (scam.isNotEmpty)
            Text(s.t('scam_checks', {'n': '${scam['total'] ?? 0}', 's': '${verdicts['likely_scam'] ?? 0}'}), style: style),
          if (friction.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(s.t('friction'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            for (final f in friction) Text('• ${s.pick(f['label'])} (${f['count']})', style: style),
          ],
        ]),
      ),
    );
  }

  static String _ago(DateTime t, S s) {
    final d = DateTime.now().difference(t);
    if (s.isUrdu) {
      if (d.inMinutes < 60) return '${d.inMinutes} منٹ پہلے';
      if (d.inHours < 24) return '${d.inHours} گھنٹے پہلے';
      return '${d.inDays} دن پہلے';
    }
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} days ago';
  }
}
