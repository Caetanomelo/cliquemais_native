import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/corp_track.dart';
import '../../data/models/course_language.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../lesson/views/convo_lesson_view.dart';

class CorpTrackDetailScreen extends StatelessWidget {
  final CorpTrack track;
  const CorpTrackDetailScreen({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppStateProvider>();
    final track = this.track.forLanguage(app.courseLanguage);
    void speak(String text) => app.cloudTts.speak(text, rate: 0.5, voiceGender: app.voiceGender, language: resolveLocale(app.courseLanguage));

    return Scaffold(
      appBar: AppBar(title: Text(track.name, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(track.role, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
          const SizedBox(height: 16),
          if (track.audio.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('"${track.audio}"',
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontStyle: FontStyle.italic, color: AppTheme.textMainDark)),
                  ),
                  IconButton(
                    onPressed: () => speak(track.audio),
                    icon: const Icon(Icons.volume_up_rounded, color: AppTheme.accentBright),
                    tooltip: 'Ouvir áudio',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (track.feedback.isNotEmpty) ...[
            const Text('Análise da estrutura', style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
            const SizedBox(height: 6),
            Text(track.feedback, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textMainDark, height: 1.4)),
            const SizedBox(height: 16),
          ],
          if (track.terms.isNotEmpty) ...[
            const Text('Termos-chave', style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in track.terms)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Text(term, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textMainDark)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (track.vocab.isNotEmpty) ...[
            const Text('Vocabulário', style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
            const SizedBox(height: 8),
            for (final v in track.vocab)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.en, style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                          Text(v.pt, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => speak(v.en),
                      icon: const Icon(Icons.volume_up_rounded, size: 20, color: AppTheme.accentBright),
                      tooltip: 'Ouvir pronúncia',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (track.dialogues.isNotEmpty) ...[
            const Text('Diálogos', style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
            const SizedBox(height: 8),
            ConvoLessonView(dialogues: track.dialogues, onSpeak: speak, shrinkWrap: true),
          ],
        ],
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}
