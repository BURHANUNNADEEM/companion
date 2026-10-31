import 'models.dart';

/// Screen ids the UI must use (pass them to CompanionEngine.onScreen).
class Screens {
  static const home = 'home';
  static const contacts = 'contacts';
  static const confirmCall = 'confirm_call';
  static const waContacts = 'wa_contacts';
  static const waChatPractice = 'wa_chat_practice'; // MOCK screen
  static const scamCheck = 'scam_check';
  static const settingsMenu = 'settings_menu';
  static const settingsLesson = 'settings_lesson';
  static const bankPractice = 'bank_practice'; // MOCK screen
  static const bankOtp = 'bank_otp'; // MOCK screen
}

/// Target ids the UI must register (CompanionTarget(id: ...)).
class Targets {
  static const tileCall = 'tile_call';
  static const tileWhatsapp = 'tile_whatsapp';
  static const tileCheckMessage = 'tile_check_message';
  static const tileAskFamily = 'tile_ask_family';
  static String contact(String contactId) => 'contact_$contactId';
  static const callGreen = 'btn_call_green';
  static const waVideo = 'btn_wa_video';
  static const pasteButton = 'btn_paste';
  static const checkButton = 'btn_check';
  static const tileSettings = 'tile_settings';
  static const tileBank = 'tile_bank';
  static String settingsItem(String lessonId) => 'item_$lessonId';
  static const openSettings = 'btn_open_settings';
  static const bankReview = 'btn_bank_review';
  static const bankConfirm = 'btn_bank_confirm';
  static const refuseOtp = 'btn_refuse_otp';
  static const shareOtp = 'btn_share_otp';
}

/// A small "how do I…" phone-settings lesson. The app explains, then opens the
/// right Android settings screen; the user flips the switch herself.
class SettingsLesson {
  final String id; // also the task id
  final String titleUr;
  final String titleEn;
  final String settingsType; // passed to the launcher
  final String whyUr;
  final String whyEn;
  final List<String> stepsUr; // what to do once the settings screen opens
  final List<String> stepsEn;
  const SettingsLesson(this.id, this.titleUr, this.titleEn, this.settingsType, this.whyUr, this.whyEn,
      this.stepsUr, this.stepsEn);
}

const settingsLessons = <SettingsLesson>[
  SettingsLesson('wifi', 'وائی فائی چلانا', 'Turn on Wi-Fi', 'wifi',
      'گھر کا انٹرنیٹ وائی فائی سے چلتا ہے۔ اس سے موبائل کا پیکج بچتا ہے۔',
      'Home internet comes through Wi-Fi. It saves your mobile package.',
      ['اوپر والا بٹن دائیں طرف کریں تاکہ نیلا ہو جائے', 'اپنے گھر کے وائی فائی کے نام پر دبائیں', 'پاس ورڈ لکھیں (گھر والوں سے پوچھیں) اور جوڑیں دبائیں'],
      ['Slide the top switch so it turns blue', 'Tap your home Wi-Fi name', 'Type the password (ask family) and tap Connect']),
  SettingsLesson('hotspot', 'ہاٹ اسپاٹ (انٹرنیٹ شیئر کرنا)', 'Share internet (hotspot)', 'hotspot',
      'ہاٹ اسپاٹ سے آپ اپنا موبائل انٹرنیٹ کسی اور فون کو دے سکتی ہیں۔',
      'Hotspot lets another phone use your mobile internet.',
      ['"ہاٹ اسپاٹ" یا "Mobile Hotspot" پر دبائیں', 'بٹن آن کریں', 'دوسرے فون کو یہاں لکھا پاس ورڈ بتائیں'],
      ['Tap "Mobile Hotspot"', 'Turn the switch on', 'Tell the other phone the password shown here']),
  SettingsLesson('sound', 'آواز اونچی کرنا', 'Make sound louder', 'sound',
      'اگر فون کی گھنٹی سنائی نہیں دیتی تو یہاں سے آواز بڑھائیں۔',
      'If you cannot hear the phone ring, turn the volume up here.',
      ['"رنگ ٹون" یا "Ring" والی لکیر ڈھونڈیں', 'گول نشان کو دائیں طرف آخر تک کھینچیں', 'فون کی سائیڈ والے اوپر کے بٹن سے بھی آواز بڑھتی ہے'],
      ['Find the "Ring" volume line', 'Drag the dot all the way to the right', 'The upper side button also turns the volume up']),
  SettingsLesson('display', 'لکھائی بڑی کرنا', 'Bigger text and brightness', 'display',
      'لکھائی بڑی ہو تو پڑھنا آسان ہوتا ہے۔ روشنی زیادہ ہو تو اسکرین صاف دکھتی ہے۔',
      'Bigger text is easier to read. More brightness makes the screen clearer.',
      ['"Font size" یا "لکھائی کا سائز" پر دبائیں اور بڑا کریں', 'Brightness والی لکیر کو دائیں طرف کریں', 'واپس آنے کے لیے پیچھے والا تیر دبائیں'],
      ['Tap "Font size" and make it bigger', 'Move the Brightness line to the right', 'Press back to return']),
  SettingsLesson('bluetooth', 'بلوٹوتھ چلانا', 'Turn on Bluetooth', 'bluetooth',
      'بلوٹوتھ سے فون بغیر تار کے ہیڈفون یا اسپیکر سے جڑتا ہے۔',
      'Bluetooth connects the phone to headphones or a speaker without a wire.',
      ['اوپر والا بٹن آن کریں', 'اپنے ہیڈفون یا اسپیکر کا نام دبائیں', 'جڑ جائے تو "Connected" لکھا آئے گا'],
      ['Turn the top switch on', 'Tap your headphone or speaker name', 'When it says "Connected", you are done']),
];

