// Core data types for Companion. Pure Dart: no Flutter imports.

/// How much help Companion gives on a step. Higher = more help.
enum HelpLevel {
  /// No help shown. User is on their own (struggle can still raise it).
  none,

  /// Small "Need a hand?" chip. No dimming, no voice.
  nudge,

  /// Target is highlighted (soft glow), short text, no voice.
  highlight,

  /// Screen dimmed, target pulses, text + Urdu voice explains WHY.
  full,
}

extension HelpLevelX on HelpLevel {
  HelpLevel raise() =>
      HelpLevel.values[index + 1 < HelpLevel.values.length ? index + 1 : index];
  bool get dimsScreen => this == HelpLevel.full;
  bool get showsHighlight => this == HelpLevel.full || this == HelpLevel.highlight;
  bool get speaks => this == HelpLevel.full;
  bool get visible => this != HelpLevel.none;
}

/// Learning stage of a task, shown to the user and caregiver.
enum SkillStage { newSkill, learning, gettingThere, confident }

extension SkillStageX on SkillStage {
  String get emoji => const ['🌰', '🌱', '🌿', '🌳'][index];
  String get labelEn =>
      const ['Not tried yet', 'Learning', 'Getting there', 'Confident'][index];
  String get labelUr =>
      const ['ابھی شروع نہیں کیا', 'سیکھ رہی ہیں', 'تقریباً آ گیا', 'خود کر لیتی ہیں'][index];
}

/// What happens when the last step of a task is tapped.
enum LaunchKind { dial, whatsappChat, sms, settings, none }

class LaunchAction {
  final LaunchKind kind;

  /// Phone number in international format without '+', e.g. 923001234567.
  final String? phone;

  /// For [LaunchKind.settings]: wifi | hotspot | sound | display | bluetooth.
  final String? settingsType;
  const LaunchAction(this.kind, {this.phone, this.settingsType});
  static const nothing = LaunchAction(LaunchKind.none);
}

/// One step inside a guided task. [targetId] must match the id the UI
/// registers for the widget the user should tap on [screenId].
class TaskStep {
  final String screenId;
  final String targetId;
  final String textUr; // short instruction: "یہاں دبائیں"
  final String textEn;
  final String whyUr; // spoken at full help: why this button
  final String whyEn;
  final String hintUr; // nudge-level hint: "نیچے دیکھیں"
  final String hintEn;
  const TaskStep({
    required this.screenId,
    required this.targetId,
    required this.textUr,
    required this.textEn,
    required this.whyUr,
    required this.whyEn,
    required this.hintUr,
    required this.hintEn,
  });
}

class TaskFlow {
  final String id;
  final String titleUr;
  final String titleEn;
  final List<TaskStep> steps;
  final LaunchAction finalAction;

  /// True if any step is a mock/practice screen (must be said in the demo).
  final bool isPractice;
  const TaskFlow({
    required this.id,
    required this.titleUr,
    required this.titleEn,
    required this.steps,
    this.finalAction = LaunchAction.nothing,
    this.isPractice = false,
  });
}

/// Logged event. Actions only, never message text or contact names.
class AppEvent {
  final String type;
  final DateTime at;
  final String sessionId;
  final Map<String, Object?> props;
  const AppEvent(this.type, this.at, this.sessionId, [this.props = const {}]);

  Map<String, Object?> toJson() =>
      {'type': type, 'at': at.toIso8601String(), 'session': sessionId, 'props': props};

  static AppEvent fromJson(Map<String, dynamic> j) => AppEvent(
        j['type'] as String,
        DateTime.parse(j['at'] as String),
        j['session'] as String,
        Map<String, Object?>.from(j['props'] as Map? ?? const {}),
      );
}

