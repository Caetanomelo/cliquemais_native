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
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'ai_tutor_call_screen.dart';
import 'call_turn_assessor.dart';

enum _MicState { idle, recording, processing }

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

  @override
  void initState() {
    super.initState();
    _app = context.read<AppStateProvider>();
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
      final reply = await _app.aiTutor.send(
        systemPrompt: _app.aiContent.systemPromptForKey('chat'),
        history: priorHistory,
        userMessage: outgoing,
      );
      if (!mounted) return;
      setState(
        () => _history.add(AiChatMessage(role: 'assistant', content: reply)),
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
    if (_micState != _MicState.idle || _sending) return;
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
    final (suggestions, welcome) = context
        .select<AppStateProvider, (List<String>, String)>(
          (app) => (
            app.aiContent.quickSuggestionsFor(AiTutorMode.chat),
            app.aiContent.welcomeMessageForKey('chat'),
          ),
        );
    final micBusy = _micState != _MicState.idle;

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.aiTutorTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AiTutorCallScreen())),
        backgroundColor: AppTheme.accentBright,
        foregroundColor: Colors.black,
        tooltip: AppLocalizations.of(context)!.aiTutorCallTooltip,
        child: const Icon(Icons.call_rounded),
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
                    disabled: _sending,
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
