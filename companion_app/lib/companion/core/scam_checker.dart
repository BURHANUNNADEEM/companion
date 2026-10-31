import 'models.dart';

/// Rule-based scam check (PRD F6, rules only — no LLM, no network).
/// Understands English, Roman Urdu and Urdu script. Never claims certainty.
/// The message text is never stored or logged; only the verdict is.
class ScamChecker {
  static const officialDomains = {
    'hbl.com', 'meezanbank.com', 'ubldigital.com', 'mcb.com.pk', 'bankalfalah.com',
    'jazzcash.com.pk', 'easypaisa.com.pk', 'bisp.gov.pk', 'nadra.gov.pk', 'fbr.gov.pk',
    'sbp.org.pk', 'pta.gov.pk', 'gov.pk',
  };

  static final _rules = <_Rule>[
    _Rule(
      'asks_code',
      5,
      [
        r'\b(otp|one[\s-]?time|verification code|pin|password|passcode|cvv)\b',
        r'\bcode\s+(bhej|send|share|bata|btaa?)',
        r'(کوڈ|پن کوڈ|پاس ورڈ|خفیہ نمبر)',
      ],
      'یہ آپ سے کوڈ، پن یا پاس ورڈ مانگ رہا ہے۔',
      'It asks for a code, PIN or password.',
      'کوڈ کسی کو نہ بتائیں۔ بینک اور حکومت کبھی کوڈ نہیں مانگتے۔',
      'Do not share the code. Banks and the government never ask for it.',
      'کوڈ = چابی۔ اپنی چابی کسی کو نہیں دیتے۔',
      'A code is like your house key. Never give it to anyone.',
    ),
    _Rule(
      'personal_info',
      3,
      [r'\b(cnic|id card|account (no|number)|card (no|number)|atm)\b', r'(شناختی کارڈ|اکاؤنٹ نمبر|کارڈ نمبر)'],
      'یہ آپ کا شناختی کارڈ یا اکاؤنٹ نمبر مانگ رہا ہے۔',
      'It asks for your ID card or account number.',
      'اپنی معلومات نہ بھیجیں۔ ضرورت ہو تو خود بینک جائیں یا کارڈ کے پیچھے والے نمبر پر فون کریں۔',
      'Do not send your details. Call your bank using the number on the back of your card.',
      'اپنی ذاتی معلومات صرف خود جا کر دیں، پیغام میں کبھی نہیں۔',
      'Give personal details only in person, never by message.',
    ),
    _Rule(
      'prize',
      3,
      [
        r'\b(won|winner|prize|lottery|lucky draw|congratulations|congrats|inaam|jeet\s?gay?e?)\b',
        r'(انعام|مبارک ہو|جیت گئے|جیت گئی|لکی ڈرا)',
      ],
      'یہ کہہ رہا ہے کہ آپ نے انعام جیتا ہے۔',
      'It says you have won a prize.',
      'جواب نہ دیں اور لنک نہ کھولیں۔',
      'Do not reply and do not open the link.',
      'جس مقابلے میں حصہ نہیں لیا، اس کا انعام نہیں ملتا۔',
      'You cannot win a contest you never entered.',
    ),
    _Rule(
      'asks_money',
      3,
      [
        r'\b(processing fee|registration fee|delivery fee|send (money|rs|pkr|payment)|advance|transfer (rs|pkr|money))\b',
        r'\b(paise|paisay)\s+(bhej|send|jama)',
        r'(فیس|پیسے بھیج|رقم بھیج|جمع کروائیں)',
      ],
      'یہ آپ سے پیسے یا فیس مانگ رہا ہے۔',
      'It asks you to pay money or a fee.',
      'پیسے نہ بھیجیں۔ اصلی امداد یا انعام کے لیے فیس نہیں لی جاتی۔',
      'Do not send money. Real aid or prizes never need a fee.',
      'پیسے لینے کے لیے پیسے دینے پڑیں تو یہ دھوکہ ہے۔',
      'If you must pay to receive money, it is a scam.',
    ),
    _Rule(
      'urgency',
      2,
      [
        r'\b(urgent|immediately|within 24|blocked?|suspend(ed)?|expire[sd]?|last chance|foran)\b',
        r'(فوراً|فوری|بند ہو جائے|بلاک|آخری موقع)',
      ],
      'یہ آپ کو جلدی کرنے یا ڈرانے کی کوشش کر رہا ہے۔',
      'It tries to rush or scare you.',
      'جلدی نہ کریں۔ پہلے گھر والوں سے بات کریں۔',
      'Slow down. Talk to your family first.',
      'جو پیغام ڈرائے یا جلدی کروائے، اس پر رک جائیں۔',
      'If a message rushes or scares you, stop and wait.',
    ),
    _Rule(
      'gov_aid',
      2,
      [r'\b(bisp|benazir|ehsaas|kafaalat|nadra|fbr)\b', r'(بینظیر|احساس|کفالت|نادرا)'],
      'یہ سرکاری امداد (بی آئی ایس پی / احساس) کا نام استعمال کر رہا ہے۔',
      'It uses the name of government aid (BISP / Ehsaas).',
      'سرکاری امداد کی تصدیق صرف 8171 پر اپنا شناختی کارڈ نمبر بھیج کر کریں، کسی لنک سے نہیں۔',
      'Verify government aid only through the official 8171 service, never through a link.',
      'حکومت لنک بھیج کر پیسے نہیں دیتی۔',
      'The government does not pay through links.',
    ),
    _Rule(
      'call_back',
      1,
      [r'\b(call (this|on|us)|is number par)\b', r'(اس نمبر پر کال|فون کریں)'],
      'یہ آپ سے کسی نامعلوم نمبر پر فون کروانا چاہتا ہے۔',
      'It asks you to call an unknown number.',
      'نامعلوم نمبر پر فون نہ کریں۔',
      'Do not call unknown numbers.',
      'صرف وہ نمبر ملائیں جو آپ پہلے سے جانتی ہیں۔',
      'Only call numbers you already know.',
    ),
  ];

