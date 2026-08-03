import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/unit_meta.dart';

/// CEFR level order used for grouping/gating. Any unit whose `cefr` isn't
/// in this list falls into a trailing "other" bucket instead of being lost.
const List<String> kCefrLevelOrder = ['A1', 'A2', 'B1', 'B2'];

/// A run of units sharing the same `phase` name within a single CEFR level
/// (never merged across levels — e.g. B1 "Especialização" and B2
/// "Especialização" stay separate groups).
class _PhaseGroup {
  final String phase;
  final List<UnitMeta> units;
  const _PhaseGroup(this.phase, this.units);
}

/// Bottom sheet unit picker used by both Drive Mode and Vocabulário. Units
/// are grouped into CEFR sub-groups (A1/A2/B1/B2, in level order); within
/// each level, units sharing the same phase name are concatenated into a
/// single pickable entry instead of repeating that name once per unit.
/// Picking an entry hands back every unit it bundles, in shuffled order
/// (re-randomized every time the picker opens), so callers can concatenate
/// their content into one combined session. A level is unlocked once the
/// user's current CEFR level has reached it, matching the coarse level
/// indicator already used on the Dashboard's `_LevelTrack`.
Future<void> showLevelUnitPicker(
  BuildContext context, {
  required List<UnitMeta> units,
  required String currentCefr,
  required void Function(List<int> units) onPicked,
  String title = 'Escolha uma unidade',
}) {
  final byLevel = <String, List<UnitMeta>>{};
  for (final u in units) {
    byLevel.putIfAbsent(u.cefr, () => []).add(u);
  }
  final rng = Random();
  for (final list in byLevel.values) {
    list.shuffle(rng);
  }
  final phaseGroups = <String, List<_PhaseGroup>>{};
  for (final entry in byLevel.entries) {
    final byPhase = <String, List<UnitMeta>>{};
    for (final u in entry.value) {
      byPhase.putIfAbsent(u.phase, () => []).add(u);
    }
    phaseGroups[entry.key] = [for (final p in byPhase.entries) _PhaseGroup(p.key, p.value)];
  }
  final orderedLevels = [
    ...kCefrLevelOrder.where(byLevel.containsKey),
    ...byLevel.keys.where((l) => !kCefrLevelOrder.contains(l)),
  ];
  final currentIndex = kCefrLevelOrder.indexOf(currentCefr).clamp(0, kCefrLevelOrder.length - 1);

  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surfaceDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppTheme.borderDark, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title,
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
              ),
              Expanded(
                child: _LevelGroupList(
                  levels: orderedLevels,
                  phaseGroups: phaseGroups,
                  currentCefr: currentCefr,
                  currentIndex: currentIndex,
                  onPicked: (units) {
                    Navigator.of(ctx).pop();
                    onPicked(units);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _LevelGroupList extends StatefulWidget {
  final List<String> levels;
  final Map<String, List<_PhaseGroup>> phaseGroups;
  final String currentCefr;
  final int currentIndex;
  final void Function(List<int> units) onPicked;

  const _LevelGroupList({
    required this.levels,
    required this.phaseGroups,
    required this.currentCefr,
    required this.currentIndex,
    required this.onPicked,
  });

  @override
  State<_LevelGroupList> createState() => _LevelGroupListState();
}

class _LevelGroupListState extends State<_LevelGroupList> {
  late String? _expanded = widget.currentCefr;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final level in widget.levels)
          _LevelSection(
            level: level,
            phaseGroups: widget.phaseGroups[level] ?? const [],
            unlocked: !kCefrLevelOrder.contains(level) || kCefrLevelOrder.indexOf(level) <= widget.currentIndex,
            isCurrent: level == widget.currentCefr,
            expanded: _expanded == level,
            onToggle: () => setState(() => _expanded = _expanded == level ? null : level),
            onPicked: widget.onPicked,
          ),
      ],
    );
  }
}

class _LevelSection extends StatelessWidget {
  final String level;
  final List<_PhaseGroup> phaseGroups;
  final bool unlocked;
  final bool isCurrent;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(List<int> units) onPicked;

  const _LevelSection({
    required this.level,
    required this.phaseGroups,
    required this.unlocked,
    required this.isCurrent,
    required this.expanded,
    required this.onToggle,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final totalUnits = phaseGroups.fold<int>(0, (sum, g) => sum + g.units.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgDashboard.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: isCurrent ? AppTheme.accentBright : AppTheme.borderDark),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: unlocked
                    ? onToggle
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Complete o nível anterior para desbloquear $level'),
                            duration: const Duration(seconds: 2),
                          ),
                        ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (unlocked ? AppTheme.accentBright : AppTheme.textSubDark).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: unlocked
                            ? Text(level,
                                style: TextStyle(
                                  fontFamily: 'Sora',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isCurrent ? AppTheme.accentBright : AppTheme.textMainDark,
                                ))
                            : const Icon(Icons.lock_rounded, size: 16, color: AppTheme.textSubDark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nível $level',
                                style: TextStyle(
                                  fontFamily: 'Sora',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: unlocked ? AppTheme.textMainDark : AppTheme.textSubDark,
                                )),
                            Text(
                              unlocked ? '$totalUnits unidades' : 'Bloqueado',
                              style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textSubDark),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        unlocked ? (expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded) : Icons.lock_rounded,
                        color: unlocked ? AppTheme.accentBright : AppTheme.textSubDark,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (unlocked && expanded)
              for (final pg in phaseGroups)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.18),
                    child: Text('${pg.units.length}', style: const TextStyle(color: AppTheme.accentBright, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(pg.phase, style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textMainDark)),
                  subtitle: Text(
                    pg.units.length > 1 ? '${pg.units.length} unidades combinadas' : '1 unidade',
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: AppTheme.textSubDark),
                  ),
                  trailing: pg.units.any((u) => u.milestone) ? const Icon(Icons.emoji_events_rounded, color: AppTheme.gold) : null,
                  onTap: () => onPicked([for (final u in pg.units) u.unit]),
                ),
          ],
        ),
      ),
    );
  }
}
