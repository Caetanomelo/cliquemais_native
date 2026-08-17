import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shared full-screen result card used by [VpcScreen] and [DriveModeScreen]
/// right after scoring an attempt: translucent backdrop, a color-bordered
/// surface with an emoji, a title/subtitle pair, and an optional extra
/// detail line (e.g. VPC's "Você disse: ..." on a miss). Each screen still
/// owns its own scoring thresholds and copy — this only carries the shared
/// layout.
class PracticeResultOverlay extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? detail;
  final Alignment alignment;
  const PracticeResultOverlay({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.detail,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Align(
          alignment: alignment,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            decoration: BoxDecoration(
              color: AppTheme.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 10),
                Text(title, style: TextStyle(fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: AppTheme.textSubDark)),
                if (detail != null && detail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(detail!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Sora', fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSubDark)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
