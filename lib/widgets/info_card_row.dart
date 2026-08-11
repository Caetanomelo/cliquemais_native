import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shared "leading avatar + title/subtitle + chevron" tappable row, used by
/// the Dashboard's primary/secondary cards, the Settings resource list, and
/// the Corp Portal track list — these were near-identical hand-rolled
/// Material+InkWell+Row widgets before this was extracted.
class InfoCardRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;
  final Color materialColor;
  final double titleFontSize;
  final FontWeight titleFontWeight;
  final double subtitleFontSize;
  final Color chevronColor;
  final double gap;
  final BorderRadius borderRadius;

  const InfoCardRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.decoration,
    this.padding = const EdgeInsets.all(14),
    this.materialColor = Colors.transparent,
    this.titleFontSize = 14,
    this.titleFontWeight = FontWeight.w700,
    this.subtitleFontSize = 11,
    this.chevronColor = AppTheme.textSubDark,
    this.gap = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: materialColor,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: decoration,
          child: Row(
            children: [
              leading,
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: 'Sora', fontSize: titleFontSize, fontWeight: titleFontWeight, color: AppTheme.textMainDark)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontFamily: 'Sora', fontSize: subtitleFontSize, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: chevronColor),
            ],
          ),
        ),
      ),
    );
  }
}
