import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../netlify_config.dart';

/// Wraps a transient (network error, timeout, 5xx) failure so [loadString]
/// knows to retry it — a 4xx or a malformed payload never becomes valid by
/// retrying, so those propagate immediately instead.
class _RetryableException implements Exception {
  final Object cause;
  _RetryableException(this.cause);
  @override
  String toString() => cause.toString();
}

/// Fetches the `/data/*.json` content files from the Netlify-hosted API
/// (backed by Supabase). Transient failures (timeouts, network errors,
/// 5xx) are retried with backoff; if every attempt still fails, the last
/// successfully-fetched copy of that asset is served from an on-disk cache
/// instead of hard-failing the screen. A brand-new install with zero
/// connectivity still has nothing to fall back to — the app remains
/// online-only by design, this only smooths over a flaky connection on a
/// device that already loaded the content once.
class RemoteContentService {
  final http.Client _client;
  static const _maxAttempts = 3;
  static const _retryBaseDelay = Duration(milliseconds: 400);

  RemoteContentService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> loadString(String asset) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _fetchOnce(asset);
      } on _RetryableException catch (e) {
        lastError = e.cause;
        if (attempt < _maxAttempts) {
          await Future.delayed(_retryBaseDelay * attempt);
        }
      } catch (e) {
        lastError = e;
        break;
      }
    }

    final cached = await _readCache(asset);
    if (cached != null) {
      try {
        unawaited(FirebaseCrashlytics.instance.recordError(
          lastError,
          StackTrace.current,
          reason: 'RemoteContentService.loadString($asset) failed, served from disk cache',
          fatal: false,
        ));
      } catch (_) {
        // Firebase isn't initialized in some contexts (unit tests) —
        // telemetry is best-effort and must never block the cache fallback.
      }
      return cached;
    }
    throw lastError!;
  }

  Future<String> _fetchOnce(String asset) async {
    final uri = Uri.parse('${NetlifyConfig.baseUrl}/data/$asset');
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw _RetryableException(e);
    }
    if (res.statusCode >= 500) {
      throw _RetryableException(Exception('Failed to load $asset: HTTP ${res.statusCode}'));
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load $asset: HTTP ${res.statusCode}');
    }
    jsonDecode(res.body); // sanity check — surface malformed payloads early
    unawaited(_writeCache(asset, res.body));
    return res.body;
  }

  Future<File> _cacheFile(String asset) async {
    final dir = await getApplicationCacheDirectory();
    return File('${dir.path}/content_cache_$asset');
  }

  Future<void> _writeCache(String asset, String body) async {
    try {
      final file = await _cacheFile(asset);
      await file.writeAsString(body);
    } catch (_) {
      // Best-effort — a failed cache write just means a later outage has
      // nothing to fall back to; it must never block the content that did
      // load successfully.
    }
  }

  Future<String?> _readCache(String asset) async {
    try {
      final file = await _cacheFile(asset);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