SettingsLesson? lessonById(String id) {
  for (final l in settingsLessons) {
    if (l.id == id) return l;
  }
  return null;
}

class Contact {
  final String id;
  final String nameUr;
  final String nameEn;
  final String phone; // international, no '+', e.g. 923001234567
  const Contact(this.id, this.nameUr, this.nameEn, this.phone);
}

class TaskIds {
  static const call = 'call_family';
  static const whatsappVideo = 'whatsapp_video';
  static const scamCheck = 'scam_check';
  static const bankPractice = 'bank_practice';
  static const all = [call, whatsappVideo, scamCheck];
}

/// Builds the guided flows. Change contacts here or load them from settings.
class TaskCatalog {
  final Contact helper; // "Ask my family" person, e.g. the son
  TaskCatalog({required this.helper});

  late final Map<String, TaskFlow> flows = {
    TaskIds.call: callFlow(helper),
    TaskIds.whatsappVideo: whatsappVideoFlow(helper),
    TaskIds.scamCheck: scamCheckFlow(),
    TaskIds.bankPractice: bankPracticeFlow(),
    for (final l in settingsLessons) l.id: settingsFlow(l),
  };

  TaskFlow? operator [](String id) => flows[id];

  /// Which task does tapping this home tile start?
  String? taskForHomeTile(String targetId) => switch (targetId) {
        Targets.tileCall => TaskIds.call,
        Targets.tileWhatsapp => TaskIds.whatsappVideo,
        Targets.tileCheckMessage => TaskIds.scamCheck,
        Targets.tileBank => TaskIds.bankPractice,
        _ => targetId.startsWith('item_') && lessonById(targetId.substring(5)) != null
            ? targetId.substring(5)
            : null,
      };

  static TaskFlow settingsFlow(SettingsLesson l) => TaskFlow(
        id: l.id,
        titleUr: l.titleUr,
        titleEn: l.titleEn,
        finalAction: LaunchAction(LaunchKind.settings, settingsType: l.settingsType),
        steps: [
          TaskStep(
            screenId: Screens.settingsMenu,
            targetId: Targets.settingsItem(l.id),
            textUr: '"${l.titleUr}" پر دبائیں',
            textEn: 'Tap "${l.titleEn}"',
            whyUr: l.whyUr,
            whyEn: l.whyEn,
            hintUr: 'فہرست میں نام ڈھونڈیں',
            hintEn: 'Find it in the list',
          ),
          TaskStep(
            screenId: Screens.settingsLesson,
            targetId: Targets.openSettings,
            textUr: 'نیچے والا بڑا بٹن دبا کر سیٹنگ کھولیں',
            textEn: 'Tap the big button to open the settings',
            whyUr: 'یہ فون کی اصلی سیٹنگ کھولے گا۔ اوپر لکھے قدم یاد رکھیں، پھر خود بٹن آن کریں۔',
            whyEn: 'This opens the real phone settings. Remember the steps above, then switch it on yourself.',
            hintUr: 'نیچے نیلا بٹن',
            hintEn: 'The blue button at the bottom',
          ),
        ],
      );

