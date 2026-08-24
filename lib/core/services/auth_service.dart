import 'dart:async';
import 'dart:typed_data';

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

  /// Partial update of the caller's own `profiles` row (see
  /// supabase/migrations/007_profile_fields.sql) — only non-null arguments
  /// are written, so callers can pass just what the user actually filled in
  /// on the profile-completion popup without clobbering other columns.
  Future<void> updateProfile({
    String? fullName,
    String? phone,
    String? cpf,
    String? address,
    String? avatarUrl,
    String? targetLanguage,
  }) async {
    if (!_available) throw StateError('supabase-not-configured');
    final uid = currentUser?.id;
    if (uid == null) throw StateError('not-logged-in');
    final patch = <String, dynamic>{
      if (fullName != null) 'display_name': fullName,
      if (phone != null) 'phone': phone,
      if (cpf != null) 'cpf': cpf,
      if (address != null) 'address': address,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (targetLanguage != null) 'target_language': targetLanguage,
    };
    if (patch.isEmpty) return;
    await Supabase.instance.client.from('profiles').update(patch).eq('id', uid);
  }

  /// Uploads avatar bytes to the `avatars` Storage bucket at
  /// `<uid>/avatar.<ext>` (upsert, so re-uploads overwrite in place instead
  /// of accumulating orphaned files) and returns the public URL. Does not
  /// itself write `profiles.avatar_url` — callers pass the result into
  /// [updateProfile] so the profile row update stays a single round trip.
  Future<String> uploadAvatar(Uint8List bytes, {required String fileExt}) async {
    if (!_available) throw StateError('supabase-not-configured');
    final uid = currentUser?.id;
    if (uid == null) throw StateError('not-logged-in');
    final path = '$uid/avatar.$fileExt';
    await Supabase.instance.client.storage
        .from('avatars')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
  }

  /// Fetches the caller's own `profiles` row so the post-login completion
  /// prompt can be skipped once [markProfilePromptSeen] has already run for
  /// this user — mirrors `getProfile()` in the web app's supabase-client.js.
  /// Returns null if logged out or on any fetch error (treated as "nothing
  /// known yet", never a hard failure).
  Future<Map<String, dynamic>?> getProfile() async {
    if (!_available) return null;
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      return await Supabase.instance.client
          .from('profiles')
          .select('display_name, phone, cpf, address, avatar_url, profile_prompt_seen, target_language')
          .eq('id', uid)
          .single();
    } catch (_) {
      return null;
    }
  }

  /// Pre-signup duplicate check for CPF/phone (see WEB_BASE's
  /// supabase/migrations/010_profile_contact_uniqueness.sql) -- call before
  /// [signUp] so a taken CPF/phone is caught with a friendly message
  /// instead of leaving a confirmed auth.users row behind with no
  /// phone/cpf (which is what happens if the unique-index violation is
  /// only caught at [updateProfile], since signUp() itself would have
  /// already succeeded by then). Works while logged out -- the RPC is
  /// security definer and bypasses profiles' RLS for this one yes/no
  /// check. Returns both false if Supabase isn't configured.
  Future<({bool cpfTaken, bool phoneTaken})> checkContactAvailable({
    String? cpf,
    String? phone,
  }) async {
    if (!_available) return (cpfTaken: false, phoneTaken: false);
    final result = await Supabase.instance.client.rpc(
      'check_contact_available',
      params: {'p_cpf': cpf, 'p_phone': phone},
    );
    final map = result as Map<String, dynamic>;
    return (
      cpfTaken: map['cpf_taken'] as bool? ?? false,
      phoneTaken: map['phone_taken'] as bool? ?? false,
    );
  }

  /// Marks the post-login profile-completion prompt as seen (see
  /// `supabase/migrations/008_profile_prompt_seen.sql` in WEB_BASE) so it
  /// stops auto-opening after every login, whether or not the user actually
  /// filled it in. Fire-and-forget from the caller's point of view.
  Future<void> markProfilePromptSeen() async {
    if (!_available) return;
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('profiles').update({'profile_prompt_seen': true}).eq('id', uid);
    } catch (_) {}
  }
}
