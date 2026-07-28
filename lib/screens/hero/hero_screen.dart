import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';

/// Second of the app's two initial screens (web's `#main-stage`, shown
/// right after the splash logo on every app launch): brand logo with a
/// glow, headline + subhead, and a single CTA that hands off to the
/// Dashboard (web's `showDashboard()`).
class HeroScreen extends StatelessWidget {
  const HeroScreen({super.key});

  void _enter(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      body: SafeArea(
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
                        BoxShadow(color: AppTheme.accent.withValues(alpha: 0.28), blurRadius: 140, spreadRadius: 30),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/images/hero_logo.jpg', width: 230, fit: BoxFit.contain),
                  ),
                ],
              ),
              const SizedBox(height: 44),
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMainDark,
                    height: 1.1,
                    letterSpacing: -0.4,
                  ),
                  children: [
                    TextSpan(text: 'O inglês que você '),
                    TextSpan(text: 'achou que nunca aprenderia.', style: TextStyle(color: AppTheme.accent)),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'DESTA VEZ É DIFERENTE. E VOCÊ VAI SENTIR ISSO.',
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
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(2),
                  onTap: () => _enter(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                    child: Text(
                      'EU QUERO FALAR INGLÊS',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 2.5,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
