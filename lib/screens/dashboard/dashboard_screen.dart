import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dashboard_stats.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/coming_soon.dart';
import '../../widgets/level_unit_picker.dart';
import '../content/all_content_screen.dart';
import '../content/study_session_screen.dart';
import '../drive_mode/drive_mode_screen.dart';
import '../hero/hero_screen.dart';
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
    // Non-reactive handle: unitData/practiceProgress are stable service
    // instances (only their internal fields mutate), and here they're only
    // read inside onTap closures — not rendered — so watching them would
    // just add rebuild triggers with no visible effect.
    final app = context.read<AppStateProvider>();

    // Each field is selected individually (rather than watching the whole
    // provider, or selecting the JourneyProgress/DomainProgress objects
    // wholesale) so this screen only rebuilds when a value it actually
    // renders changes — e.g. a voiceGender or introDone update elsewhere
    // no longer triggers a Dashboard rebuild while it sits underneath in
    // the nav stack. JourneyProgress/DomainProgress are freshly-constructed
    // plain objects with identity equality, so selecting them directly
    // would defeat select's diffing; the primitive fields have real value
    // equality.
    final cefr = context.select<AppStateProvider, String>(
      (a) => a.journeyProgress.cefr,
    );
    final levelFraction = context.select<AppStateProvider, double>(
      (a) => a.journeyProgress.levelFraction,
    );
    final todayXp = context.select<AppStateProvider, int>((a) => a.todayXp);
    // Analytics Core only renders once logged in (see the isLoggedIn branch
    // below), so these read the real, Supabase-backed figures (Fase 8) —
    // realStreakDays/realWeekXp/realTotalXp/realDomainProgress fall back to
    // the local-only numbers on their own until the first fetch resolves.
    final streakDays = context.select<AppStateProvider, int>(
      (a) => a.realStreakDays,
    );
    final weekXp = context.select<AppStateProvider, int>((a) => a.realWeekXp);
    final totalXp = context.select<AppStateProvider, int>((a) => a.realTotalXp);
    final domains = DomainProgress(
      pronuncia: context.select<AppStateProvider, double>(
        (a) => a.realDomainProgress.pronuncia,
      ),
      vocabulario: context.select<AppStateProvider, double>(
        (a) => a.realDomainProgress.vocabulario,
      ),
      fluencia: context.select<AppStateProvider, double>(
        (a) => a.realDomainProgress.fluencia,
      ),
      compreensao: context.select<AppStateProvider, double>(
        (a) => a.realDomainProgress.compreensao,
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bgDashboard,
      body: SafeArea(
        bottom: false,
        // Fase 8: completions.record() never pushes a live update back into
        // realDomainProgress/realStreakDays/etc (that would mean a Supabase
        // round-trip on every single answer) — pull-to-refresh is the
        // explicit way to see fresh Analytics Core numbers after finishing a
        // practice session, on top of the automatic refresh on login.
        child: RefreshIndicator(
          onRefresh: () =>
              context.read<AppStateProvider>().refreshRealAnalytics(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 108),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const _TopBadge(),
              const SizedBox(height: 18),
              _GreetingHeader(
                cefr: cefr,
                onBell: () => showComingSoonSnackbar(context),
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              const SizedBox(height: 18),
              _LevelTrack(cefr: cefr, levelFraction: levelFraction),
              const SizedBox(height: 22),
              _XpDailySection(
                todayXp: todayXp,
                goal: AppStateProvider.dailyXpGoal,
              ),
              const SizedBox(height: 16),
              _SectionLabel(AppLocalizations.of(context)!.dashboardSectionDriveMode),
              const SizedBox(height: 12),
              _ActionGrid(
                onAllContent: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AllContentScreen()),
                ),
                onVocab: () => showLevelUnitPicker(
                  context,
                  units: app.unitData.unitMeta,
                  currentCefr: cefr,
                  completedUnits: app.practiceProgress.vocabCompletedUnits,
                  onPicked: (units) => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VpcScreen(units: units)),
                  ),
                ),
                onStudySession: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudySessionScreen()),
                ),
                onDriveMode: () => showLevelUnitPicker(
                  context,
                  units: app.unitData.unitMeta,
                  currentCefr: cefr,
                  completedUnits: app.practiceProgress.driveCompletedUnits,
                  onPicked: (units) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DriveModeScreen(units: units),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionLabel(AppLocalizations.of(context)!.dashboardSectionAnalyticsCore),
                  GestureDetector(
                    onTap: () async {
                      await context.read<AppStateProvider>().auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HeroScreen()),
                          (route) => false,
                        );
                      }
                    },
                    child: Text(
                      AppLocalizations.of(context)!.dashboardSignOut,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        color: AppTheme.textSubDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AnalyticsCore(
                streakDays: streakDays,
                weekXp: weekXp,
                totalXp: totalXp,
                domains: domains,
              ),
              const SizedBox(height: 26),
              _SectionLabel(AppLocalizations.of(context)!.dashboardSectionYourDomains),
              const SizedBox(height: 12),
              _DomainGrid(domains: domains),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.inicio),
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
          gradient: const LinearGradient(
            colors: [AppTheme.navyMid, AppTheme.navy],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
          border: Border.all(color: AppTheme.navBorder),
        ),
        child: Text(
          AppLocalizations.of(context)!.dashboardTopBadge,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTheme.accentBright,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String cefr;
  final VoidCallback onBell;
  final VoidCallback onSettings;
  const _GreetingHeader({
    required this.cefr,
    required this.onBell,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: AppLocalizations.of(context)!.dashboardSettingsSemanticLabel,
          child: GestureDetector(
            onTap: onSettings,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryButtonGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.dashboardWelcomeBack,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  color: AppTheme.textSubDark,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.dashboardYourJourney,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMainDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentBright.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(color: AppTheme.borderDark),
                    ),
                    child: Text(
                      cefr,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentBright,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onBell,
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: AppTheme.textMainDark,
          ),
          tooltip: AppLocalizations.of(context)!.dashboardNotificationsTooltip,
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
                Text(
                  _levels[i],
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: i <= currentIndex
                        ? AppTheme.accentBright
                        : AppTheme.textSubDark,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(color: AppTheme.navBorder),
                        FractionallySizedBox(
                          widthFactor: i < currentIndex
                              ? 1.0
                              : (i == currentIndex
                                    ? levelFraction.clamp(0.06, 1.0)
                                    : 0.0),
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
              Text(
                AppLocalizations.of(context)!.dashboardXpDailyLabel,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSubDark,
                  letterSpacing: 1,
                ),
              ),
              Text(
                AppLocalizations.of(context)!.dashboardXpDailyProgress(todayXp, goal),
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gold,
                ),
              ),
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
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: AppTheme.textSubDark,
      ),
    );
  }
}