  static final _url = RegExp(
      r'((https?:\/\/|www\.)[^\s]+|\b([a-z0-9-]+\.)+(com|pk|net|org|info|xyz|top|click|online|site|live|ly|me|gl|gd|at|link|buzz|icu|shop|cfd|sbs|io|co)\b(\/[^\s]*)?)',
      caseSensitive: false);
  static const _shorteners = {'bit.ly', 'tinyurl.com', 'goo.gl', 'cutt.ly', 't.me', 'wa.link', 'rb.gy', 'is.gd', 'shorturl.at'};
  static const _badTlds = {'xyz', 'top', 'click', 'info', 'online', 'site', 'live', 'buzz', 'icu', 'shop', 'cfd', 'sbs'};
  static final _claimsOfficial = RegExp(
      r'\b(hbl|meezan|ubl|mcb|alfalah|jazz ?cash|easy ?paisa|bisp|benazir|ehsaas|nadra|fbr|bank|state bank)\b|(بینک|جاز کیش|ایزی پیسہ|بینظیر|نادرا)',
      caseSensitive: false);

  ScamVerdict check(String text) {
    final t = text.trim();
    final reasons = <ScamReason>[];
    final hits = <_Rule>[];
    for (final r in _rules) {
      if (r.patterns.any((p) => RegExp(p, caseSensitive: false, unicode: true).hasMatch(t))) {
        hits.add(r);
        reasons.add(ScamReason(r.id, r.reasonUr, r.reasonEn, r.weight));
      }
    }

    // ---- links ----
    final domains = _url
        .allMatches(t)
        .map((m) => _domainOf(m.group(0)!))
        .where((d) => d.contains('.') && !RegExp(r'^\d+(\.\d+)*$').hasMatch(d))
        .toSet();
    if (domains.isNotEmpty) {
      final official = domains.where(_isOfficial).toSet();
      final unofficial = domains.difference(official);
      final risky = unofficial.where((d) => _shorteners.contains(d) || _badTlds.contains(d.split('.').last));
      if (_claimsOfficial.hasMatch(t) && unofficial.isNotEmpty) {
        reasons.add(const ScamReason(
            'link_mismatch',
            'یہ بینک یا حکومت کا نام لیتا ہے مگر لنک ان کا اصلی نہیں ہے۔',
            'It claims to be a bank or the government, but the link is not their real website.',
            3));
      } else if (risky.isNotEmpty) {
        reasons.add(const ScamReason('risky_link', 'اس میں چھپا ہوا یا مشکوک لنک ہے۔',
            'It contains a hidden or suspicious link.', 2));
      } else if (unofficial.isNotEmpty) {
        reasons.add(const ScamReason('has_link', 'اس میں ایک لنک ہے۔', 'It contains a link.', 1));
      }
    }

    reasons.sort((a, b) => b.weight.compareTo(a.weight));
    final score = reasons.fold<int>(0, (s, r) => s + r.weight);
    final level = score >= 5
        ? ScamLevel.likelyScam
        : score >= 2
            ? ScamLevel.beCareful
            : ScamLevel.probablyFine;

    final top = hits.isEmpty ? null : (hits..sort((a, b) => b.weight.compareTo(a.weight))).first;
    final linkTop = reasons.isNotEmpty && reasons.first.ruleId.contains('link');
    final actionUr = level == ScamLevel.probablyFine
        ? 'یہ عام پیغام لگتا ہے، پھر بھی کوڈ یا پیسے کبھی نہ بھیجیں۔'
        : linkTop || top == null
            ? 'لنک نہ کھولیں اور جواب نہ دیں۔'
            : top.actionUr;
    final actionEn = level == ScamLevel.probablyFine
        ? 'This looks like a normal message, but never send codes or money.'
        : linkTop || top == null
            ? 'Do not open the link and do not reply.'
            : top.actionEn;
    final lessonUr = top?.lessonUr ?? 'اصلی ادارے لنک بھیج کر معلومات نہیں مانگتے۔';
    final lessonEn = top?.lessonEn ?? 'Real organisations do not ask for details through links.';

    return ScamVerdict(
      level: level,
      score: score,
      reasons: reasons,
      actionUr: actionUr,
      actionEn: actionEn,
      lessonUr: lessonUr,
      lessonEn: lessonEn,
    );
  }

  static String _domainOf(String url) {
    var u = url.toLowerCase().replaceFirst(RegExp(r'^https?:\/\/'), '');
    u = u.split('/').first.split('?').first;
    if (u.startsWith('www.')) u = u.substring(4);
    return u;
  }

  static bool _isOfficial(String d) =>
      officialDomains.any((o) => d == o || d.endsWith('.$o'));

  /// Remove numbers, CNICs and emails before any text leaves the phone
  /// (for a future LLM step — PRD F8). Not used by the rule engine itself.
  static String redact(String text) => text
      .replaceAll(RegExp(r'\b\d{5}-\d{7}-\d\b'), '[CNIC]')
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '[EMAIL]')
      .replaceAll(RegExp(r'(\+?\d[\d\s-]{7,}\d)'), '[NUMBER]');
}

class _Rule {
  final String id;
  final int weight;
  final List<String> patterns;
  final String reasonUr, reasonEn, actionUr, actionEn, lessonUr, lessonEn;
  const _Rule(this.id, this.weight, this.patterns, this.reasonUr, this.reasonEn, this.actionUr,
      this.actionEn, this.lessonUr, this.lessonEn);
}
