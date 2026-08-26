import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

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
  final l10n = AppLocalizations.of(context)!;
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: Text(l10n.leaveWhileRecordingTitle, style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textMainDark)),
      content: Text(l10n.leaveWhileRecordingContent,
          style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textSubDark)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.leaveWhileRecordingCancel)),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.leaveWhileRecordingDiscard, style: const TextStyle(color: AppTheme.red))),
      ],
    ),
  );
  if (discard == true) {
    await onDiscard();
    return true;
  }
  return false;
}