/// 2x2 action grid — All Content / Vocabulary / AI Tutor / Drive Mode —
/// mirroring the web Dashboard's `.db-action-grid` layout (option 02).
/// Only the two primary CTAs (All Content, Drive Mode) get the glow
/// treatment, matching the web hierarchy.
class _ActionGrid extends StatelessWidget {
  final VoidCallback onAllContent;
  final VoidCallback onVocab;
  final VoidCallback onStudySession;
  final VoidCallback onDriveMode;
  const _ActionGrid({
    required this.onAllContent,
    required this.onVocab,
    required this.onStudySession,
    required this.onDriveMode,
  });

  static Widget _iconBox({Color? bg, Gradient? gradient, required Widget child}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionGridCard(
                  featured: true,
                  onTap: onAllContent,
                  leading: _iconBox(
                    bg: AppTheme.accent2.withValues(alpha: 0.18),
                    child: const Icon(Icons.school_rounded, color: AppTheme.accent2, size: 18),
                  ),
                  title: l10n.dashboardAllContentTitle,
                  subtitle: l10n.dashboardAllContentSubtitle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionGridCard(
                  onTap: onVocab,
                  leading: _iconBox(
                    bg: AppTheme.green.withValues(alpha: 0.15),
                    child: const Icon(Icons.style_rounded, color: AppTheme.green, size: 18),
                  ),
                  title: l10n.dashboardVocabTitle,
                  subtitle: l10n.dashboardVocabSubtitle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ActionGridCard(
                  onTap: onStudySession,
                  leading: _iconBox(
                    bg: AppTheme.gold.withValues(alpha: 0.15),
                    child: const Icon(Icons.menu_book_rounded, color: AppTheme.gold, size: 18),
                  ),
                  title: l10n.settingsStudySessionTitle,
                  subtitle: l10n.settingsStudySessionSubtitle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionGridCard(
                  featured: true,
                  onTap: onDriveMode,
                  leading: _iconBox(
                    gradient: AppTheme.primaryButtonGradient,
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
                  ),
                  title: l10n.dashboardDriveModeTitle,
                  subtitle: l10n.dashboardDriveModeSubtitle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionGridCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool featured;
  const _ActionGridCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = featured
        ? AppTheme.glassCard()
        : BoxDecoration(
            color: AppTheme.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.borderDark),
          );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMainDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  color: AppTheme.textSubDark,
                ),
              ),
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
  const _AnalyticsCore({
    required this.streakDays,
    required this.weekXp,
    required this.totalXp,
    required this.domains,
  });

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
                _StatMiniCard(
                  icon: Icons.local_fire_department_rounded,
                  color: AppTheme.red,
                  value: '$streakDays',
                  label: AppLocalizations.of(context)!.dashboardStreakDaysLabel,
                ),
                const SizedBox(height: 8),
                _StatMiniCard(
                  icon: Icons.bolt_rounded,
                  color: AppTheme.accentBright,
                  value: '$weekXp',
                  label: AppLocalizations.of(context)!.dashboardWeekXpLabel,
                ),
                const SizedBox(height: 8),
                _StatMiniCard(
                  icon: Icons.emoji_events_rounded,
                  color: AppTheme.gold,
                  value: '$totalXp',
                  label: AppLocalizations.of(context)!.dashboardTotalXpLabel,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 168,
              child: CustomPaint(
                painter: _DiamondChartPainter(
                  domains: domains,
                  labels: [
                    AppLocalizations.of(context)!.domainAbbrevPronunciation,
                    AppLocalizations.of(context)!.domainAbbrevVocabulary,
                    AppLocalizations.of(context)!.domainAbbrevFluency,
                    AppLocalizations.of(context)!.domainAbbrevComprehension,
                  ],
                ),
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
  const _StatMiniCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

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
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMainDark,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 9,
                    color: AppTheme.textSubDark,
                  ),
                ),
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
  final List<String> labels;
  _DiamondChartPainter({required this.domains, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 6);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final values = [
      domains.pronuncia,
      domains.vocabulario,
      domains.fluencia,
      domains.compreensao,
    ];

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
    canvas.drawPath(
      fillPath,
      Paint()..color = AppTheme.accentBright.withValues(alpha: 0.22),
    );
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
          text: labels[i],
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 9,
            color: AppTheme.textSubDark,
            fontWeight: FontWeight.w700,
          ),
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

class _DomainGrid extends StatelessWidget {
  final DomainProgress domains;
  const _DomainGrid({required this.domains});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (
        icon: Icons.record_voice_over_rounded,
        label: l10n.domainPronunciation,
        color: AppTheme.accent,
        value: domains.pronuncia,
      ),
      (
        icon: Icons.style_rounded,
        label: l10n.domainVocabulary,
        color: AppTheme.green,
        value: domains.vocabulario,
      ),
      (
        icon: Icons.forum_rounded,
        label: l10n.domainFluency,
        color: AppTheme.accent2,
        value: domains.fluencia,
      ),
      (
        icon: Icons.menu_book_rounded,
        label: l10n.domainComprehension,
        color: AppTheme.gold,
        value: domains.compreensao,
      ),
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
  const _DomainRingCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
  });

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
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              color: AppTheme.textSubDark,
            ),
          ),
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
