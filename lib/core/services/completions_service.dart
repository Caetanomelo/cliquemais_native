import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// One row of content_completions (see WEB_BASE's
/// supabase/migrations/006_content_completions.sql — same Supabase project,
/// same table/columns/RLS, so a completion recorded here and one recorded by
/// the web app land in the same place). content_id conventions:
///   Drive Mode -> "drive:ID"  where ID is drive_phrases.id (same id the web app uses)
///   VPC        -> "vocab:ID"  where ID is vocab_items.id (native's own stable id —
///                 native VPC reads the separate vocab_items table, not
///                 lessons.json's embedded vocab blocks like web VPC does,
///                 so there's no shared item identity to key off between
///                 platforms here; see WEB_BASE's src/supabase-client.js
///                 content_id convention comment for the web side's reasons)
///   Currículo  -> "unitN:type:blockIndex:itemIndex" via [curriculumContentId] —
///                 same composite key web's src/main.js _contentId() builds.
///                 The curriculum's own vocab lesson type shares this key
///                 with VPC's entry for the same word (both read the same
///                 lessons.json/curriculum vocab block), so finishing one
///                 already covers the other.
class CompletionEvent {
  final String module;
  final String contentId;
  final int unit;
  final String domain;
  final int xp;
  const CompletionEvent({
    required this.module,
    required this.contentId,
    required this.unit,
    required this.domain,
    this.xp = 5,
  });

  Map<String, dynamic> toJson() =>
      {'module': module, 'contentId': contentId, 'unit': unit, 'domain': domain, 'xp': xp};

  factory CompletionEvent.fromJson(Map<String, dynamic> j) => CompletionEvent(
        module: j['module'] as String,
        contentId: j['contentId'] as String,
        unit: j['unit'] as int,
        domain: j['domain'] as String,
        xp: j['xp'] as int? ?? 5,
      );
}

/// Per-item completion tracking (Drive Mode phrases, VPC words, later the
/// curriculum) — the native counterpart of WEB_BASE's
/// src/supabase-client.js Auth.recordCompletion.
///
/// Login is optional app-wide (see the feature plan's design decisions), so
/// this mirrors the web app's behavior exactly: record() is a no-op when
/// logged out, same as Auth.recordCompletion's `if (!supabase ||
/// !currentUser) return`. Once logged in, every completion is cached
/// on-device immediately in [_localIds] (so isCompleted()/Fase 7's queue
/// filtering can work fully offline, same pattern as
/// PracticeProgressService) and pushed to Supabase in the background. A
/// push that throws (offline, still logged in) is queued in [_pending] and
/// retried on the next flushPending() call instead of being lost — no new
/// connectivity-detection dependency, since a failed write is itself the
/// offline signal.
class CompletionsService {
  static const _kLocalIds = 'content_completions_local_ids';
  static const _kPending = 'content_completions_pending';

  final AuthService _auth;
  final SharedPreferences _prefs;
  final Set<String> _localIds;
  final List<CompletionEvent> _pending;

  CompletionsService._(this._auth, this._prefs, this._localIds, this._pending);

  static Future<CompletionsService> create(AuthService auth) async {
    final prefs = await SharedPreferences.getInstance();
    final localIds = (prefs.getStringList(_kLocalIds) ?? const []).toSet();
    final pending = (prefs.getStringList(_kPending) ?? const [])
        .map((s) => CompletionEvent.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    final svc = CompletionsService._(auth, prefs, localIds, pending);
    unawaited(svc.flushPending());
    return svc;
  }

  /// True once this device has recorded [contentId] done for the currently
  /// logged-in student. Not namespaced per-user — same simplification
  /// PersistenceService/PracticeProgressService already make for XP/unit
  /// progress on this device.
  bool isCompleted(String contentId) => _localIds.contains(contentId);

  /// Builds the composite content_id for one curriculum item — mirrors
  /// web's src/main.js _contentId(unitId, type, blockIdx, itemIdx) exactly
  /// (unitId there is the "unitN" string; unit here is the bare int, so the
  /// prefix is rebuilt as "unit$unit").
  static String curriculumContentId(int unit, String type, int blockIndex, int itemIndex) =>
      'unit$unit:$type:$blockIndex:$itemIndex';

  Future<void> record({
    required String module,
    required String contentId,
    required int unit,
    required String domain,
    int xp = 5,
  }) async {
    if (!_auth.isLoggedIn) return;
    if (_localIds.contains(contentId)) return;
    _localIds.add(contentId);
    await _prefs.setStringList(_kLocalIds, _localIds.toList());
    await _pushOrQueue(
      CompletionEvent(module: module, contentId: contentId, unit: unit, domain: domain, xp: xp),
    );
  }

  Future<void> flushPending() async {
    if (!_auth.isLoggedIn || _pending.isEmpty) return;
    final remaining = <CompletionEvent>[];
    for (final event in _pending) {
      if (!await _writeToSupabase(event)) remaining.add(event);
    }
    _pending
      ..clear()
      ..addAll(remaining);
    await _savePending();
  }

  Future<void> _pushOrQueue(CompletionEvent event) async {
    if (!await _writeToSupabase(event)) {
      _pending.add(event);
      await _savePending();
    }
  }

  Future<bool> _writeToSupabase(CompletionEvent event) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await Supabase.instance.client.from('content_completions').upsert(
        {
          'user_id': user.id,
          'module': event.module,
          'content_id': event.contentId,
          'unit': event.unit,
          'domain': event.domain,
          'xp': event.xp,
        },
        onConflict: 'user_id,content_id',
        ignoreDuplicates: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _savePending() async {
    await _prefs.setStringList(_kPending, _pending.map((e) => jsonEncode(e.toJson())).toList());
  }
}