  static TaskFlow bankPracticeFlow() => const TaskFlow(
        id: TaskIds.bankPractice,
        titleUr: 'بینک کی محفوظ مشق',
        titleEn: 'Safe banking practice',
        isPractice: true,
        steps: [
          TaskStep(
            screenId: Screens.home,
            targetId: Targets.tileBank,
            textUr: '"بینک کی مشق" والا بٹن دبائیں',
            textEn: 'Tap "Banking practice"',
            whyUr: 'یہ صرف مشق ہے۔ کوئی اصلی پیسے نہیں جائیں گے۔',
            whyEn: 'This is only practice. No real money moves.',
            hintUr: 'بینک کی عمارت والی تصویر',
            hintEn: 'The bank building picture',
          ),
          TaskStep(
            screenId: Screens.bankPractice,
            targetId: Targets.bankReview,
            textUr: 'پہلے نام اور رقم غور سے دیکھیں، پھر "چیک کر لیا" دبائیں',
            textEn: 'First check the name and amount, then tap "I checked"',
            whyUr: 'پیسے بھیجنے سے پہلے ہمیشہ نام اور رقم دو بار پڑھیں۔ غلط نام پر گئے پیسے واپس نہیں آتے۔',
            whyEn: 'Always read the name and amount twice. Money sent to the wrong person rarely comes back.',
            hintUr: 'نیچے والا بٹن',
            hintEn: 'The button at the bottom',
          ),
          TaskStep(
            screenId: Screens.bankOtp,
            targetId: Targets.refuseOtp,
            textUr: 'کوئی کوڈ مانگ رہا ہے۔ صحیح جواب چنیں',
            textEn: 'Someone asks for your code. Choose the right answer',
            whyUr: 'بینک کبھی فون کر کے کوڈ نہیں مانگتا۔ کوڈ مانگنے والا دھوکے باز ہے۔ فون بند کر دیں۔',
            whyEn: 'Banks never phone you for a code. Whoever asks is a scammer. Hang up.',
            hintUr: 'ہرا بٹن',
            hintEn: 'The green button',
          ),
        ],
      );

  static TaskFlow callFlow(Contact c) => TaskFlow(
        id: TaskIds.call,
        titleUr: 'فون کرنا',
        titleEn: 'Make a call',
        finalAction: LaunchAction(LaunchKind.dial, phone: c.phone),
        steps: [
          const TaskStep(
            screenId: Screens.home,
            targetId: Targets.tileCall,
            textUr: 'فون کرنے کے لیے یہ ہرا بٹن دبائیں',
            textEn: 'Tap the green Call button',
            whyUr: 'یہ "کال" کا بٹن ہے۔ اس پر فون کی تصویر بنی ہے۔ اسے دبانے سے آپ کے لوگوں کی فہرست کھلے گی۔',
            whyEn: 'This is the Call button. It has a phone picture. It opens your list of people.',
            hintUr: 'فون والی تصویر ڈھونڈیں',
            hintEn: 'Look for the phone picture',
          ),
          TaskStep(
            screenId: Screens.contacts,
            targetId: Targets.contact(c.id),
            textUr: '${c.nameUr} کے نام پر دبائیں',
            textEn: 'Tap ${c.nameEn}',
            whyUr: 'یہ آپ کے لوگوں کی فہرست ہے۔ جس سے بات کرنی ہو، اس کے نام پر دبائیں۔',
            whyEn: 'This is your list of people. Tap the person you want to talk to.',
            hintUr: 'نام والی فہرست میں دیکھیں',
            hintEn: 'Look in the list of names',
          ),
          TaskStep(
            screenId: Screens.confirmCall,
            targetId: Targets.callGreen,
            textUr: 'ہرا بٹن دبا کر کال ملائیں',
            textEn: 'Tap the green button to call',
            whyUr: 'ہرا بٹن ہمیشہ کال ملاتا ہے۔ لال بٹن کال بند کرتا ہے۔ گھبرائیں نہیں، کچھ خراب نہیں ہوگا۔',
            whyEn: 'Green always starts a call. Red always ends it. Nothing will break.',
            hintUr: 'ہرا رنگ = کال ملانا',
            hintEn: 'Green means call',
          ),
        ],
      );

