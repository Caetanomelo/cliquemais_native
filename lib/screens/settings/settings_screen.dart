import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Conta',
              style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.badge_rounded,
            title: 'Meus dados',
            subtitle: 'Nome, e-mail, celular, CPF, endereço e foto',
            onTap: () => showProfileCompletionDialog(context, cancelLabel: 'Fechar'),
          ),
          const SizedBox(height: 22),
          const Text('Recursos',
              style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.menu_book_rounded,
            title: 'Sessão de Estudo',
            subtitle: 'Continua de onde você parou no currículo',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudySessionScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.smart_toy_rounded,
            title: 'IA Tutor',
            subtitle: 'Converse, tire dúvidas de gramática e vocabulário',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiTutorScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ResourceRow(
            icon: Icons.business_center_rounded,
            title: 'Portal Corporativo',
            subtitle: '18 trilhas de inglês para o ambiente de trabalho',
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
