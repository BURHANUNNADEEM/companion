import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../widgets/ui_helpers.dart';
import '../services/app_state.dart';
import '../widgets/language_toggle.dart';

/// First sign-in: Parent or Caregiver, on a plain confirmation screen (F5). Stored server-side.
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _choose(BuildContext context, String role) async {
    final s = S.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('role_confirm_title')),
        content: Text(s.t('role_confirm_body'), style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('no'))),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('yes'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<AppState>().setRole(role);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Widget _card(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Icon(icon, size: 64, color: const Color(0xFF0B5D3B)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                Text(sub, style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('app_name'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Align(child: LanguageToggle()),
          const SizedBox(height: 20),
          Text(s.t('role_title'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _card(context, Icons.elderly_rounded, s.t('role_parent'), s.t('role_parent_sub'), () => _choose(context, 'parent')),
          const SizedBox(height: 12),
          _card(context, Icons.volunteer_activism_rounded, s.t('role_caregiver'), s.t('role_caregiver_sub'),
              () => _choose(context, 'caregiver')),
        ],
      ),
    );
  }
}
