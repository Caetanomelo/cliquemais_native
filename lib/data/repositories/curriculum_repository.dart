import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/corp_track.dart';
import '../models/lesson_unit.dart';
import '../models/unit_curriculum_meta.dart';
import 'json_repository.dart';

// Top-level so compute() can ship them to a background isolate — lessons.json
// alone is 400+KB and this repository's loadAll() runs at boot alongside every
// other content repository's, all racing to decode JSON on the main isolate.
List<LessonUnit> _parseUnits(String raw) {
  final map = jsonDecode(raw) as Map<String, dynamic>;
  return map.entries
      .map((e) => LessonUnit.fromJson(e.key, e.value as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.unit.compareTo(b.unit));
}

Map<String, UnitCurriculumMeta> _parseProgression(String raw) {
  final map = jsonDecode(raw) as Map<String, dynamic>;
  return map.map(
    (k, v) => MapEntry(k, UnitCurriculumMeta.fromJson(k, v as Map<String, dynamic>)),
  );
}

List<CorpTrack> _parseCorpTracks(String raw) {
  final list = jsonDecode(raw) as List;
  return list.map((e) => CorpTrack.fromJson(e as Map<String, dynamic>)).toList();
}

/// Loads the full lesson curriculum: lessons.json (`UNITS`),
/// unit_progression.json (`UNIT_META`), corp_tracks.json (`CORP_TRACKS`)
/// and unit_emojis.json (`UNIT_EMOJIS`). Content comes straight from
/// [JsonRepository.content] (Netlify/Supabase-hosted) — no offline fallback.
class CurriculumRepository extends JsonRepository {
  CurriculumRepository({super.content});

  List<LessonUnit>? _units;
  Map<String, UnitCurriculumMeta>? _progression;
  List<CorpTrack>? _corpTracks;
  Map<String, String>? _unitEmojis;
  Map<String, List<LessonUnit>>? _groupedByBook;

  Future<void> loadAll() async {
    await Future.wait([
      _loadUnits(),
      _loadProgression(),
      _loadCorpTracks(),
      _loadUnitEmojis(),
    ]);
  }

  Future<void> _loadUnits() async {
    final raw = await content.loadString('lessons.json');
    _units = await compute(_parseUnits, raw);
  }

  Future<void> _loadProgression() async {
    final raw = await content.loadString('unit_progression.json');
    _progression = await compute(_parseProgression, raw);
  }

  Future<void> _loadCorpTracks() async {
    final raw = await content.loadString('corp_tracks.json');
    _corpTracks = await compute(_parseCorpTracks, raw);
  }

  Future<void> _loadUnitEmojis() async {
    final raw = await content.loadString('unit_emojis.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _unitEmojis = map.map((k, v) => MapEntry(k, v as String));
  }

  List<LessonUnit> get units => _units ?? const [];
  List<CorpTrack> get corpTracks => _corpTracks ?? const [];

  LessonUnit? unitById(String id) {
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  UnitCurriculumMeta? progressionFor(String unitId) => _progression?[unitId];

  String emojiForUnit(String unitId) => _unitEmojis?[unitId] ?? '📘';

  /// Units grouped by `book`, preserving first-seen order (matches the web
  /// app's "Todo o Conteúdo" grouping). `units` is immutable after
  /// [loadAll], so this is computed once and cached — `AllContentScreen`
  /// calls it on every `context.watch` rebuild (XP/streak changes included),
  /// which was otherwise re-grouping the full unit list on each of those.
  Map<String, List<LessonUnit>> groupedByBook() {
    if (_groupedByBook != null) return _groupedByBook!;
    final result = <String, List<LessonUnit>>{};
    for (final u in units) {
      result.putIfAbsent(u.book, () => []).add(u);
    }
    return _groupedByBook = result;
  }
}
