import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dashboard_stats.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/level_unit_picker.dart';
import '../ai_tutor/ai_tutor_screen.dart';
import '../content/all_content_screen.dart';
import '../drive_mode/drive_mode_screen.dart';
import '../settings/settings_screen.dart';
import '../vpc/vpc_screen.dart';

/// Dashboard — rebuilt to match the web app's Dashboard screen 1:1
/// (glass cards, glow borders, segmented level track, analytics diamond,
/// domain rings, persistent bottom nav) rather than the earlier native-first
/// list layout.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateProvider>();
    final journey = app.journeyProgress;
    final domains = app.domainProgress;

    return Scaffold(
      backgroundColor: AppTheme.bgDashboard,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 108),
          children: [
            const _TopBadge(),
            const SizedBox(height: 18),
            _GreetingHeader(
              cefr: journey.cefr,
              onBell: () => _emBreve(context),
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 18),
            _LevelTrack(cefr: journey.cefr, levelFraction: journey.levelFraction),
            const SizedBox(height: 22),
            _XpDailySection(todayXp: app.todayXp, goal: AppStateProvider.dailyXpGoal),
            const SizedBox(height: 16),
            _AiTutorPrimaryCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiTutorScreen()),
              ),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('DRIVE MODE'),
            const SizedBox(height: 12),
            _DriveModePrimaryCard(
              onTap: () => showLevelUnitPicker(
                context,
                units: app.unitData.unitMeta,
                currentCefr: journey.cefr,
                completedUnits: app.practiceProgress.driveCompletedUnits,
                onPicked: (units) => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DriveModeScreen(units: units)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SecondaryCard(
              icon: Icons.style_rounded,
              title: 'Vocabulário',
              subtitle: 'Flashcards com gravação e comparação de pronúncia',
              onTap: () => showLevelUnitPicker(
                context,
                units: app.unitData.unitMeta,
                currentCefr: journey.cefr,
                completedUnits: app.practiceProgress.vocabCompletedUnits,
                onPicked: (units) => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => VpcScreen(units: units)),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('ANALYTICS CORE'),
            const SizedBox(height: 12),
            _AnalyticsCore(
              streakDays: app.streakDays,
              weekXp: app.weekXp,
              totalXp: app.totalXp,
              domains: domains,
            ),
            const SizedBox(height: 26),
            _ContentBanner(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AllContentScreen()),
              ),
            ),
            const SizedBox(height: 26),
            const _SectionLabel('SEUS DOMÍNIOS'),
            const SizedBox(height: 12),
            _DomainGrid(domains: domains),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.inicio),
    );
  }

  void _emBreve(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Em breve'), duration: Duration(seconds: 2)),
    );
  }
}

class _TopBadge extends StatelessWidget {
  const _TopBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.navyMid, AppTheme.navy]),
          borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
          border: Border.all(color: AppTheme.navBorder),
        ),
        child: const Text(
          'CLIQUE+',
          style: TextStyle(fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accentBright, letterSpacing: 2),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String cefr;
  final VoidCallback onBell;
  final VoidCallback onSettings;
  const _GreetingHeader({required this.cefr, required this.onBell, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onSettings,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(gradient: AppTheme.primaryButtonGradient, shape: BoxShape.circle),
            child: const Icon(Icons.person_rounded, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bem-vindo(a) de volta',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Text('Sua jornada',
                      style: TextStyle(fontFamily: 'Sora', fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBright.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Text(cefr,
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.accentBright)),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onBell,
          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.textMainDark),
        ),
      ],
    );
  }
}

class _LevelTrack extends StatelessWidget {
  static const _levels = ['A1', 'A2', 'B1', 'B2'];
  final String cefr;
  final double levelFraction;
  const _LevelTrack({required this.cefr, required this.levelFraction});

