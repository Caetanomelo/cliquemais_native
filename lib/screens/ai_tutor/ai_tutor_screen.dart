import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/ai_tutor_service.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'ai_tutor_call_screen.dart';

/// IA Tutor — Claude-backed chat (via the shared Netlify `ai-chat` function)
/// with 2 modes (chat/pronunciation), matching the web app's merged `AiTutor`
/// module. Pronúncia mode also offers a live voice call with the AI. No API
/// key required from the user.
class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({super.key});

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen> {
  late final AppStateProvider _app;
  AiTutorMode _mode = AiTutorMode.chat;
  final Map<AiTutorMode, List<AiChatMessage>> _historyByMode = {
    for (final m in AiTutorMode.values) m: <AiChatMessage>[],
  };
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
  }

  List<AiChatMessage> get _history => _historyByMode[_mode]!;

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    setState(() {
      _history.add(AiChatMessage(role: 'user', content: trimmed));
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();
    try {
      final priorHistory = _history.sublist(0, _history.length - 1);
      final reply = await _app.aiTutor.send(
        systemPrompt: _app.aiContent.systemPromptFor(_mode),
        history: priorHistory,
        userMessage: trimmed,
      );
      if (!mounted) return;
      setState(() => _history.add(AiChatMessage(role: 'assistant', content: reply)));
      await _app.addXp(8);
    } catch (_) {
      if (mounted) {
        setState(() => _history.add(const AiChatMessage(
              role: 'assistant',
              content: 'Ops, não consegui responder agora. Verifique sua conexão e tente novamente.',
            )));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _switchMode(AiTutorMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateProvider>();
    final suggestions = app.aiContent.quickSuggestionsFor(_mode);
    final welcome = app.aiContent.welcomeMessageFor(_mode);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IA Tutor'),
      ),
      body: Column(
        children: [
          _ModeTabs(mode: _mode, onChanged: _switchMode),
          if (_mode == AiTutorMode.pronunciation)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiTutorCallScreen()),
                  ),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Chamada de Voz com o Tutor IA', style: TextStyle(fontFamily: 'Sora', fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBright,
                    side: const BorderSide(color: AppTheme.accentBright),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (welcome.isNotEmpty) _AiBubble(text: welcome, isUser: false),
                for (final m in _history) _AiBubble(text: m.content, isUser: m.role == 'user'),
                if (_sending) const Padding(padding: EdgeInsets.only(top: 8), child: _TypingIndicator()),
              ],
            ),
          ),
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(suggestions[i], style: const TextStyle(fontFamily: 'Sora', fontSize: 12)),
                  backgroundColor: AppTheme.surfaceDark,
                  side: const BorderSide(color: AppTheme.borderDark),
                  onPressed: !_sending ? () => _send(suggestions[i]) : null,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Escreva sua mensagem...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: !_sending ? () => _send(_controller.text) : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  final AiTutorMode mode;
  final void Function(AiTutorMode) onChanged;
  const _ModeTabs({required this.mode, required this.onChanged});

  static const _labels = {
    AiTutorMode.chat: ('Conversa', Icons.chat_bubble_outline_rounded),
    AiTutorMode.pronunciation: ('Pronúncia', Icons.record_voice_over_rounded),
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: AiTutorMode.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final m = AiTutorMode.values[i];
          final (label, icon) = _labels[m]!;
          final selected = m == mode;
          return ChoiceChip(
            selected: selected,
            label: Text(label, style: const TextStyle(fontFamily: 'Sora', fontSize: 12)),
            avatar: Icon(icon, size: 16),
            selectedColor: AppTheme.accent.withValues(alpha: 0.3),
            backgroundColor: AppTheme.surfaceDark,
            side: BorderSide(color: selected ? AppTheme.accentBright : AppTheme.borderDark),
            onSelected: (_) => onChanged(m),
          );
        },
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _AiBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.accent.withValues(alpha: 0.28) : AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isUser ? AppTheme.accentBright.withValues(alpha: 0.5) : AppTheme.borderDark),
              ),
              child: Text(
                text,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppTheme.textMainDark, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderDark),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentBright),
        ),
      ),
    );
  }
}
