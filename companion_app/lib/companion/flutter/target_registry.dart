import 'package:flutter/widgets.dart';

/// Lets the overlay find WHERE a target widget is on screen.
///
/// Wrap any tappable widget the engine may point at:
///   CompanionTarget(id: Targets.tileCall, child: MyBigTile(...))
/// Then the overlay calls TargetRegistry.instance.rectOf(state.targetId).
class TargetRegistry {
  TargetRegistry._();
  static final instance = TargetRegistry._();
  final Map<String, GlobalKey> _keys = {};

  GlobalKey keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  /// Global rectangle of the target, or null if it is not on screen.
  Rect? rectOf(String? id) {
    if (id == null) return null;
    final ctx = _keys[id]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class CompanionTarget extends StatelessWidget {
  final String id;
  final Widget child;
  const CompanionTarget({super.key, required this.id, required this.child});

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: TargetRegistry.instance.keyFor(id), child: child);
}
