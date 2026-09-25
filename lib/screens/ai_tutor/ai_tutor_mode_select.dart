import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'ai_tutor_call_screen.dart';
import 'ai_tutor_screen.dart';

/// Bottom sheet asking the student to pick text chat or voice chat before
/// entering the Tutor — every entry point that used to push [AiTutorScreen]
/// directly (bottom nav, content list, settings) now opens this first.
/// Voice pushes [AiTutorCallScreen] right away (mirrors web's floating call
/// button) instead of routing through the text screen first.
Future<void> showAiTutorModeSelect(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final nav = Navigator.of(context);
  final mode = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.navy,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiTutorModeSelectTitle,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _ModeOption(
              emoji: '💬',
              label: l10n.aiTutorModeText,
              sub: l10n.aiTutorModeTextSub,
              onTap: () => Navigator.of(sheetContext).pop('text'),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              emoji: '🎙️',
              label: l10n.aiTutorModeVoice,
              sub: l10n.aiTutorModeVoiceSub,
              onTap: () => Navigator.of(sheetContext).pop('voice'),
            ),
          ],
        ),
      ),
    ),
  );
  if (mode == null || !context.mounted) return;
  if (mode == 'voice') {
    nav.push(MaterialPageRoute(builder: (_) => const AiTutorCallScreen()));
  } else {
    nav.push(MaterialPageRoute(builder: (_) => const AiTutorScreen()));
  }
}

class _ModeOption extends StatelessWidget {
  final String emoji;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _ModeOption({required this.emoji, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.glassCard(radius: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppTheme.accent, AppTheme.gold]),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(color: AppTheme.textSubDark, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
