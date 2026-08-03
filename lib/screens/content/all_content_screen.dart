import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/lesson_unit.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/level_unit_picker.dart';
import '../ai_tutor/ai_tutor_screen.dart';
import '../drive_mode/drive_mode_screen.dart';
import '../lesson/unit_lesson_screen.dart';
import '../content/study_session_screen.dart';
import '../vpc/vpc_screen.dart';

/// "Todo o Conteúdo" — same dark navy / glass-card design language as the
/// Dashboard: hero (logo, greeting, streak, "Continuar Aprendendo" CTA,
/// quick-action cards, XP/streak stat bar, overall progress) followed by
/// the full curriculum grouped by book, using the same card/button styling
/// as Início.
class AllContentScreen extends StatelessWidget {
  const AllContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateProvider>();
    final grouped = app.curriculum.groupedByBook();
    final journey = app.journeyProgress;

    String? highlightId;
    for (final u in app.curriculum.units) {
      if (!app.curriculumProgress.isUnitComplete(u.id)) {
        highlightId = u.id;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDashboard,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _TopStrip(onBack: () => Navigator.of(context).maybePop()),
          _Hero(
            todayXp: app.todayXp,
            weekXp: app.weekXp,
            totalXp: app.totalXp,
            streakDays: app.streakDays,
            overallFraction: journey.overallFraction,
            onContinue: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudySessionScreen()),
            ),
            onVocab: () => showLevelUnitPicker(
              context,
              units: app.unitData.unitMeta,
              currentCefr: journey.cefr,
              onPicked: (unit) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => VpcScreen(unit: unit)),
              ),
            ),
            onPronunc: () => showLevelUnitPicker(
              context,
              units: app.unitData.unitMeta,
              currentCefr: journey.cefr,
              onPicked: (unit) => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DriveModeScreen(unit: unit)),
              ),
            ),
            onTutor: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiTutorScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in grouped.entries) ...[
                  _BookHeader(title: entry.key),
                  const SizedBox(height: 10),
                  for (final unit in entry.value) ...[
                    _UnitCard(unit: unit, highlighted: unit.id == highlightId),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.conteudos),
    );
  }
}

class _TopStrip extends StatelessWidget {
  final VoidCallback onBack;
  const _TopStrip({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: AppTheme.surfaceDark.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
                  border: Border.all(color: AppTheme.borderDark),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.accentBright),
                    SizedBox(width: 6),
                    Text('Painel',
                        style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentBright)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Bom dia';
  if (hour < 18) return 'Boa tarde';
  return 'Boa noite';
}

class _Hero extends StatelessWidget {
  final int todayXp;
  final int weekXp;
  final int totalXp;
  final int streakDays;
  final double overallFraction;
  final VoidCallback onContinue;
  final VoidCallback onVocab;
  final VoidCallback onPronunc;
  final VoidCallback onTutor;

  const _Hero({
    required this.todayXp,
    required this.weekXp,
    required this.totalXp,
    required this.streakDays,
    required this.overallFraction,
    required this.onContinue,
    required this.onVocab,
    required this.onPronunc,
    required this.onTutor,
  });

  @override
  Widget build(BuildContext context) {
    final streakText = streakDays <= 0
        ? 'Comece sua sequência hoje. Todo dia conta. 🔥'
        : '$streakDays ${streakDays == 1 ? 'dia seguido' : 'dias seguidos'}. Você já é diferente da semana passada. 🔥';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.navyMid, AppTheme.navyDeep])),
      child: Column(
        children: [
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.near_me_rounded, color: AppTheme.accent2, size: 24),
                  SizedBox(width: 6),
                  Text('Click', style: TextStyle(fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.accent2)),
                  Text('+', style: TextStyle(fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.gold)),
                ],
              ),
              const Text('INGLÊS',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.gold, letterSpacing: 3)),
              const SizedBox(height: 6),
              const Text('INGLÊS PARA BRASILEIROS',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSubDark, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 22),
          Text('${_greeting()}. Cada minuto conta.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
          const SizedBox(height: 6),
          Text(streakText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
          const SizedBox(height: 18),
          _ContinueButton(onTap: onContinue),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickCard(
                  icon: Icons.bolt_rounded,
                  iconColor: AppTheme.gold,
                  title: '5 palavras novas',
                  subtitle: 'Resultados em 2 min',
                  badge: '2 min',
                  onTap: onVocab,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickCard(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: AppTheme.red,
                  title: 'Desafio de pronúncia',
                  subtitle: 'Soe como nativo(a)',
                  badge: '3 min',
                  onTap: onPronunc,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickCard(
                  icon: Icons.forum_rounded,
                  iconColor: AppTheme.accent2,
                  title: 'Conversa real agora',
                  subtitle: 'Com Tutor IA',
                  badge: '5 min',
                  onTap: onTutor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x33141B29),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.navBorder),
            ),
            child: Row(
              children: [
                _StatCell(value: '$todayXp', label: 'XP', color: AppTheme.accentBright),
                const _StatDivider(),
                _StatCell(value: '$weekXp', label: 'na semana', color: AppTheme.gold),
                const _StatDivider(),
                _StatCell(value: '$totalXp', label: 'total', color: AppTheme.accent2),
                const _StatDivider(),
                _StatCell(value: '$streakDays', label: 'sequência', color: AppTheme.red),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PROGRESSO GERAL',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.textSubDark, letterSpacing: 1.2)),
              Text('${(overallFraction * 100).round()}%',
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.accentBright)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: overallFraction,
              minHeight: 6,
              backgroundColor: AppTheme.navBorder,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accentBright),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryButtonGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusBtn),
          ),
          child: Column(
            children: const [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('Continuar Aprendendo',
                      style: TextStyle(fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
              SizedBox(height: 2),
              Text('Continuar sua jornada →',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 11, color: Color(0xCCFFFFFF))),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;
  const _QuickCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 1,
                  style: const TextStyle(fontFamily: 'Sora', fontSize: 9, color: AppTheme.textSubDark)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.accent2, borderRadius: BorderRadius.circular(AppTheme.radiusBtn)),
                child: Text(badge, style: const TextStyle(fontFamily: 'Sora', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: 'Sora', fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontFamily: 'Sora', fontSize: 9, color: AppTheme.textSubDark)),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 26, color: AppTheme.navBorder);
  }
}

class _BookHeader extends StatelessWidget {
  final String title;
  const _BookHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: AppTheme.accentBright, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(title.toUpperCase(),
            style: const TextStyle(fontFamily: 'Sora', fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textMainDark, letterSpacing: 0.6)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppTheme.navBorder)),
      ],
    );
  }
}

class _UnitCard extends StatelessWidget {
  final LessonUnit unit;
  final bool highlighted;
  const _UnitCard({required this.unit, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateProvider>();
    final emoji = app.curriculum.emojiForUnit(unit.id);
    final label = unit.unit == 0 ? 'BOAS-VINDAS' : 'PASSO ${unit.unit}';
    final goal = unit.goals.isNotEmpty ? unit.goals.first : unit.subtitle;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => UnitLessonScreen(unit: unit)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlighted ? AppTheme.gold : AppTheme.borderDark, width: highlighted ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSubDark, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(unit.title,
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textMainDark)),
                    const SizedBox(height: 2),
                    Text(goal, style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textSubDark)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppTheme.navBorder, shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.accentBright),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
