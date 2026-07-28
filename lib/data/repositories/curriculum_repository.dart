import 'dart:convert';

import '../../core/services/remote_content_service.dart';
import '../models/corp_track.dart';
import '../models/lesson_unit.dart';
import '../models/unit_curriculum_meta.dart';

/// Loads the full lesson curriculum: lessons.json (`UNITS`),
/// unit_progression.json (`UNIT_META`), corp_tracks.json (`CORP_TRACKS`)
/// and unit_emojis.json (`UNIT_EMOJIS`). Content comes straight from
/// [RemoteContentService] (Netlify/Supabase-hosted) — no offline fallback.
class CurriculumRepository {
  final RemoteContentService _content;
  CurriculumRepository({RemoteContentService? content}) : _content = content ?? RemoteContentService();

  List<LessonUnit>? _units;
  Map<String, UnitCurriculumMeta>? _progression;
  List<CorpTrack>? _corpTracks;
  Map<String, String>? _unitEmojis;

  Future<void> loadAll() async {
    await Future.wait([
      _loadUnits(),
      _loadProgression(),
      _loadCorpTracks(),
      _loadUnitEmojis(),
    ]);
  }

  Future<void> _loadUnits() async {
    final raw = await _content.loadString('lessons.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _units = map.entries
        .map((e) => LessonUnit.fromJson(e.key, e.value as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.unit.compareTo(b.unit));
  }

  Future<void> _loadProgression() async {
    final raw = await _content.loadString('unit_progression.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _progression = map.map(
      (k, v) => MapEntry(k, UnitCurriculumMeta.fromJson(k, v as Map<String, dynamic>)),
    );
  }

  Future<void> _loadCorpTracks() async {
    final raw = await _content.loadString('corp_tracks.json');
    final list = jsonDecode(raw) as List;
    _corpTracks = list.map((e) => CorpTrack.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _loadUnitEmojis() async {
    final raw = await _content.loadString('unit_emojis.json');
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
  /// app's "Todo o Conteúdo" grouping).
  Map<String, List<LessonUnit>> groupedByBook() {
    final result = <String, List<LessonUnit>>{};
    for (final u in units) {
      result.putIfAbsent(u.book, () => []).add(u);
    }
    return result;
  }
}
