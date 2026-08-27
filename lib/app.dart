import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/app_state_provider.dart';
import 'screens/splash/splash_screen.dart';

/// Wraps the app so any descendant can force a full tree rebuild --
/// equivalent to WEB_BASE's `location.reload()` after a target-language
/// change (see project_web_target_language_switcher_shipped memory). Used
/// after a native-language save so every already-built screen re-mounts
/// fresh, not just the ones that read AppLocalizations.of(context) directly
/// in build() and would otherwise pick up the new locale reactively anyway.
class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() {
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

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
