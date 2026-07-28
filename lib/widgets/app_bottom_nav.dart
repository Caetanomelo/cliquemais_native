import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../screens/content/all_content_screen.dart';
import '../screens/settings/settings_screen.dart';

/// The four top-level destinations the persistent bottom nav can jump to.
enum AppTab { inicio, conteudos, evolucao, perfil }

/// Persistent bottom navigation bar (Início/Conteúdos/Evolução/Perfil),
/// rendered by every screen's `Scaffold.bottomNavigationBar` so it's always
/// available, per the reference screenshot. Since the app navigates via
/// pushed routes rather than an IndexedStack shell, tapping a tab unwinds
/// the stack back to the root Dashboard and then pushes the target screen.
class AppBottomNav extends StatelessWidget {
  final AppTab? current;
  const AppBottomNav({super.key, this.current});

  static const _items = [
    (tab: AppTab.inicio, icon: Icons.home_rounded, label: 'Início'),
    (tab: AppTab.conteudos, icon: Icons.menu_book_rounded, label: 'Conteúdos'),
    (tab: AppTab.evolucao, icon: Icons.insights_rounded, label: 'Evolução'),
    (tab: AppTab.perfil, icon: Icons.person_rounded, label: 'Perfil'),
  ];

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
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final item in _items)
              _NavItem(
                icon: item.icon,
                label: item.label,
                active: item.tab == current,
                onTap: () => _go(context, item.tab),
              ),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, AppTab tab) {
    if (tab == current) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    switch (tab) {
      case AppTab.inicio:
        break;
      case AppTab.conteudos:
        nav.push(MaterialPageRoute(builder: (_) => const AllContentScreen()));
        break;
      case AppTab.evolucao:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Em breve'), duration: Duration(seconds: 2)),
        );
        break;
      case AppTab.perfil:
        nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
