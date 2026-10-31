import 'package:companion/l10n/strings.dart';
import 'package:companion/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every UI string exists in both English and Urdu', () {
    final en = S.strings['en']!.keys.toSet();
    final ur = S.strings['ur']!.keys.toSet();
    expect(en.difference(ur), isEmpty, reason: 'missing in Urdu');
    expect(ur.difference(en), isEmpty, reason: 'missing in English');
    for (final k in en) {
      expect(S.strings['en']![k]!.trim(), isNotEmpty, reason: 'en:$k');
      expect(S.strings['ur']![k]!.trim(), isNotEmpty, reason: 'ur:$k');
    }
  });

  test('placeholders match between languages', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final k in S.strings['en']!.keys) {
      final a = re.allMatches(S.strings['en']![k]!).map((m) => m.group(1)).toSet();
      final b = re.allMatches(S.strings['ur']![k]!).map((m) => m.group(1)).toSet();
      expect(a, b, reason: k);
    }
  });

  test('Urdu is right-to-left, English left-to-right', () {
    expect(S('ur').direction, TextDirection.rtl);
    expect(S('en').direction, TextDirection.ltr);
  });

  test('t() fills placeholders and pick() chooses the language', () {
    expect(S('en').t('step_of', {'n': '1', 'total': '3'}), 'Step 1 of 3');
    expect(S('ur').t('step_of', {'n': '1', 'total': '3'}), 'قدم 1 از 3');
    expect(S('ur').pick({'en': 'Call', 'ur': 'کال'}), 'کال');
    expect(S('en').pick({'en': 'Call', 'ur': 'کال'}), 'Call');
    expect(S('ur').pick({'en': 'only english'}), 'only english');
  });

  test('home has 4-6 tiles, each labelled in both languages', () {
    expect(kHomeTiles.length, inInclusiveRange(4, 6));
    for (final t in kHomeTiles) {
      expect(t.en, isNotEmpty);
      expect(t.ur, isNotEmpty);
    }
  });
}
