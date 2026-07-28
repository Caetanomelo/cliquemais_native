import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/secure_key_service.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../ai_tutor/ai_tutor_screen.dart';
import '../content/study_session_screen.dart';
import '../corp/corp_portal_screen.dart';

/// Lets the user enter their own API keys (Anthropic for AI Tutor;
/// ElevenLabs/Google/OpenAI for cloud TTS). Keys are written straight to
/// [SecureKeyService] (platform keychain/keystore) — never logged, never
/// sent anywhere but the respective provider's official API, never
/// hardcoded in source, unlike the web app's plaintext localStorage keys.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final keys = context.read<AppStateProvider>().secureKeys;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const SizedBox(height: 22),
          const Text('Chaves de API',
              style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSubDark)),
          const SizedBox(height: 4),
          const Text(
            'Suas chaves ficam guardadas apenas neste dispositivo, no keychain/keystore seguro do sistema. Nenhuma é enviada para nós.',
            style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark),
          ),
          const SizedBox(height: 20),
          _KeyField(
            keys: keys,
            provider: ApiProvider.anthropic,
            label: 'Anthropic (Claude)',
            hint: 'Necessária para o IA Tutor',
            url: 'console.anthropic.com',
          ),
          const SizedBox(height: 16),
          _KeyField(
            keys: keys,
            provider: ApiProvider.elevenLabs,
            label: 'ElevenLabs',
            hint: 'Voz premium para Drive Mode e diálogos',
            url: 'elevenlabs.io',
          ),
          const SizedBox(height: 16),
          _KeyField(
            keys: keys,
            provider: ApiProvider.googleTts,
            label: 'Google Cloud Text-to-Speech',
            hint: 'Voz padrão em nuvem',
            url: 'console.cloud.google.com',
          ),
          const SizedBox(height: 16),
          _KeyField(
            keys: keys,
            provider: ApiProvider.openAi,
            label: 'OpenAI',
            hint: 'Voz do IA Tutor',
            url: 'platform.openai.com',
          ),
          const SizedBox(height: 8),
          const Text(
            'Sem uma chave configurada, a fala volta automaticamente para a voz do próprio aparelho.',
            style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.perfil),
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
    return Material(
      color: AppTheme.surfaceDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accentBright),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSubDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyField extends StatefulWidget {
  final SecureKeyService keys;
  final ApiProvider provider;
  final String label;
  final String hint;
  final String url;
  const _KeyField({
    required this.keys,
    required this.provider,
    required this.label,
    required this.hint,
    required this.url,
  });

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loaded = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await widget.keys.getKey(widget.provider);
    if (mounted) {
      setState(() {
        _controller.text = v ?? '';
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    await widget.keys.setKey(widget.provider, _controller.text);
    if (mounted) setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
          const SizedBox(height: 2),
          Text('${widget.hint} · ${widget.url}',
              style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textSubDark)),
          const SizedBox(height: 10),
          if (!_loaded)
            const LinearProgressIndicator()
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    obscureText: _obscure,
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textMainDark),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'sk-...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _save,
                  icon: Icon(_saved ? Icons.check_rounded : Icons.save_rounded),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
