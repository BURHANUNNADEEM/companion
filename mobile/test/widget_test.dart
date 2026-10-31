import 'package:companion/l10n/strings.dart';
import 'package:companion/screens/family_screen.dart' show SummaryView;
import 'package:companion/services/app_state.dart';
import 'package:companion/theme.dart';
import 'package:companion/widgets/big_tile.dart';
import 'package:companion/widgets/guidance_overlay.dart';
import 'package:companion/widgets/step_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget host(Widget child, {String lang = 'ur'}) {
  final state = AppState()..lang = lang;
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.build(lang),
      home: Directionality(
        textDirection: lang == 'ur' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('big tile meets 56dp tap target and 20sp text (F1)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(Center(
      child: SizedBox(
        width: 180,
        child: BigTile(label: 'کال کریں', icon: Icons.call, color: Colors.green, onTap: () => taps++),
      ),
    )));
    final size = tester.getSize(find.byType(BigTile));
    expect(size.height, greaterThanOrEqualTo(56));
    expect(size.width, greaterThanOrEqualTo(56));
    final text = tester.widget<Text>(find.text('کال کریں'));
    expect(text.style!.fontSize, greaterThanOrEqualTo(20));
    await tester.tap(find.byType(BigTile));
    expect(taps, 1);
  });

  testWidgets('overlay: kind wording, choices, dismissed with ONE tap on Not now (F4)', (tester) async {
    var dismissed = 0;
    var accepted = '';
    final s = S('ur');
    await tester.pumpWidget(host(StatefulBuilder(builder: (context, setState) {
      return Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Colors.white)),
        if (dismissed == 0)
          Positioned.fill(
            child: GuidanceOverlay(
              title: s.t('need_hand'),
              sentence: s.t('tap_here_to', {'task': 'کال کریں'}),
              targetRect: const Rect.fromLTWH(20, 100, 150, 150),
              choices: [OverlayChoice('کال کریں', () => accepted = 'call')],
              notNowLabel: s.t('not_now'),
              onNotNow: () => setState(() => dismissed++),
              somethingElseLabel: s.t('something_else'),
              onSomethingElse: () {},
            ),
          ),
      ]);
    })));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('کیا مدد چاہیے؟'), findsOneWidget);
    expect(find.text('کال کریں کے لیے یہاں دبائیں'), findsOneWidget);
    expect(find.text('کچھ اور'), findsOneWidget);
    expect(find.textContaining('confused'), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'کال کریں'));
    expect(accepted, 'call');
    await tester.tap(find.text('ابھی نہیں'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(dismissed, 1);
    expect(find.byType(GuidanceOverlay), findsNothing);
  });

  testWidgets('step progress shows stars for finished steps', (tester) async {
    await tester.pumpWidget(host(const StepProgress(total: 3, current: 2, label: 'قدم 3 از 3')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Urdu layout is right-to-left', (tester) async {
    await tester.pumpWidget(host(Builder(builder: (c) => Text(S.of(c).t('hello')))));
    expect(find.text('السلام علیکم'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('السلام علیکم')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('caregiver summary shows counts only, in both languages (F9)', (tester) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final summary = {
      'last_active': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      'tasks_completed_per_day': {today: 4},
      'struggle_episodes_per_day': {today: 2},
      'friction_tasks': [
        {'task': 'whatsapp', 'count': 2, 'label': {'en': 'WhatsApp video call', 'ur': 'واٹس ایپ ویڈیو کال'}}
      ],
      'scam_checks': {'total': 3, 'verdicts': {'likely_scam': 1, 'be_careful': 1, 'probably_fine': 1}},
    };
    await tester.pumpWidget(host(SummaryView(summary: summary), lang: 'en'));
    expect(find.text('Tasks done (7 days): 4'), findsOneWidget);
    expect(find.text('Times they needed help (7 days): 2'), findsOneWidget);
    expect(find.text('Messages checked: 3 (likely scams: 1)'), findsOneWidget);
    expect(find.textContaining('WhatsApp video call'), findsOneWidget);

    await tester.pumpWidget(host(SummaryView(summary: summary), lang: 'ur'));
    expect(find.text('مکمل کام (7 دن): 4'), findsOneWidget);
    expect(find.textContaining('واٹس ایپ ویڈیو کال'), findsOneWidget);
  });
}
