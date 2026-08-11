import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Ports the VPC score ring (decoded_app.html `.vpc-ring-fill` SVG circle,
/// r=35, stroke-width=7, `showResult()`'s `dash=circ-(sc/100)*circ`).
class VpcRingPainter extends CustomPainter {
  final double percent; // 0.0-1.0
  final Color strokeColor;
  final Color bgColor;
  const VpcRingPainter({required this.percent, required this.strokeColor, this.bgColor = AppTheme.borderDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 5;
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    const startAngle = -1.5707963267948966; // -90deg, matches SVG `rotate(-90deg)`
    final sweep = 6.283185307179586 * percent.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant VpcRingPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.strokeColor != strokeColor;
  }
}
