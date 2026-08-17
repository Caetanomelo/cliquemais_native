import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shared circular record/stop mic button used by [VpcScreen] and
/// [DriveModeScreen]: solid accent circle that turns red with a glow while
/// listening, disabled (no tap, no glow) while [enabled] is false.
class RecordMicButton extends StatelessWidget {
  final bool listening;
  final bool enabled;
  final VoidCallback? onTap;
  const RecordMicButton({super.key, required this.listening, this.enabled = true, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: listening ? 'Parar gravação' : 'Gravar pronúncia',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: listening ? AppTheme.red : AppTheme.accent,
            boxShadow: listening
                ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)]
                : null,
          ),
          child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
