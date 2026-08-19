/// Same Supabase project the web app (`WEB_BASE`) uses for Auth and
/// `content_completions` (see `supabase/migrations/006_content_completions.sql`
/// in the sibling web project) — one project, one set of student accounts,
/// shared between phone and browser.
///
/// The anon key is safe to ship in the app binary: real access control is
/// Row Level Security (`auth.uid() = user_id`), not secrecy of this key —
/// same reasoning as `VITE_SUPABASE_ANON_KEY` already being exposed in the
/// web app's client bundle. Defaults to production here, same pattern as
/// [NetlifyConfig.baseUrl], rather than defaulting empty: now that login is
/// mandatory (Hero -> LoginSignupScreen on every first launch), a build that
/// silently ran with auth disabled would leave every user stuck unable to
/// pass the login gate, instead of just missing an optional feature.
/// Overridable at build time for a staging project — `flutter run
/// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bgxqtsqdrtjmugemnnnp.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJneHF0c3FkcnRqbXVnZW1ubm5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyMzk5NDcsImV4cCI6MjEwMDgxNTk0N30.fXw_lMe2s4l9x8XGXxBwqpx145eumvXIH9Cp5XZCcIE',
  );
}
