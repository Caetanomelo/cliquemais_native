import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../screens/ai_tutor/ai_tutor_screen.dart';
import '../screens/content/all_content_screen.dart';

/// The three top-level destinations the persistent bottom nav can jump to.
enum AppTab { inicio, conteudos, tutor }

/// Persistent bottom navigation bar (Início / Tutor / Conteúdos), rendered
/// by every screen's `Scaffold.bottomNavigationBar` so it's always
/// available. Tutor sits centered and visually raised — it's the app's
/// primary action, not a peer of the other two. Since the app navigates via
/// pushed routes rather than an IndexedStack shell, tapping a tab unwinds
/// the stack back to the root Dashboard and then pushes the target screen.
class AppBottomNav extends StatelessWidget {
  final AppTab? current;
  // Lets a screen with an in-progress recording (VpcScreen/DriveModeScreen)
  // confirm before the tab switch unwinds the stack out from under it —
  // `_go` pops eagerly via `popUntil`, which doesn't go through PopScope,
  // so this is the only hook screens have to intercept it. Returning false
  // cancels the tab switch; omit it (null) for screens with nothing to lose.
  final Future<bool> Function()? onBeforeLeave;
  const AppBottomNav({super.key, this.current, this.onBeforeLeave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.topbar,
        border: const Border(top: BorderSide(color: AppTheme.navBorder, width: 1)),
        boxShadow: const [BoxShadow(color: Color(0x2200F2FE), blurRadius: 20)],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Início',
              active: current == AppTab.inicio,
              onTap: () => _go(context, AppTab.inicio),
            ),
            _TutorButton(
              active: current == AppTab.tutor,
              onTap: () => _go(context, AppTab.tutor),
            ),
            _NavItem(
              icon: Icons.menu_book_rounded,
              label: 'Conteúdos',
              active: current == AppTab.conteudos,
              onTap: () => _go(context, AppTab.conteudos),
            ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, AppTab tab) async {
    if (tab == current) return;
    if (onBeforeLeave != null) {
      final canLeave = await onBeforeLeave!();
      if (!canLeave || !context.mounted) return;
    }
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    switch (tab) {
      case AppTab.inicio:
        break;
      case AppTab.conteudos:
        nav.push(MaterialPageRoute(builder: (_) => const AllContentScreen()));
        break;
      case AppTab.tutor:
        nav.push(MaterialPageRoute(builder: (_) => const AiTutorScreen()));
        break;
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accentBright : AppTheme.textSubDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 3),
            if (active)
              Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppTheme.accentBright, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}

/// Centered, raised action button for the AI Tutor — the bar's primary
/// destination, so it reads as a distinct control rather than a third
/// peer of Início/Conteúdos.
class _TutorButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _TutorButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -14),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryButtonGradient,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.topbar, width: 4),
                boxShadow: [
                  BoxShadow(color: AppTheme.accentBright.withValues(alpha: active ? 0.55 : 0.35), blurRadius: 16, spreadRadius: 1),
                ],
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 26),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -8),
            child: Text('Tutor',
                style: TextStyle(
                    fontFamily: 'Sora', fontSize: 10, fontWeight: FontWeight.w700, color: active ? AppTheme.accentBright : AppTheme.textSubDark)),
          ),
        ],
      ),
    );
  }
}
