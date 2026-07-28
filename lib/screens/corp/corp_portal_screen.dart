import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import 'corp_track_detail_screen.dart';

/// Portal Corporativo — the 18 `CORP_TRACKS`, unreachable in the source web
/// app (no nav path existed there) but ported here on request.
class CorpPortalScreen extends StatelessWidget {
  const CorpPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tracks = context.watch<AppStateProvider>().curriculum.corpTracks;
    return Scaffold(
      appBar: AppBar(title: const Text('Portal Corporativo')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final t = tracks[i];
          final color = _parseColor(t.color);
          return Material(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CorpTrackDetailScreen(track: t)),
              ),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.borderDark)),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: Center(child: Text(t.emoji, style: const TextStyle(fontSize: 22))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.name,
                              style: const TextStyle(
                                  fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMainDark)),
                          const SizedBox(height: 2),
                          Text(t.role, style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: AppTheme.textSubDark)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textSubDark),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  Color _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}