  @override
  Widget build(BuildContext context) {
    final currentIndex = _levels.indexOf(cefr).clamp(0, _levels.length - 1);
    return Row(
      children: [
        for (var i = 0; i < _levels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Text(_levels[i],
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: i <= currentIndex ? AppTheme.accentBright : AppTheme.textSubDark,
                    )),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(color: AppTheme.navBorder),
                        FractionallySizedBox(
                          widthFactor: i < currentIndex ? 1.0 : (i == currentIndex ? levelFraction.clamp(0.06, 1.0) : 0.0),
                          child: Container(color: AppTheme.accentBright),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _XpDailySection extends StatelessWidget {
  final int todayXp;
  final int goal;
  const _XpDailySection({required this.todayXp, required this.goal});

  @override
  Widget build(BuildContext context) {
    final progress = (todayXp / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glassCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('XP DIÁRIO',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textSubDark, letterSpacing: 1)),
              Text('$todayXp / $goal XP',
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.gold)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppTheme.navBorder,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accentBright),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: AppTheme.textSubDark,
        ));
  }
}

class _DriveModePrimaryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DriveModePrimaryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.glassCard(),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(gradient: AppTheme.primaryButtonGradient, shape: BoxShape.circle),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Drive Mode',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                    SizedBox(height: 3),
                    Text('Prática de pronúncia mãos-livres, com comandos de voz',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiTutorPrimaryCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AiTutorPrimaryCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.glassCard(),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(gradient: AppTheme.primaryButtonGradient, shape: BoxShape.circle),
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tutor IA',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                    SizedBox(height: 3),
                    Text('Converse e pratique pronúncia com o professor de IA',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SecondaryCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppTheme.green.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: AppTheme.green),
              ),
              const SizedBox(width: 14),
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

class _AnalyticsCore extends StatelessWidget {
  final int streakDays;
  final int weekXp;
  final int totalXp;
  final DomainProgress domains;
  const _AnalyticsCore({required this.streakDays, required this.weekXp, required this.totalXp, required this.domains});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _StatMiniCard(icon: Icons.local_fire_department_rounded, color: AppTheme.red, value: '$streakDays', label: 'dias seguidos'),
                const SizedBox(height: 8),
                _StatMiniCard(icon: Icons.bolt_rounded, color: AppTheme.accentBright, value: '$weekXp', label: 'XP na semana'),
                const SizedBox(height: 8),
                _StatMiniCard(icon: Icons.emoji_events_rounded, color: AppTheme.gold, value: '$totalXp', label: 'XP total'),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 168,
              child: CustomPaint(
                painter: _DiamondChartPainter(domains: domains),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatMiniCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatMiniCard({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                Text(label, style: const TextStyle(fontFamily: 'Sora', fontSize: 9, color: AppTheme.textSubDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 4-axis radar ("diamond") chart of Pronúncia/Vocabulário/Fluência/
/// Compreensão, matching the web Dashboard's Analytics Core chart.
class _DiamondChartPainter extends CustomPainter {
  final DomainProgress domains;
  _DiamondChartPainter({required this.domains});

  static const _labels = ['Pron.', 'Vocab.', 'Flu.', 'Comp.'];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 6);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final values = [domains.pronuncia, domains.vocabulario, domains.fluencia, domains.compreensao];

    Offset pointAt(int i, double fraction) {
      final angle = -math.pi / 2 + i * (math.pi * 2 / 4);
      return Offset(
        center.dx + radius * fraction * math.cos(angle),
        center.dy + radius * fraction * math.sin(angle),
      );
    }

    final gridPaint = Paint()
      ..color = AppTheme.navBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final ring in [0.33, 0.66, 1.0]) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final p = pointAt(i, ring);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(center, pointAt(i, 1.0), gridPaint);
    }

    final fillPath = Path();
    final dotPaint = Paint()..color = AppTheme.accentBright;
    for (var i = 0; i < 4; i++) {
      final p = pointAt(i, values[i].clamp(0.04, 1.0));
      if (i == 0) {
        fillPath.moveTo(p.dx, p.dy);
      } else {
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = AppTheme.accentBright.withValues(alpha: 0.22));
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppTheme.accentBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(pointAt(i, values[i].clamp(0.04, 1.0)), 3, dotPaint);
    }

    for (var i = 0; i < 4; i++) {
      final labelPos = pointAt(i, 1.22);
      final tp = TextPainter(
        text: TextSpan(
          text: _labels[i],
          style: const TextStyle(fontFamily: 'Sora', fontSize: 9, color: AppTheme.textSubDark, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _DiamondChartPainter oldDelegate) =>
      oldDelegate.domains.pronuncia != domains.pronuncia ||
      oldDelegate.domains.vocabulario != domains.vocabulario ||
      oldDelegate.domains.fluencia != domains.fluencia ||
      oldDelegate.domains.compreensao != domains.compreensao;
}

class _ContentBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ContentBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.glassCard(),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppTheme.accent2.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.school_rounded, color: AppTheme.accent2),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Todo o Conteúdo',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                    SizedBox(height: 3),
                    Text('Todas as unidades e lições, por livro',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.accentBright),
            ],
          ),
        ),
      ),
    );
  }
}

class _DomainGrid extends StatelessWidget {
  final DomainProgress domains;
  const _DomainGrid({required this.domains});

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.record_voice_over_rounded, label: 'Pronúncia', color: AppTheme.accent, value: domains.pronuncia),
      (icon: Icons.style_rounded, label: 'Vocabulário', color: AppTheme.green, value: domains.vocabulario),
      (icon: Icons.forum_rounded, label: 'Fluência', color: AppTheme.accent2, value: domains.fluencia),
      (icon: Icons.menu_book_rounded, label: 'Compreensão', color: AppTheme.gold, value: domains.compreensao),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _DomainRingCard(
              icon: items[i].icon,
              label: items[i].label,
              color: items[i].color,
              value: items[i].value,
            ),
          ),
        ],
      ],
    );
  }
}

class _DomainRingCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double value;
  const _DomainRingCard({required this.icon, required this.label, required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _RingPainter(fraction: value, color: color),
              child: Center(child: Icon(icon, color: color, size: 18)),
            ),
          ),
          const SizedBox(height: 8),
          Text('${(value * 100).round()}%',
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 9, color: AppTheme.textSubDark)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  _RingPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final trackPaint = Paint()
      ..color = AppTheme.navBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}

