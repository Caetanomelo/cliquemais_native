import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../netlify_config.dart';

/// Registers this device for push notifications: requests permission
/// (a no-op on Android below 13), reads the FCM token, and posts it to the
/// Netlify-hosted `/.netlify/functions/subscribe` endpoint (which stores
/// FCM tokens and is used by `send-push.js` to fan out via Firebase Admin).
/// Also re-posts whenever FCM rotates the token. Entirely best-effort: no
/// Firebase config, no permission, or no network must never affect the rest
/// of the app — this mirrors the fallback-first pattern used throughout
/// [CloudTtsService] and [RemoteContentService].
class PushService {
  final http.Client _client;
  PushService({http.Client? client}) : _client = client ?? http.Client();

  Future<void> register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _subscribe(token);
      messaging.onTokenRefresh.listen(_subscribe);
    } catch (_) {
      // Push is additive — never required for the app to function.
    }
  }

  Future<void> _subscribe(String token) async {
    try {
      final uri = Uri.parse('${NetlifyConfig.baseUrl}/.netlify/functions/subscribe');
      await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Best-effort — will retry on next launch or token refresh.
    }
  }

  void dispose() => _client.close();
}
