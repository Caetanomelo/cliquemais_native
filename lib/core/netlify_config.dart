/// Base URL of the deployed Cliquemais web app on Netlify — the shared
/// backend for cloud TTS and hosted content (see `WEB_BASE/netlify/functions`
/// and `WEB_BASE/data/*.json` in the sibling web project).
///
/// Certificate pinning was evaluated and deliberately skipped: Netlify
/// terminates TLS with short-lived, auto-rotated Let's Encrypt certs, so
/// static pins would need a remote-updatable backup-pin mechanism (which
/// doesn't exist here) or the app would risk bricking connectivity on every
/// rotation. There's no `usesCleartextTraffic`/custom network security
/// config on Android, so the OS default (HTTPS-only, system trust store,
/// cleartext blocked since API 28) already applies — that's the right
/// level of protection for this app's data (lesson content, chat prompts,
/// pronunciation audio — no payments or sensitive PII).
class NetlifyConfig {
  static const baseUrl = 'https://clickmaisapp.netlify.app';
}
