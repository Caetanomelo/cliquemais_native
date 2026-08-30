import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/course_language.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/info_card_row.dart';
import '../../widgets/profile_completion_dialog.dart';
import '../ai_tutor/ai_tutor_screen.dart';
import '../content/study_session_screen.dart';
import '../corp/corp_portal_screen.dart';

/// App resources hub. TTS and the AI Tutor both run entirely through the
/// shared Netlify backend — no user-supplied API keys anywhere in the app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickCourseLanguage(BuildContext context) async {
    final appState = context.read<AppStateProvider>();
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: Text(AppLocalizations.of(context)!.settingsCourseLanguageTitle, style: const TextStyle(color: AppTheme.textMainDark)),
        children: [
          for (final entry in kLanguageLabels.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Row(
                children: [
                  Icon(
                    entry.key == appState.courseLanguage ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppTheme.accentBright,
                  ),
                  const SizedBox(width: 12),
                  Text(entry.value, style: const TextStyle(color: AppTheme.textMainDark)),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == appState.courseLanguage) return;
    if (!isValidPair(appState.nativeLanguage, chosen)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsLanguagesSameError)),
        );
      }
      return;
    }
    try {
      await appState.setCourseLanguage(chosen);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsLanguageSwitchError)),
        );
      }
    }
  }

  Future<void> _pickNativeLanguage(BuildContext context) async {
    final appState = context.read<AppStateProvider>();
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: Text(AppLocalizations.of(context)!.settingsNativeLanguageTitle, style: const TextStyle(color: AppTheme.textMainDark)),
        children: [
          for (final entry in kLanguageLabels.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Row(
                children: [
                  Icon(
                    entry.key == appState.nativeLanguage ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppTheme.accentBright,
                  ),
                  const SizedBox(width: 12),
                  Text(entry.value, style: const TextStyle(color: AppTheme.textMainDark)),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == appState.nativeLanguage) return;
    if (!isValidPair(chosen, appState.courseLanguage)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsLanguagesSameError)),
        );
      }
      return;
    }
    try {
      await appState.setNativeLanguage(chosen);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsLanguageSwitchError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.settingsSectionAccount,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.badge_rounded,
            title: l10n.settingsMyDataTitle,
            subtitle: l10n.settingsMyDataSubtitle,
            onTap: () => showProfileCompletionDialog(context, cancelLabel: l10n.settingsCloseLabel),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.language_rounded,
            title: l10n.settingsCourseLanguageTitle,
            subtitle: kLanguageLabels[appState.courseLanguage] ?? 'Inglês',
            onTap: () => _pickCourseLanguage(context),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.record_voice_over_rounded,
            title: l10n.settingsNativeLanguageTitle,
            subtitle: kLanguageLabels[appState.nativeLanguage] ?? 'Português',
            onTap: () => _pickNativeLanguage(context),
          ),
          const SizedBox(height: 22),
          Text(l10n.settingsSectionResources,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.menu_book_rounded,
            title: l10n.settingsStudySessionTitle,
            subtitle: l10n.settingsStudySessionSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudySessionScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.smart_toy_rounded,
            title: l10n.settingsAiTutorTitle,
            subtitle: l10n.settingsAiTutorSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiTutorScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.business_center_rounded,
            title: l10n.settingsCorpPortalTitle,
            subtitle: l10n.settingsCorpPortalSubtitle,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CorpPortalScreen()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ResourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InfoCardRow(
      onTap: onTap,
      materialColor: AppTheme.surfaceDark,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDark),
      ),
      gap: 12,
      leading: Icon(icon, color: AppTheme.accentBright),
      title: title,
      subtitle: subtitle,
    );
  }
}
