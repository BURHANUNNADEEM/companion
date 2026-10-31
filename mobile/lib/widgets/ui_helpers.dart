import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api_client.dart';

/// Friendly, bilingual error snackbar.
void showApiError(BuildContext context, Object e) {
  final s = S.read(context);
  final msg = e is ApiException && e.isOffline ? s.t('error_offline') : s.t('error_generic');
  showMessage(context, msg);
}

void showMessage(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 20)), duration: const Duration(seconds: 4)));
}

/// Rect of a widget (by GlobalKey) in the coordinate space of [ancestor] (or global if null).
Rect? rectOf(GlobalKey key, {RenderObject? ancestor}) {
  final ctx = key.currentContext;
  final box = ctx?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: ancestor);
  return topLeft & box.size;
}
