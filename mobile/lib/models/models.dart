import 'package:flutter/material.dart';

/// Home tile definitions (mirror backend app/services/tasks.py). Available offline.
class TaskDef {
  const TaskDef(this.id, this.en, this.ur, this.icon, this.color, this.workflowId, this.intent,
      {this.param, this.inAppRoute});
  final String id;
  final String en;
  final String ur;
  final IconData icon;
  final Color color;
  final String workflowId;
  /// Tier 1 intent opened directly by the tile (1 tap, F1/F10).
  final String? intent;
  final String? param;
  final String? inAppRoute;

  String label(String lang) => lang == 'ur' ? ur : en;
}

const kHomeTiles = <TaskDef>[
  TaskDef('call', 'Call', 'کال کریں', Icons.call, Color(0xFF1B7F3B), 'call_contact', 'dial', param: 'contact'),
  TaskDef('messages', 'Messages', 'پیغامات', Icons.sms, Color(0xFF1565C0), 'open_messages', 'sms'),
  TaskDef('photos', 'Photos', 'تصویریں', Icons.photo_library, Color(0xFF6A1B9A), 'open_photos', 'gallery'),
  TaskDef('whatsapp', 'WhatsApp video call', 'واٹس ایپ ویڈیو کال', Icons.videocam, Color(0xFF00796B),
      'whatsapp_video_call', 'whatsapp_chat', param: 'contact'),
  TaskDef('scam_check', 'Check a message', 'پیغام چیک کریں', Icons.shield, Color(0xFFB71C1C), 'scam_check', null,
      inAppRoute: 'scam_check'),
  TaskDef('ask_family', 'Ask my family', 'گھر والوں سے مدد', Icons.family_restroom, Color(0xFFE65100), 'ask_family',
      'dial', param: 'helper'),
];

TaskDef? tileById(String id) {
  for (final t in kHomeTiles) {
    if (t.id == id) return t;
  }
  return null;
}

class Suggestion {
  Suggestion({required this.task, required this.workflowId, required this.label});
  final String task;
  final String workflowId;
  final Map<String, dynamic> label;

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
        task: j['task'] as String,
        workflowId: j['workflow_id'] as String,
        label: Map<String, dynamic>.from(j['label'] as Map),
      );
}

class Highlight {
  const Highlight(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        (j['x'] as num).toDouble().clamp(0.0, 1.0),
        (j['y'] as num).toDouble().clamp(0.0, 1.0),
        (j['w'] as num).toDouble().clamp(0.0, 1.0),
        (j['h'] as num).toDouble().clamp(0.0, 1.0),
      );
}

/// Client-side allow-lists (defence in depth: the app ignores anything else the server sends).
const kAllowedActionKinds = {'open_intent', 'external_hint', 'in_app_route', 'in_app_hint'};
const kAllowedIntents = {
  'dial', 'sms', 'gallery', 'camera', 'whatsapp_chat', 'whatsapp_open', 'settings_wifi',
  'settings_bluetooth', 'settings_sound', 'settings_display', 'maps_search',
};
const kAllowedRoutes = {'home', 'scam_check', 'family'};
const kAllowedArrows = {'up', 'down', 'left', 'right'};

class NavStep {
  NavStep({
    required this.index,
    required this.id,
    required this.screen,
    required this.targetId,
    required this.targetLabel,
    required this.highlight,
    required this.arrow,
    required this.hint,
    required this.actionKind,
    this.intent,
    this.route,
    this.params = const {},
    required this.completion,
  });

  final int index;
  final String id;
  final String screen;
  final String targetId;
  final Map<String, dynamic> targetLabel;
  final Highlight highlight;
  final String arrow;
  final Map<String, dynamic> hint;
  final String actionKind;
  final String? intent;
  final String? route;
  final Map<String, dynamic> params;
  final String completion;

  bool get isExternal => actionKind == 'external_hint';

