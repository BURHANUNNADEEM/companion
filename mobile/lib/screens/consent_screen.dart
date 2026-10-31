import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../widgets/ui_helpers.dart';
import '../services/app_state.dart';
import '../services/services.dart';
import '../widgets/language_toggle.dart';

/// Plain-language consent (F5). Nothing is logged until "I agree" is pressed.
/// Defaults: tracking shown ON (takes effect only after accepting), sharing OFF, text storage OFF.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool tracking = true;
  bool sharing = false;
  bool storage = false;
  Map<String, dynamic> texts = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().api.get('/consent').then((r) {
      if (mounted) setState(() => texts = Map<String, dynamic>.from(r['text'] as Map));
    }).catchError((_) {});
  }

  Widget _item(String title, String key, bool? value, ValueChanged<bool>? onChanged) {
    final s = S.of(context);
    final body = s.pick(texts[key]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            if (value != null) Transform.scale(scale: 1.3, child: Switch(value: value, onChanged: onChanged)),
          ]),
          if (body.isNotEmpty) Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() => busy = true);
    try {
      final isParent = context.read<AppState>().role == 'parent';
      await context.read<AppState>().saveConsent({
        'activity_tracking': isParent && tracking,
        'caregiver_sharing': isParent && sharing,
        'scam_text_storage': isParent && storage,
        'ai_disclosure': true,
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isParent = context.watch<AppState>().role == 'parent';
    return Scaffold(
      appBar: AppBar(title: Text(s.t('consent_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Align(child: LanguageToggle()),
          const SizedBox(height: 12),
          Text(s.t('consent_intro'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
          if (isParent) ...[
            _item(s.t('consent_tracking'), 'activity_tracking', tracking, (v) => setState(() => tracking = v)),
            _item(s.t('consent_sharing'), 'caregiver_sharing', sharing, (v) => setState(() => sharing = v)),
            _item(s.t('consent_storage'), 'scam_text_storage', storage, (v) => setState(() => storage = v)),
          ],
          _item(s.t('consent_ai'), 'ai_disclosure', null, null),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: busy ? null : _accept, child: Text(s.t('consent_accept'))),
        ],
      ),
    );
  }
}
