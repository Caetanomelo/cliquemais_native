import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class LiveTranscript {
  final String text;
  final bool isFinal;
  const LiveTranscript({this.text = '', this.isFinal = false});
}

/// Renders the live partial-STT transcript driven by [listenable]. VPC and
/// Drive Mode's `onResult` callback can fire many times per second while
/// listening — routing that through the screen's own `setState` rebuilds
/// the whole body (score ring, phrase text, buttons) on every partial word.
/// Isolating it behind a `ValueListenableBuilder` means only this small text
/// widget rebuilds; the screen updates the notifier directly, no `setState`.
class LiveTranscriptText extends StatelessWidget {
  final ValueListenable<LiveTranscript> listenable;
  final EdgeInsetsGeometry padding;
  const LiveTranscriptText({super.key, required this.listenable, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveTranscript>(
      valueListenable: listenable,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Text(
            '"${value.text}"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: value.isFinal ? AppTheme.green : AppTheme.accentBright,
            ),
          ),
        );
      },
    );
  }
}
