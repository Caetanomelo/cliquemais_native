import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_state_provider.dart';
import '../hero/hero_screen.dart';

/// First of the app's two initial screens (web's `#splash-screen`):
/// initializes [AppStateProvider] (persistence, data assets, speech
/// engine) then hands off to [HeroScreen] — the web's `#main-stage`,
/// shown on every launch right after the logo. Simpler than the web
/// app's animated "neural orb" splash — that flourish is deferred,
/// Phase 1 focuses on functional parity.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _failed = false);
    final app = context.read<AppStateProvider>();
    final start = DateTime.now();
    try {
      await app.init();
    } catch (e, st) {
      // debugPrint is a no-op in release builds, so this failure — the one
      // that leaves the user stuck at the splash screen — was invisible in
      // production telemetry. Every other error site in the app already
      // reports through Crashlytics; this is the one that matters most.
      try {
        await FirebaseCrashlytics.instance.recordError(e, st, reason: 'SplashScreen._boot: AppStateProvider.init failed', fatal: false);
      } catch (_) {
        // Best-effort — must never block showing the retry UI below.
      }
      if (!mounted) return;
      setState(() => _failed = true);
      return;
    }
    final elapsed = DateTime.now().difference(start);
    const minSplash = Duration(milliseconds: 900);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HeroScreen()),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.06).animate(
                CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _failed
                      ? const RadialGradient(colors: [AppTheme.red, AppTheme.red])
                      : const RadialGradient(colors: [AppTheme.accentBright, AppTheme.accent]),
                  boxShadow: [
                    BoxShadow(color: AppTheme.accentBright.withValues(alpha: 0.45), blurRadius: 40, spreadRadius: 6),
                  ],
                ),
                child: Icon(
                  _failed ? Icons.wifi_off_rounded : Icons.bolt_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Click+ Inglês',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8F0FE),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _failed ? 'Sem conexão com a internet.\nO app precisa estar online para funcionar.' : 'Preparando sua sessão…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 13,
                color: const Color(0xFFE8F0FE).withValues(alpha: 0.55),
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _boot,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.buttonBg,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
