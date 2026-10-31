import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

/// Big اردو / English switch, available on every first-run screen and in Settings.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SegmentedButton<String>(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(120, 60),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      segments: const [
        ButtonSegment(value: 'ur', label: Text('اردو')),
        ButtonSegment(value: 'en', label: Text('English')),
      ],
      selected: {state.lang},
      onSelectionChanged: (v) => state.setLang(v.first),
    );
  }
}
