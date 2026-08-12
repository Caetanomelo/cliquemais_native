import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    // Debug builds keep crashes local (noisy during development); release
    // builds report to the existing "app-clique-mais" Firebase project.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    // Crashlytics itself needs Firebase.initializeApp() to have succeeded,
    // so there's no structured-logging path available for this specific
    // failure — debugPrint is the only option left, not an oversight.
    debugPrint('Firebase.initializeApp failed: $e');
  }
  runApp(const CliqueMaisApp());
}
