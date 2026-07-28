import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../netlify_config.dart';

/// Serves the `assets/data/*.json` content files, transparently preferring a
/// copy previously fetched from the Netlify-hosted `/data/*.json` files over
/// the bundled asset — so content updates (new units, phrases, vocab) reach
/// the app without an app-store release.
///
/// Boot never blocks on network: [loadString] always resolves from local
/// storage (cache file if present, else the bundled asset), while
/// [refreshInBackground] fires an unawaited fetch that updates the cache for
/// the *next* launch. Bundled assets remain the offline fallback forever.
class RemoteContentService {
  static const List<String> knownAssets = [
    'unit_meta.json',
    'drive_phrases.json',
    'vocab_items.json',
    'emoji_map.json',
    'lessons.json',
    'unit_progression.json',
    'corp_tracks.json',
    'unit_emojis.json',
    'ai_system_prompts.json',
    'ai_quick_suggestions.json',
    'ai_welcome_messages.json',
  ];

  Directory? _cacheDir;

  Future<Directory> _dir() async {
    final existing = _cacheDir;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/remote_content');
    await dir.create(recursive: true);
    return _cacheDir = dir;
  }

  Future<String> loadString(String asset) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$asset');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {
      // Cache unavailable for any reason — bundled asset is always safe.
    }
    return rootBundle.loadString('assets/data/$asset');
  }

  /// Fire-and-forget refresh of every known content file. Never awaited by
  /// callers — errors and slow networks must never delay app boot.
  void refreshInBackground() {
    unawaited(_refreshAll());
  }

  Future<void> _refreshAll() async {
    final dir = await _dir();
    final client = http.Client();
    try {
      await Future.wait(knownAssets.map((asset) => _refreshOne(client, dir, asset)));
    } finally {
      client.close();
    }
  }

  Future<void> _refreshOne(http.Client client, Directory dir, String asset) async {
    try {
      final uri = Uri.parse('${NetlifyConfig.baseUrl}/data/$asset');
      final res = await client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      jsonDecode(res.body); // sanity check before it can replace a working cache
      await File('${dir.path}/$asset').writeAsString(res.body);
    } catch (_) {
      // Offline or Netlify hiccup — keep whatever cache (or bundled asset)
      // is already in place.
    }
  }
}
