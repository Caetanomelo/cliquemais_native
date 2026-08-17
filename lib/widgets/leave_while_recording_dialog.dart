import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shared "gravação em andamento" confirmation shown by [VpcScreen] and
/// [DriveModeScreen] when the user tries to switch bottom-nav tabs while
/// mid-recording — leaving without confirming would silently discard
/// whatever's already been spoken. Returns true if the caller should
/// proceed with leaving (and has already cancelled the recording).
Future<bool> confirmLeaveWhileRecording(
  BuildContext context, {
  required bool listening,
  required Future<void> Function() onDiscard,
}) async {
  if (!listening) return true;
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: const Text('Gravação em andamento', style: TextStyle(fontFamily: 'Sora', color: AppTheme.textMainDark)),
      content: const Text('Sair agora descarta a gravação atual. Deseja continuar?',
          style: TextStyle(fontFamily: 'Sora', color: AppTheme.textSubDark)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Descartar', style: TextStyle(color: AppTheme.red))),
      ],
    ),
  );
  if (discard == true) {
    await onDiscard();
    return true;
  }
  return false;
}
