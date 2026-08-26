import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
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
      // Consumer (not a plain `child:` MaterialApp) so the whole app rebuilds
      // — and re-resolves `locale:` below — the instant nativeLanguage
      // changes in Settings, without requiring an app restart.
      child: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          return MaterialApp(
            title: 'Click+ Inglês',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            // nativeLanguage is the app's own language concept (decoupled
            // from the OS locale) — persistence isn't ready until
            // AppStateProvider.init() resolves (see SplashScreen), so this
            // falls back to 'pt' (persistence's own default) until then.
            locale: Locale(appState.ready ? appState.nativeLanguage : 'pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
