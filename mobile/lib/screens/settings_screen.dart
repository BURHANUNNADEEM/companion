import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/services.dart';
import '../widgets/language_toggle.dart';
import '../widgets/ui_helpers.dart';

/// Language, bigger text, privacy/consent toggles, Tier 2 accessibility, delete my data, sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _tier2Available = false;
  bool _tier2Enabled = false;
  late final AppServices _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<AppServices>();
    WidgetsBinding.instance.addObserver(this);
    context.read<AppState>().tracker?.screen('settings');
    _checkTier2();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkTier2(); // user may have toggled it in Android settings
  }

  Future<void> _checkTier2() async {
    final available = await _svc.tier2.isAvailable();
    final enabled = available && await _svc.tier2.isEnabled();
    if (mounted) setState(() {
      _tier2Available = available;
      _tier2Enabled = enabled;
    });
  }

  Future<void> _setConsent(String key, bool value) async {
    try {
      await context.read<AppState>().saveConsent({key: value});
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _delete() async {
    final s = S.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('delete_data')),
        content: Text(s.t('delete_confirm'), style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(s.t('delete_data')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    final auth = context.read<AuthService>();
    final navigator = Navigator.of(context);
    try {
      await state.deleteMyData();
      state.contacts.contacts.clear();
      await state.contacts.save();
      if (mounted) showMessage(context, s.t('deleted'));
      navigator.popUntil((r) => r.isFirst);
      await auth.signOut();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = context.watch<AppState>();
    final c = state.consent;
    final isParent = state.role == 'parent';
    Widget sw(String title, String key) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 22)),
          value: c[key] == true,
          onChanged: (v) => _setConsent(key, v),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('language'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Align(child: LanguageToggle()),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('bigger_text'), style: const TextStyle(fontSize: 22)),
            value: state.bigText,
            onChanged: state.setBigText,
          ),
          if (isParent) ...[
            const Divider(height: 30),
            Text(s.t('privacy'), style: Theme.of(context).textTheme.titleLarge),
            sw(s.t('consent_tracking'), 'activity_tracking'),
            sw(s.t('consent_sharing'), 'caregiver_sharing'),
            sw(s.t('consent_storage'), 'scam_text_storage'),
            const Divider(height: 30),
            Text(s.t('tier2_title'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(s.t('tier2_body'), style: const TextStyle(fontSize: 19)),
            const SizedBox(height: 8),
            Text(
              !_tier2Available ? s.t('tier2_unavailable') : (_tier2Enabled ? s.t('tier2_on') : s.t('tier2_off')),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (_tier2Available)
              OutlinedButton(onPressed: _svc.tier2.openAccessibilitySettings, child: Text(s.t('tier2_open_settings'))),
          ],
          const Divider(height: 30),
          OutlinedButton(
            onPressed: () async {
              final auth = context.read<AuthService>();
              Navigator.of(context).popUntil((r) => r.isFirst);
              await auth.signOut();
            },
            child: Text(s.t('sign_out')),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C)),
            onPressed: _delete,
            child: Text(s.t('delete_data')),
          ),
        ],
      ),
    );
  }
}
