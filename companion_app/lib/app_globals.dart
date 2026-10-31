import 'package:flutter/widgets.dart';

import 'companion/companion.dart';
import 'services/backend_sync.dart';

/// Created once in main() before runApp.
late final CompanionController companion;
late final BackendSync backend;

/// Pops everything and returns to the home screen WITHOUT counting back presses
/// (so finishing a task is never mistaken for "struggling").
void goHome(BuildContext context) {
  Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
}

/// Every guided button calls this: tells the engine, and when a task finishes,
/// reports the outcome to the backend (best effort).
Future<TapOutcome> tapTarget(String targetId) async {
  final taskBefore = companion.engine.activeTaskId ?? companion.engine.catalog.taskForHomeTile(targetId);
  final cleanBefore =
      taskBefore == null ? 0 : companion.engine.ladder.progress(taskBefore).cleanCompletions;
  final outcome = await companion.tap(targetId);
  if (outcome.taskCompleted && taskBefore != null) {
    final cleanAfter = companion.engine.ladder.progress(taskBefore).cleanCompletions;
    backend.reportTaskCompleted(taskBefore, clean: cleanAfter > cleanBefore);
    backend.flushEvents();
  }
  return outcome;
}
