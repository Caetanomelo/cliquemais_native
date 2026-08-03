import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models/unit_meta.dart';

/// CEFR level order used for grouping/gating. Any unit whose `cefr` isn't
/// in this list falls into a trailing "other" bucket instead of being lost.
const List<String> kCefrLevelOrder = ['A1', 'A2', 'B1', 'B2'];

/// Bottom sheet unit picker used by both Drive Mode and Vocabulário. Units
/// are grouped into CEFR sub-groups (A1/A2/B1/B2, in level order — not
/// resorted by unit number, so interleaved B1/B2 units stay each in their
/// own group); a group is unlocked once the user's current CEFR level has
/// reached it, matching the coarse level indicator already used on the
/// Dashboard's `_LevelTrack`.
Future<void> showLevelUnitPicker(
  BuildContext context, {
  required List<UnitMeta> units,
  required String currentCefr,
  required void Function(int unit) onPicked,
  String title = 'Escolha uma unidade',
}) {
  final groups = <String, List<UnitMeta>>{};
  for (final u in units) {
    groups.putIfAbsent(u.cefr, () => []).add(u);
  }
  final orderedLevels = [
    ...kCefrLevelOrder.where(groups.containsKey),
    ...groups.keys.where((l) => !kCefrLevelOrder.contains(l)),
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
                  groups: groups,
                  currentCefr: currentCefr,
                  currentIndex: currentIndex,
                  onPicked: (unit) {
                    Navigator.of(ctx).pop();
                    onPicked(unit);
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
  final Map<String, List<UnitMeta>> groups;
  final String currentCefr;
  final int currentIndex;
  final void Function(int unit) onPicked;

  const _LevelGroupList({
    required this.levels,
    required this.groups,
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
            units: widget.groups[level] ?? const [],
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
  final List<UnitMeta> units;
  final bool unlocked;
  final bool isCurrent;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(int unit) onPicked;

  const _LevelSection({
    required this.level,
    required this.units,
    required this.unlocked,
    required this.isCurrent,
    required this.expanded,
    required this.onToggle,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
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
                              unlocked ? '${units.length} unidades' : 'Bloqueado',
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
              for (final u in units)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.18),
                    child: Text('${u.step}', style: const TextStyle(color: AppTheme.accentBright, fontWeight: FontWeight.w700)),
                  ),
                  title: Text(u.phase, style: const TextStyle(fontFamily: 'Sora', color: AppTheme.textMainDark)),
                  trailing: u.milestone ? const Icon(Icons.emoji_events_rounded, color: AppTheme.gold) : null,
                  onTap: () => onPicked(u.unit),
                ),
          ],
        ),
      ),
    );
  }
}