  static NavStep? tryParse(Map<String, dynamic> j) {
    final action = Map<String, dynamic>.from(j['action'] as Map? ?? {});
    final kind = action['kind'] as String? ?? '';
    if (!kAllowedActionKinds.contains(kind)) return null;
    final intent = action['intent'] as String?;
    if (kind == 'open_intent' && !kAllowedIntents.contains(intent)) return null;
    final route = action['route'] as String?;
    if (kind == 'in_app_route' && !kAllowedRoutes.contains(route)) return null;
    final arrow = j['arrow'] as String? ?? 'down';
    final target = Map<String, dynamic>.from(j['target'] as Map? ?? {});
    return NavStep(
      index: (j['index'] as num?)?.toInt() ?? 0,
      id: j['id'] as String? ?? '',
      screen: j['screen'] as String? ?? '',
      targetId: target['id'] as String? ?? '',
      targetLabel: Map<String, dynamic>.from(target['label'] as Map? ?? {}),
      highlight: Highlight.fromJson(Map<String, dynamic>.from(j['highlight'] as Map)),
      arrow: kAllowedArrows.contains(arrow) ? arrow : 'down',
      hint: Map<String, dynamic>.from(j['hint'] as Map? ?? {}),
      actionKind: kind,
      intent: intent,
      route: route,
      params: Map<String, dynamic>.from(action['params'] as Map? ?? {}),
      completion: (j['completion'] as Map?)?['type'] as String? ?? 'user_confirm',
    );
  }
}

class NavPlan {
  NavPlan({
    required this.status,
    this.workflowId,
    this.task,
    this.title = const {},
    this.intro = const {},
    this.message = const {},
    this.steps = const [],
    this.slots = const {},
    this.tier2Skill,
    this.done = const {},
    this.maxSteps = 10,
    this.timeoutSeconds = 30,
  });

  final String status; // ok | refused
  final String? workflowId;
  final String? task;
  final Map<String, dynamic> title;
  final Map<String, dynamic> intro;
  final Map<String, dynamic> message;
  final List<NavStep> steps;
  final Map<String, dynamic> slots;
  final String? tier2Skill;
  final Map<String, dynamic> done;
  final int maxSteps;
  final int timeoutSeconds;

  bool get ok => status == 'ok' && steps.isNotEmpty;

  /// Parses and validates a server plan. Any step with an unknown action makes the whole plan refused.
  factory NavPlan.fromJson(Map<String, dynamic> j) {
    final limits = Map<String, dynamic>.from(j['limits'] as Map? ?? {});
    final maxSteps = (limits['max_steps'] as num?)?.toInt() ?? 10;
    final rawSteps = (j['steps'] as List? ?? []).cast<Map>();
    final steps = <NavStep>[];
    var invalid = false;
    for (final s in rawSteps) {
      final step = NavStep.tryParse(Map<String, dynamic>.from(s));
      if (step == null) {
        invalid = true;
        break;
      }
      steps.add(step);
    }
    if (steps.length > 10 || steps.length > maxSteps) invalid = true;
    final status = (j['status'] == 'ok' && !invalid) ? 'ok' : 'refused';
    return NavPlan(
      status: status,
      workflowId: j['workflow_id'] as String?,
      task: j['task'] as String?,
      title: Map<String, dynamic>.from(j['title'] as Map? ?? {}),
      intro: Map<String, dynamic>.from(j['intro'] as Map? ?? {}),
      message: Map<String, dynamic>.from(j['message'] as Map? ?? {}),
      steps: status == 'ok' ? steps : const [],
      slots: Map<String, dynamic>.from(j['slots'] as Map? ?? {}),
      tier2Skill: j['tier2_skill'] as String?,
      done: Map<String, dynamic>.from(j['done'] as Map? ?? {}),
      maxSteps: maxSteps,
      timeoutSeconds: (limits['timeout_seconds'] as num?)?.toInt() ?? 30,
    );
  }
}

class ScamResult {
  ScamResult(this.id, this.verdict, this.reasons, this.explanation);
  final String id;
  final String verdict;
  final List<String> reasons;
  final Map<String, dynamic> explanation;

  factory ScamResult.fromJson(Map<String, dynamic> j) => ScamResult(
        j['id'] as String,
        j['verdict'] as String,
        (j['reasons'] as List? ?? []).cast<String>(),
        Map<String, dynamic>.from(j['explanation'] as Map),
      );
}
