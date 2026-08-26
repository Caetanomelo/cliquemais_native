import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_signup_screen.dart';

/// Second of the app's two initial screens (web's `#main-stage`, shown
/// right after the splash logo on every first-time launch): brand logo with
/// a glow, headline + subhead, then a timed loading bar that hands off to
/// [LoginSignupScreen] — login is mandatory, so there is no CTA here to skip
/// ahead. Returning logged-in users never see this screen at all
/// ([SplashScreen] routes them straight to the Dashboard).
class HeroScreen extends StatefulWidget {
  const HeroScreen({super.key});

  @override
  State<HeroScreen> createState() => _HeroScreenState();
}

class _HeroScreenState extends State<HeroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loadController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loadController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 4000),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _goToLogin();
          })
          ..forward();
  }

  @override
  void dispose() {
    _loadController.dispose();
    super.dispose();
  }

  void _goToLogin() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginSignupScreen()),
    );
  }

  // Tapping anywhere advances immediately instead of forcing the full 4s
  // wait every time (mirrors the web hero's tap-to-skip) — mandatory login
  // still can't be bypassed, this only skips the loading-bar delay.
  void _skip() {
    if (_navigated) return;
    _loadController.stop();
    _goToLogin();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 260,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.28),
                            blurRadius: 140,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/hero_logo.jpg',
                        width: 230,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 44),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.textMainDark,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                    children: [
                      TextSpan(text: l10n.heroTaglinePart1),
                      TextSpan(
                        text: l10n.heroTaglinePart2,
                        style: const TextStyle(color: AppTheme.accent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.heroSubtext,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 3,
                    color: AppTheme.textSubDark.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 52),
                AnimatedBuilder(
                  animation: _loadController,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _loadController.value,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppTheme.accentBright, AppTheme.accent2],
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(50)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.heroPreparing,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2.5,
                    color: AppTheme.textSubDark.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.heroTapToSkip,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: AppTheme.accentBright.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
