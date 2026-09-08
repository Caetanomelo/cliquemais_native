import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/ai_tutor_service.dart';
import '../../core/services/pronunciation_assessment_service.dart';
import '../../data/models/course_language.dart';
import '../../data/repositories/ai_content_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'ai_tutor_call_screen.dart';
import 'call_turn_assessor.dart';

enum _MicState { idle, recording, processing }

/// Parses and strips the `[[PRONOUNCE:word or expression]]` marker
/// (migration 068) that the AI tutor may emit in a chat-mode reply. Returns
/// the reply with the marker removed (safe to store/render as-is) plus the
/// bare word/expression, or a null word when the reply carries no marker.
(String, String?) _extractPronounceMarker(String text) {
  final m = RegExp(r'\[\[PRONOUNCE:([^\]]{1,80})\]\]', caseSensitive: false).firstMatch(text);
  if (m == null) return (text, null);
  final word = m.group(1)!.trim();
  final clean = (text.substring(0, m.start) + text.substring(m.end))
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return (clean, word.isEmpty ? null : word);
}

/// IA Tutor — Claude-backed chat (via the shared Netlify `ai-chat` function)
/// in a single merged feed: typed messages and mic-recorded pronunciation
/// turns share one history. A mic turn is assessed via Azure Pronunciation
/// Assessment (same unscripted pass used by [AiTutorCallScreen]) and shows
/// up as a score card instead of a plain bubble. Live voice calls are still
/// reachable via the floating action button. No API key required from the
/// user.
class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({super.key});

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen>
    with WidgetsBindingObserver {
  late final AppStateProvider _app;
  final AudioRecorder _recorder = AudioRecorder();
  final List<AiChatMessage> _history = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  _MicState _micState = _MicState.idle;
  // Set by a _PronPracticeChip while it's recording -- guards against it and
  // the composer's main mic (or another chip) capturing audio at the same
  // time, mirroring the single-recording-at-a-time rule the web build uses.
  bool _pronChipActive = false;
  // Picked once per screen instance so it stays fixed for this
  // conversation's duration — a fresh AiTutorScreen is pushed every time the
  // user taps the Tutor tab (see AppBottomNav), so this naturally re-rolls
  // on each new conversation.
  late final AiPersona _persona;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
    _persona = _app.aiContent.pickPersona();
    WidgetsBinding.instance.addObserver(this);
  }

  // A hold-to-talk gesture left mid-press when the app backgrounds (e.g. a
  // notification pulls focus away) would otherwise leave the mic's
  // AudioRecord session reserved indefinitely.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (_micState == _MicState.recording) {
      unawaited(_cancelMicRecording());
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    _controller.clear();
    await _sendMessage(trimmed);
  }

  Future<void> _sendMessage(
    String text, {
    String feedback = '',
    double? pronScore,
    List<PronWord> lowScoreWords = const [],
  }) async {
    if (_sending) return;
    setState(() {
      _history.add(
        AiChatMessage(
          role: 'user',
          content: text,
          pronScore: pronScore,
          lowScoreWords: lowScoreWords,
        ),
      );
      _sending = true;
    });
    try {
      final priorHistory = _history.sublist(0, _history.length - 1);
      final outgoing = feedback.isEmpty ? text : '$text\n\n$feedback';
      final basePrompt = _app.aiContent.systemPromptForKey('chat');
      final systemPrompt = _persona.prompt.isEmpty ? basePrompt : '${_persona.prompt}\n\n$basePrompt';
      final reply = await _app.aiTutor.send(
        systemPrompt: systemPrompt,
        history: priorHistory,
        userMessage: outgoing,
      );
      if (!mounted) return;
      final (cleanReply, pronounceWord) = _extractPronounceMarker(reply);
      setState(
        () => _history.add(
          AiChatMessage(
            role: 'assistant',
            content: cleanReply,
            pronounceWord: pronounceWord,
          ),
        ),
      );
      await _app.addXp(8);
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'AiTutorScreen._sendMessage failed',
          fatal: false,
        ),
      );
      if (mounted) {
        setState(
          () => _history.add(
            AiChatMessage(
              role: 'assistant',
              content: AppLocalizations.of(context)!.aiTutorErrorReply,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startMicRecording() async {
    if (_micState != _MicState.idle || _sending || _pronChipActive) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final path =
        '${Directory.systemTemp.path}/tutor_mic_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    if (!mounted) return;
    setState(() => _micState = _MicState.recording);
  }

  Future<void> _cancelMicRecording() async {
    if (_micState != _MicState.recording) return;
    try {
      final path = await _recorder.stop();
      if (path != null) await _safeDeleteAudio(path);
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'AiTutorScreen._cancelMicRecording failed',
          fatal: false,
        ),
      );
    }
    if (mounted) setState(() => _micState = _MicState.idle);
  }

  Future<void> _stopMicRecordingAndAssess() async {
    if (_micState != _MicState.recording) return;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason:
              'AiTutorScreen._stopMicRecordingAndAssess: recorder.stop failed',
          fatal: false,
        ),
      );
    }
    setState(() => _micState = _MicState.processing);
    if (path == null) {
      if (mounted) setState(() => _micState = _MicState.idle);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      unawaited(_safeDeleteAudio(path));
      // ~0.25s of 16kHz/16-bit/mono PCM — filters out accidental taps
      // without any real speech before spending an Azure call on them.
      if (bytes.length < 8000) {
        if (mounted) setState(() => _micState = _MicState.idle);
        return;
      }
      final result = await assessCallTurn(
        _app.pronunciation,
        bytes,
        primaryLang: resolveLocale(_app.courseLanguage),
        nativeLang: resolveLocale(_app.nativeLanguage),
        onError: (e, st, {required reason}) => unawaited(
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason: 'AiTutorScreen._stopMicRecordingAndAssess: $reason',
            fatal: false,
          ),
        ),
      );
      if (mounted) setState(() => _micState = _MicState.idle);
      if (result.transcript.trim().isEmpty) {
        if (result.failed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.aiTutorAudioError),
            ),
          );
        }
        return;
      }
      await _sendMessage(
        result.transcript,
        feedback: result.feedback,
        pronScore: result.pronScore,
        lowScoreWords: result.lowScoreWords,
      );
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'AiTutorScreen._stopMicRecordingAndAssess failed',
          fatal: false,
        ),
      );
      if (mounted) setState(() => _micState = _MicState.idle);
    }
  }

  Future<void> _safeDeleteAudio(String path) async {
    try {
      await File(path).delete();
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'AiTutorScreen._safeDeleteAudio failed',
          fatal: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // stop() must finish before dispose() runs — firing both unawaited let
    // dispose() tear down the plugin's native session while stop() was
    // still flushing the in-progress recording.
    unawaited(_stopThenDisposeRecorder());
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _stopThenDisposeRecorder() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'AiTutorScreen._stopThenDisposeRecorder: stop failed',
          fatal: false,
        ),
      );
    }
    await _recorder.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only depends on aiContent (static after boot) — select() avoids
    // rebuilding this screen on unrelated notifyListeners() calls (e.g. XP
    // changes) that context.watch<AppStateProvider>() would trigger on
    // every message sent, even from this very screen.
    final (suggestions, baseWelcome) = context
        .select<AppStateProvider, (List<String>, String)>(
          (app) => (
            app.aiContent.quickSuggestionsFor(AiTutorMode.chat),
            app.aiContent.welcomeMessageForKey('chat'),
          ),
        );
    final welcome = _persona.welcome.isNotEmpty ? _persona.welcome : baseWelcome;
    final micBusy = _micState != _MicState.idle || _pronChipActive;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_persona.avatar, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _persona.displayName.isNotEmpty ? _persona.displayName : AppLocalizations.of(context)!.aiTutorTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        // Item 4 do pedido: ícone de call no canto superior direito da tela,
        // não mais um FAB flutuando sobre o conteúdo/composer.
        actions: [
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AiTutorCallScreen())),
            icon: const Icon(Icons.call_rounded),
            color: AppTheme.accentBright,
            tooltip: AppLocalizations.of(context)!.aiTutorCallTooltip,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // ListView.builder instead of ListView(children: [...]) — chat
            // history grows unbounded over a long conversation, so only the
            // bubbles actually on screen should be built.
            //
            // reverse: true anchors content to the bottom (next to the
            // composer) instead of the top, matching every mainstream chat
            // app: with only the welcome bubble on screen there's no dead
            // gap between it and the input, and new messages stay pinned in
            // view for free (no manual scroll-to-bottom animation needed —
            // see _scrollToBottom's removal). itemBuilder walks the visual
            // order back-to-front: newest (typing indicator, then history
            // newest-first) at index 0, welcome bubble last.
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount:
                  (welcome.isNotEmpty ? 1 : 0) +
                  _history.length +
                  (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                var i = index;
                if (_sending) {
                  if (i == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: _TypingIndicator(),
                    );
                  }
                  i -= 1;
                }
                if (i < _history.length) {
                  final m = _history[_history.length - 1 - i];
                  if (m.role == 'user' && m.pronScore != null) {
                    return _PronCard(
                      text: m.content,
                      pronScore: m.pronScore!,
                      lowScoreWords: m.lowScoreWords,
                    );
                  }
                  if (m.role != 'user' && m.pronounceWord != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AiBubble(text: m.content, isUser: false),
                        _PronPracticeChip(
                          word: m.pronounceWord!,
                          pronunciation: _app.pronunciation,
                          targetLang: resolveLocale(_app.courseLanguage),
                          isBusyElsewhere: () =>
                              _micState != _MicState.idle || _pronChipActive,
                          onActiveChanged: (active) {
                            if (mounted) setState(() => _pronChipActive = active);
                          },
                        ),
                      ],
                    );
                  }
                  return _AiBubble(text: m.content, isUser: m.role == 'user');
                }
                return _AiBubble(text: welcome, isUser: false);
              },
            ),
          ),
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(
                    suggestions[i],
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 12),
                  ),
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
                      enabled: !_sending && !micBusy,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 14,
                        color: AppTheme.textMainDark,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: AppLocalizations.of(context)!.aiTutorInputHint,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MicButton(
                    state: _micState,
                    disabled: _sending || _pronChipActive,
                    onStart: _startMicRecording,
                    onStop: _stopMicRecordingAndAssess,
                    onCancel: _cancelMicRecording,
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (!_sending && !micBusy)
                        ? () => _send(_controller.text)
                        : null,
                    icon: const Icon(Icons.send_rounded),
                    tooltip: AppLocalizations.of(context)!.aiTutorSendTooltip,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.tutor),
    );
  }
}

