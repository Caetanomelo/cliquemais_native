/// Same Supabase project the web app (`WEB_BASE`) uses for Auth and
/// `content_completions` (see `supabase/migrations/006_content_completions.sql`
/// in the sibling web project) — one project, one set of student accounts,
/// shared between phone and browser.
///
/// The anon key is safe to ship in the app binary: real access control is
/// Row Level Security (`auth.uid() = user_id`), not secrecy of this key.
/// Overridable at build time the same way as [NetlifyConfig] — e.g.
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// against a staging project — and empty by default so a build that forgets
/// to set them just runs with auth disabled instead of crashing (see
/// [AuthService.isConfigured]).
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
}
