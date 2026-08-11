import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/info_card_row.dart';
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
          return InfoCardRow(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CorpTrackDetailScreen(track: t)),
            ),
            materialColor: AppTheme.surfaceDark,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.borderDark)),
            titleFontSize: 15,
            subtitleFontSize: 12,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Center(child: Text(t.emoji, style: const TextStyle(fontSize: 22))),
            ),
            title: t.name,
            subtitle: t.role,
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
