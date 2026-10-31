import 'event_log.dart';
import 'help_ladder.dart';
import 'models.dart';
import 'task_flows.dart';

class SkillLine {
  final String taskId;
  final String titleUr;
  final String titleEn;
  final SkillStage stage;
  final int completions;
  final int independent;

  /// The step she pauses on most (null if none). Tells the family what to teach.
  final String? stuckStepEn;
  final String? stuckStepUr;
  const SkillLine(this.taskId, this.titleUr, this.titleEn, this.stage, this.completions,
      this.independent, this.stuckStepEn, this.stuckStepUr);
}

/// What a caregiver may see (PRD F9, reframed: "what to teach next").
/// Never contains message text, contact names or screen content.
/// Empty unless the parent turned on caregiver sharing.
class CaregiverSummary {
  final bool sharingAllowed;
  final DateTime? lastActive;
  final List<SkillLine> skills;
  final int struggleEpisodesToday;
  final int scamChecks;
  final int likelyScams;
  final List<String> teachNextEn;
  final List<String> teachNextUr;

  const CaregiverSummary({
    required this.sharingAllowed,
    this.lastActive,
    this.skills = const [],
    this.struggleEpisodesToday = 0,
    this.scamChecks = 0,
    this.likelyScams = 0,
    this.teachNextEn = const [],
    this.teachNextUr = const [],
  });

  static CaregiverSummary build({
    required EventLog log,
    required HelpLadder ladder,
    required TaskCatalog catalog,
    required DateTime now,
  }) {
    if (!log.consent.caregiverSharing) return const CaregiverSummary(sharingAllowed: false);
    final ev = log.events;
    final today = DateTime(now.year, now.month, now.day);
    final skills = <SkillLine>[];
    final teachEn = <String>[];
    final teachUr = <String>[];

    for (final flow in catalog.flows.values) {
      final p = ladder.progress(flow.id);
      final stage = ladder.stage(flow.id);
      String? stuckEn, stuckUr;
      if (p.struggleByStep.isNotEmpty) {
        final worst = p.struggleByStep.entries.reduce((a, b) => a.value >= b.value ? a : b);
        if (worst.key < flow.steps.length) {
          stuckEn = flow.steps[worst.key].textEn;
          stuckUr = flow.steps[worst.key].textUr;
        }
      }
      skills.add(SkillLine(flow.id, flow.titleUr, flow.titleEn, stage, p.completions,
          p.independent, stuckEn, stuckUr));
      if (stage != SkillStage.confident) {
        if (stuckEn != null) {
          teachEn.add('${flow.titleEn}: she still pauses at "$stuckEn".');
          teachUr.add('${flow.titleUr}: اس قدم پر رکتی ہیں — "$stuckUr"');
        } else if (stage == SkillStage.newSkill) {
          teachEn.add('${flow.titleEn}: not tried yet — try it together.');
          teachUr.add('${flow.titleUr}: ابھی نہیں کیا — ساتھ مل کر کریں۔');
        }
      }
    }

    final scam = ev.where((e) => e.type == EventTypes.scamCheck).toList();
    return CaregiverSummary(
      sharingAllowed: true,
      lastActive: ev.isEmpty ? null : ev.last.at,
      skills: skills,
      struggleEpisodesToday:
          ev.where((e) => e.type == EventTypes.struggle && !e.at.isBefore(today)).length,
      scamChecks: scam.length,
      likelyScams: scam.where((e) => e.props['level'] == ScamLevel.likelyScam.name).length,
      teachNextEn: teachEn,
      teachNextUr: teachUr,
    );
  }
}