  static TaskFlow whatsappVideoFlow(Contact c) => TaskFlow(
        id: TaskIds.whatsappVideo,
        titleUr: 'واٹس ایپ ویڈیو کال',
        titleEn: 'WhatsApp video call',
        isPractice: true,
        finalAction: LaunchAction(LaunchKind.whatsappChat, phone: c.phone),
        steps: [
          const TaskStep(
            screenId: Screens.home,
            targetId: Targets.tileWhatsapp,
            textUr: 'واٹس ایپ کا بٹن دبائیں',
            textEn: 'Tap the WhatsApp button',
            whyUr: 'یہ واٹس ایپ ہے۔ اس سے آپ بچوں کو دیکھ کر بات کر سکتی ہیں۔',
            whyEn: 'This is WhatsApp. You can see your family while you talk.',
            hintUr: 'ہری بات والی تصویر ڈھونڈیں',
            hintEn: 'Look for the green speech bubble',
          ),
          TaskStep(
            screenId: Screens.waContacts,
            targetId: Targets.contact(c.id),
            textUr: '${c.nameUr} کے نام پر دبائیں',
            textEn: 'Tap ${c.nameEn}',
            whyUr: 'جس سے بات کرنی ہو اس کا نام دبائیں۔ اس سے ان کی بات چیت کھلے گی۔',
            whyEn: 'Tap the person to open your chat with them.',
            hintUr: 'نام والی فہرست میں دیکھیں',
            hintEn: 'Look in the list of names',
          ),
          const TaskStep(
            screenId: Screens.waChatPractice,
            targetId: Targets.waVideo,
            textUr: 'اوپر کیمرے والا نشان دبائیں',
            textEn: 'Tap the camera icon at the top',
            whyUr: 'کیمرے کا نشان ویڈیو کال ہے، فون کا نشان صرف آواز والی کال۔ یہ مشق ہے، اصلی کال نہیں ہوگی۔',
            whyEn: 'The camera icon is a video call; the phone icon is voice only. This is practice — no real call.',
            hintUr: 'اوپر دائیں طرف دیکھیں',
            hintEn: 'Look at the top right',
          ),
        ],
      );

  static TaskFlow scamCheckFlow() => const TaskFlow(
        id: TaskIds.scamCheck,
        titleUr: 'پیغام چیک کرنا',
        titleEn: 'Check a message',
        steps: [
          TaskStep(
            screenId: Screens.home,
            targetId: Targets.tileCheckMessage,
            textUr: '"پیغام چیک کریں" والا بٹن دبائیں',
            textEn: 'Tap "Check a message"',
            whyUr: 'کوئی پیغام عجیب لگے تو یہاں چیک کریں، پھر جواب دیں۔',
            whyEn: 'If a message looks strange, check it here before replying.',
            hintUr: 'ڈھال والی تصویر ڈھونڈیں',
            hintEn: 'Look for the shield picture',
          ),
          TaskStep(
            screenId: Screens.scamCheck,
            targetId: Targets.pasteButton,
            textUr: '"پیسٹ" دبا کر پیغام یہاں لائیں',
            textEn: 'Tap Paste to bring the message here',
            whyUr: 'پیسٹ کا مطلب ہے کاپی کیا ہوا پیغام یہاں رکھنا۔',
            whyEn: 'Paste puts the message you copied into this box.',
            hintUr: 'ڈبے کے نیچے بٹن دیکھیں',
            hintEn: 'Look under the box',
          ),
          TaskStep(
            screenId: Screens.scamCheck,
            targetId: Targets.checkButton,
            textUr: 'اب "چیک کریں" دبائیں',
            textEn: 'Now tap Check',
            whyUr: 'ہم آپ کو بتائیں گے یہ پیغام محفوظ ہے یا دھوکہ، اور کیوں۔',
            whyEn: 'We will tell you whether it looks safe or like a scam, and why.',
            hintUr: 'بڑا نیلا بٹن',
            hintEn: 'The big blue button',
          ),
        ],
      );
}
