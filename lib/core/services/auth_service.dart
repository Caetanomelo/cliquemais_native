import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Student login (email/senha) via Supabase Auth — same project as the web
/// app, so an account created on the phone works on the browser and vice
/// versa. Auth is an enhancement, not a hard dependency: every method here
/// degrades to a no-op/throw that callers already handle gracefully rather
/// than crashing the boot chain, matching the guarded-init pattern used for
/// Firebase in `main.dart` and for [SpeechService] after the real-device
/// crash-on-launch fix (unguarded plugin `.initialize()` in the boot chain
/// must never take the whole app down).
class AuthService {
  bool _available = false;
  bool get isConfigured => _available;

  /// Must run once, before [currentUser]/[signIn]/etc. are used — mirrors
  /// `Firebase.initializeApp()` in `main.dart`. Swallows its own failures
  /// (missing --dart-define config, no network) so a broken/unset Supabase
  /// project degrades the app to "no login available" instead of crashing
  /// cold boot on every device.
  Future<void> init() async {
    if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) return;
    try {
      await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  User? get currentUser => _available ? Supabase.instance.client.auth.currentUser : null;
  bool get isLoggedIn => currentUser != null;

  /// Fires on sign-in/sign-out/token-refresh, including the initial session
  /// restore from local storage on app start. Empty when Supabase never
  /// initialized, so listeners (AppStateProvider) don't need their own
  /// isConfigured checks.
  Stream<AuthState> get onAuthStateChange =>
      _available ? Supabase.instance.client.auth.onAuthStateChange : const Stream.empty();

  Future<void> signUp(String email, String password, {String? displayName}) async {
    if (!_available) throw StateError('supabase-not-configured');
    await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      data: displayName != null && displayName.isNotEmpty ? {'display_name': displayName} : null,
    );
  }

  Future<void> signIn(String email, String password) async {
    if (!_available) throw StateError('supabase-not-configured');
    await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    if (!_available) return;
    await Supabase.instance.client.auth.signOut();
  }
}
