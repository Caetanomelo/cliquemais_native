import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Rounded hint bubble with a downward-pointing tail, shown above the mic
/// button on every STT screen. STT never auto-starts — the user must always
/// tap the mic icon — so this bubble is the visual cue for that ("Aperte
/// para falar"), matching the house bubble style used in the AI Tutor chat.
/// Held back by [delay] so it doesn't flash in the instant the mic button
/// appears — it's a nudge for someone who hasn't tapped yet, not a label.
/// Callers mount this conditionally (only while idle), so the delay restarts
/// naturally each time it reappears.
class SpeechBubble extends StatefulWidget {
  final String? text;
  final Duration delay;
  const SpeechBubble({super.key, this.text, this.delay = const Duration(seconds: 3)});

  @override
  State<SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<SpeechBubble> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mic_none_rounded, size: 16, color: AppTheme.accentBright),
              const SizedBox(width: 8),
              Text(
                widget.text ?? AppLocalizations.of(context)!.speechBubbleDefaultText,
                style: const TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textMainDark),
              ),
            ],
          ),
        ),
        CustomPaint(size: const Size(20, 8), painter: _BubbleTailPainter()),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = AppTheme.surfaceDark;
    final stroke = Paint()
      ..color = AppTheme.borderDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx - 8, 0)
      ..lineTo(cx, size.height)
      ..lineTo(cx + 8, 0);
    canvas.drawPath(path, fill..style = PaintingStyle.fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
