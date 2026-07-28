import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../netlify_config.dart';

/// Fetches the `/data/*.json` content files straight from the
/// Netlify-hosted API (backed by Supabase) on every call — no on-disk
/// cache, no bundled asset fallback. The app is online-only by design,
/// keeping the install size small and content edits (new units, phrases,
/// vocab) visible immediately without an app-store release.
class RemoteContentService {
  Future<String> loadString(String asset) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/data/$asset');
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Failed to load $asset: HTTP ${res.statusCode}');
    }
    jsonDecode(res.body); // sanity check — surface malformed payloads early
    return res.body;
  }
}