class _MicButton extends StatelessWidget {
  final _MicState state;
  final bool disabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  const _MicButton({
    required this.state,
    required this.disabled,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final recording = state == _MicState.recording;
    final processing = state == _MicState.processing;
    final active = !disabled && !processing;
    return Semantics(
      button: true,
      enabled: active,
      label: recording
          ? AppLocalizations.of(context)!.aiTutorMicRecordingLabel
          : AppLocalizations.of(context)!.aiTutorMicIdleLabel,
      child: GestureDetector(
        onTapDown: active ? (_) => onStart() : null,
        onTapUp: active ? (_) => onStop() : null,
        onTapCancel: active ? onCancel : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording ? AppTheme.red : AppTheme.surfaceDark,
            border: Border.all(
              color: recording ? AppTheme.red : AppTheme.borderDark,
            ),
            boxShadow: recording
                ? [
                    BoxShadow(
                      color: AppTheme.red.withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: processing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentBright,
                  ),
                )
              : Icon(
                  recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: recording ? Colors.white : AppTheme.accentBright,
                  size: 20,
                ),
        ),
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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppTheme.accent.withValues(alpha: 0.28)
                    : AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isUser
                      ? AppTheme.accentBright.withValues(alpha: 0.5)
                      : AppTheme.borderDark,
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  color: AppTheme.textMainDark,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline pronunciation score card for a mic-recorded user turn — replaces
/// the plain [_AiBubble] for that message so the recognized text, the
/// Azure `PronScore`, and a short tip surface directly in the feed.
class _PronCard extends StatelessWidget {
  final String text;
  final double pronScore;
  final List<PronWord> lowScoreWords;
  const _PronCard({
    required this.text,
    required this.pronScore,
    required this.lowScoreWords,
  });

  @override
  Widget build(BuildContext context) {
    final good = pronScore >= 80;
    final scoreColor = good ? AppTheme.green : AppTheme.gold;
    final tip = lowScoreWords.isEmpty
        ? AppLocalizations.of(context)!.aiTutorPronPerfect
        : AppLocalizations.of(context)!.aiTutorPronAttention(
            lowScoreWords.take(3).map((w) => w.word).join(', '),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accentBright.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: AppTheme.accentBright,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '"$text"',
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14,
                            color: AppTheme.textMainDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: scoreColor.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '${pronScore.round()}',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scoreColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tip,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      color: AppTheme.textSubDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChipState { idle, recording, processing, error }

/// "Praticar pronúncia" chip rendered below a bot bubble whose reply carried
/// a `[[PRONOUNCE:word]]` marker (migration 068). Owns its own [AudioRecorder]
/// (separate from the composer's) so it never contends over the same
/// recorder session — [isBusyElsewhere]/[onActiveChanged] enforce the
/// single-recording-at-a-time rule against the composer mic and other chips.
/// Records just the one word/expression and sends it to
/// [PronunciationAssessmentService.assess] with `referenceText` set, for a
/// scripted (stricter) score than the unscripted mic pipeline elsewhere in
/// this screen.
class _PronPracticeChip extends StatefulWidget {
  final String word;
  final PronunciationAssessmentService pronunciation;
  final String targetLang;
  final bool Function() isBusyElsewhere;
  final void Function(bool active) onActiveChanged;
  const _PronPracticeChip({
    required this.word,
    required this.pronunciation,
    required this.targetLang,
    required this.isBusyElsewhere,
    required this.onActiveChanged,
  });

  @override
  State<_PronPracticeChip> createState() => _PronPracticeChipState();
}

class _PronPracticeChipState extends State<_PronPracticeChip> {
  final AudioRecorder _recorder = AudioRecorder();
  _ChipState _state = _ChipState.idle;
  double? _score;

  Future<void> _toggle() async {
    if (_state == _ChipState.processing) return;
    if (_state == _ChipState.recording) {
      await _stopAndAssess();
      return;
    }
    if (widget.isBusyElsewhere()) return;
    await _start();
  }

  Future<void> _start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final path =
        '${Directory.systemTemp.path}/tutor_pron_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: '_PronPracticeChip._start failed',
          fatal: false,
        ),
      );
      if (mounted) setState(() => _state = _ChipState.error);
      return;
    }
    widget.onActiveChanged(true);
    if (mounted) {
      setState(() {
        _state = _ChipState.recording;
        _score = null;
      });
    }
  }

  Future<void> _stopAndAssess() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: '_PronPracticeChip._stopAndAssess: stop failed',
          fatal: false,
        ),
      );
    }
    widget.onActiveChanged(false);
    if (mounted) setState(() => _state = _ChipState.processing);
    if (path == null) {
      if (mounted) setState(() => _state = _ChipState.error);
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      unawaited(_safeDelete(path));
      // ~0.25s of 16kHz/16-bit/mono PCM — same accidental-tap filter used by
      // the screen's main mic pipeline.
      if (bytes.length < 8000) {
        if (mounted) setState(() => _state = _ChipState.error);
        return;
      }
      final result = await widget.pronunciation.assess(
        bytes,
        lang: widget.targetLang,
        isNativePass: false,
        referenceText: widget.word,
      );
      if (result == null) {
        if (mounted) setState(() => _state = _ChipState.error);
        return;
      }
      if (mounted) {
        setState(() {
          _state = _ChipState.idle;
          _score = result.pronScore;
        });
      }
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: '_PronPracticeChip._stopAndAssess failed',
          fatal: false,
        ),
      );
      if (mounted) setState(() => _state = _ChipState.error);
    }
  }

  Future<void> _safeDelete(String path) async {
    try {
      await File(path).delete();
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: '_PronPracticeChip._safeDelete failed',
          fatal: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_state == _ChipState.recording) widget.onActiveChanged(false);
    unawaited(_stopThenDisposeRecorder());
    super.dispose();
  }

  Future<void> _stopThenDisposeRecorder() async {
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (e, st) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: '_PronPracticeChip._stopThenDisposeRecorder: stop failed',
          fatal: false,
        ),
      );
    }
    await _recorder.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recording = _state == _ChipState.recording;
    final processing = _state == _ChipState.processing;
    final errored = _state == _ChipState.error;
    final label = switch (_state) {
      _ChipState.recording => l10n.aiTutorPronPracticeRecording,
      _ChipState.processing => l10n.aiTutorPronPracticeProcessing,
      _ChipState.error => l10n.aiTutorPronPracticeError,
      _ChipState.idle => l10n.aiTutorPronPracticeCta(widget.word),
    };
    final accentColor = recording
        ? AppTheme.red
        : (errored ? AppTheme.gold : AppTheme.accentBright);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: processing ? null : _toggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accentColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (processing)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentBright,
                          ),
                        ),
                      ),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_score != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_score! >= 80 ? AppTheme.green : AppTheme.gold)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_score!.round()}%',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _score! >= 80 ? AppTheme.green : AppTheme.gold,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accentBright,
          ),
        ),
      ),
    );
  }
}
