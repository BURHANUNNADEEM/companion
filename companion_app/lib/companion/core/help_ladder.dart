import 'dart:convert';

import 'config.dart';
import 'models.dart';
import 'storage.dart';

/// Per-task learning record, saved on the phone.
class SkillProgress {
  final String taskId;
  int attempts = 0; // tasks started
  int completions = 0; // tasks finished (any help)
  int cleanCompletions = 0; // finished with no struggle during the run
  int independent = 0; // finished clean while help level was `none`
  DateTime? lastDone;
  bool mastered = false;

  /// stepIndex -> number of struggle episodes on that step (for caregiver:
  /// "still pauses on step X").
  final Map<int, int> struggleByStep = {};

  SkillProgress(this.taskId);

  Map<String, Object?> toJson() => {
        'taskId': taskId,
        'attempts': attempts,
        'completions': completions,
        'clean': cleanCompletions,
        'independent': independent,
        'lastDone': lastDone?.toIso8601String(),
        'mastered': mastered,
        'struggleByStep': struggleByStep.map((k, v) => MapEntry('$k', v)),
      };

  factory SkillProgress.fromJson(Map<String, dynamic> j) {
    final p = SkillProgress(j['taskId'] as String)
      ..attempts = j['attempts'] as int? ?? 0
      ..completions = j['completions'] as int? ?? 0
      ..cleanCompletions = j['clean'] as int? ?? 0
      ..independent = j['independent'] as int? ?? 0
      ..lastDone = j['lastDone'] == null ? null : DateTime.parse(j['lastDone'] as String)
      ..mastered = j['mastered'] as bool? ?? false;
    (j['struggleByStep'] as Map? ?? {}).forEach((k, v) {
      p.struggleByStep[int.parse(k as String)] = v as int;
    });
    return p;
  }
}

/// The "help that fades" ladder.
///
/// | clean completions | starting help      |
/// |-------------------|--------------------|
/// | 0                 | full (dim+pulse+voice) |
/// | 1–2               | highlight only     |
/// | 3+                | none (nudge only if struggle) |
///
/// Inside a run, every struggle trigger raises help by one level
/// (none → nudge → highlight → full). Help never acts for the user.
class HelpLadder {
  static const _key = '${storePrefix}progress';
  final CompanionConfig cfg;
  final KeyValueStore store;
  final Clock clock;
  final Map<String, SkillProgress> _p = {};

  HelpLadder(this.cfg, this.store, {this.clock = systemClock}) {
    final raw = store.getString(_key);
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          _p[k] = SkillProgress.fromJson(v as Map<String, dynamic>);
        });
      } catch (_) {}
    }
  }

  SkillProgress progress(String taskId) => _p.putIfAbsent(taskId, () => SkillProgress(taskId));
  Map<String, SkillProgress> get all => Map.unmodifiable(_p);

  HelpLevel startingLevel(String taskId) {
    final c = progress(taskId).cleanCompletions;
    if (c >= cfg.successesForNone) return HelpLevel.none;
    if (c >= cfg.successesForHighlight) return HelpLevel.highlight;
    return HelpLevel.full;
  }

  SkillStage stage(String taskId) {
    final p = progress(taskId);
    if (p.completions == 0) return SkillStage.newSkill;
    if (p.cleanCompletions >= cfg.successesForMastery) return SkillStage.confident;
    if (p.cleanCompletions >= 1) return SkillStage.gettingThere;
    return SkillStage.learning;
  }

  void recordStart(String taskId) {
    progress(taskId).attempts++;
    _save();
  }

  void recordStruggle(String taskId, int stepIndex) {
    final m = progress(taskId).struggleByStep;
    m[stepIndex] = (m[stepIndex] ?? 0) + 1;
    _save();
  }

  /// [clean] = no struggle trigger during this run.
  /// [startedAt] = help level the run started with.
  Celebration recordCompletion(String taskId, String titleUr, String titleEn,
      {required bool clean, required HelpLevel startedAt}) {
    final p = progress(taskId);
    final wasMastered = p.mastered;
    p.completions++;
    p.lastDone = clock();
    if (clean) p.cleanCompletions++;
    if (clean && startedAt == HelpLevel.none) p.independent++;
    if (p.cleanCompletions >= cfg.successesForMastery) p.mastered = true;
    _save();

    final justMastered = p.mastered && !wasMastered;
    final st = stage(taskId);
    String ur, en;
    if (justMastered) {
      ur = 'شاباش! اب آپ $titleUr خود کر لیتی ہیں۔ ${st.emoji}';
      en = 'Well done! You can now do "$titleEn" on your own. ${st.emoji}';
    } else if (p.independent > 0 && clean && startedAt == HelpLevel.none) {
      ur = 'آپ نے $titleUr ${p.independent} بار بغیر مدد کے کیا! ${st.emoji}';
      en = 'You did "$titleEn" without help ${p.independent} time(s)! ${st.emoji}';
    } else if (clean) {
      ur = 'بہت اچھے! اگلی بار ہم کم مدد کریں گے۔ ${st.emoji}';
      en = 'Great! Next time we will help a little less. ${st.emoji}';
    } else {
      ur = 'ہو گیا! ہر بار آسان ہو جائے گا۔ ${st.emoji}';
      en = 'Done! It gets easier every time. ${st.emoji}';
    }
    return Celebration(
      taskId: taskId,
      stage: st,
      justMastered: justMastered,
      independentCount: p.independent,
      messageUr: ur,
      messageEn: en,
    );
  }

  Future<void> reset() async {
    _p.clear();
    await store.remove(_key);
  }

  /// For demos: pretend the task was done well [n] times.
  void seed(String taskId, {required int clean, int independent = 0}) {
    final p = progress(taskId)
      ..attempts = clean
      ..completions = clean
      ..cleanCompletions = clean
      ..independent = independent
      ..lastDone = clock();
    p.mastered = clean >= cfg.successesForMastery;
    _save();
  }

  void _save() {
    store.setString(_key, jsonEncode(_p.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
