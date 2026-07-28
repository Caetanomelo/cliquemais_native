import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_state_provider.dart';
import 'screens/splash/splash_screen.dart';

/// Root widget: wires the single [AppStateProvider] via `provider` and
/// starts navigation at [SplashScreen], which owns app boot (`init()`).
class CliqueMaisApp extends StatelessWidget {
  const CliqueMaisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppStateProvider(),
      child: MaterialApp(
        title: 'Click+ Inglês',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const SplashScreen(),
      ),
    );
  }
}