class EventTypes {
  static const screenView = 'screen_view';
  static const tap = 'tap';
  static const wrongTap = 'wrong_tap';
  static const back = 'back';
  static const idle = 'idle';
  static const taskStarted = 'task_started';
  static const stepCompleted = 'step_completed';
  static const taskCompleted = 'task_completed';
  static const taskAbandoned = 'task_abandoned';
  static const struggle = 'struggle_detected';
  static const helpRaised = 'help_raised';
  static const suggestionShown = 'suggestion_shown';
  static const suggestionAccepted = 'suggestion_accepted';
  static const suggestionDismissed = 'suggestion_dismissed';
  static const somethingElse = 'something_else_tapped';
  static const navStarted = 'nav_started';
  static const scamCheck = 'scam_check';
  static const mastered = 'skill_mastered';
}

/// Struggle signals (PRD F2) plus "wrong tap" (tap off the guided target).
enum StruggleSignal { backtracking, idle, repeatedTaps, looping, noCompletion, wrongTaps }

class StruggleResult {
  final double score;
  final Set<StruggleSignal> signals;
  final bool triggered;
  const StruggleResult(this.score, this.signals, this.triggered);
  static const calm = StruggleResult(0, {}, false);
  @override
  String toString() => 'Struggle(score=$score, $signals, triggered=$triggered)';
}

/// What the UI should draw right now. The UI only renders this; all decisions
/// are made by the engine.
class GuidanceState {
  final String? taskId;
  final int stepIndex;
  final int totalSteps;
  final String? screenId;
  final String? targetId;
  final HelpLevel level;
  final String textUr;
  final String textEn;

  /// Text to speak now (null = say nothing). UI passes it to TtsService.
  final String? speakUr;

  /// Set when the user is lost on a screen with no active task.
  final List<String> suggestions;

  /// Set once when a task is completed: celebration / badge.
  final Celebration? celebration;

  const GuidanceState({
    this.taskId,
    this.stepIndex = 0,
    this.totalSteps = 0,
    this.screenId,
    this.targetId,
    this.level = HelpLevel.none,
    this.textUr = '',
    this.textEn = '',
    this.speakUr,
    this.suggestions = const [],
    this.celebration,
  });

  static const idle = GuidanceState();
  bool get hasSuggestions => suggestions.isNotEmpty;
  bool get showOverlay => level.visible || hasSuggestions;

  @override
  String toString() =>
      'Guidance(task=$taskId step=$stepIndex/$totalSteps target=$targetId level=$level sugg=$suggestions celebrate=${celebration?.messageEn})';
}

class Celebration {
  final String taskId;
  final SkillStage stage;
  final bool justMastered;
  final int independentCount;
  final String messageUr;
  final String messageEn;
  const Celebration({
    required this.taskId,
    required this.stage,
    required this.justMastered,
    required this.independentCount,
    required this.messageUr,
    required this.messageEn,
  });
}

enum ScamLevel { probablyFine, beCareful, likelyScam }

extension ScamLevelX on ScamLevel {
  String get labelEn => const ['Probably fine', 'Be careful', 'Likely scam'][index];
  String get labelUr => const ['شاید ٹھیک ہے', 'احتیاط کریں', 'یہ دھوکہ لگتا ہے'][index];
}

class ScamReason {
  final String ruleId;
  final String reasonUr;
  final String reasonEn;
  final int weight;
  const ScamReason(this.ruleId, this.reasonUr, this.reasonEn, this.weight);
}

class ScamVerdict {
  final ScamLevel level;
  final int score;
  final List<ScamReason> reasons;
  final String actionUr;
  final String actionEn;

  /// One reusable rule to remember (the teaching part).
  final String lessonUr;
  final String lessonEn;
  static const askFamilyUr = 'شک ہو تو اپنے گھر والوں سے پوچھ لیں۔';
  static const askFamilyEn = 'When in doubt, ask your family.';
  const ScamVerdict({
    required this.level,
    required this.score,
    required this.reasons,
    required this.actionUr,
    required this.actionEn,
    required this.lessonUr,
    required this.lessonEn,
  });

  /// Single sentence for TTS.
  String get spokenUr {
    final r = reasons.isEmpty ? '' : ' ${reasons.first.reasonUr}';
    return '${level.labelUr}.$r $actionUr $askFamilyUr';
  }
}
