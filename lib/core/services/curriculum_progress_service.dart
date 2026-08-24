import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks per-unit/per-lesson completion for the full curriculum, mirroring
/// the web app's `state.progress[unitId][lessonIdx]`. Persisted as one JSON
/// value per unit (`curriculum_progress:<lang>:<unitId>` -> completed lesson
/// indices) plus a completed-units set, both scoped by course language so a
/// student's Spanish progress never mixes with their English progress —
/// completing a lesson in unit12 only ever rewrites unit12's key, not every
/// other unit's progress alongside it.
class CurriculumProgressService {
  static const _kProgressPrefix = 'curriculum_progress:';
  // Pre-language-rollout key: a single JSON blob covering every unit, from
  // before per-unit keys existed. Read once on create() to seed existing
  // installs, then deleted — after that, only the per-unit keys above are
  // ever written. Only relevant for 'en', the only language that existed
  // before this rollout.
  static const _kLegacyProgress = 'curriculum_progress';
  static const _kCompletedUnitsPrefix = 'curriculum_completed_units';

  final SharedPreferences _prefs;
  final String _lang;
  final Map<String, Set<int>> _progress;
  final Set<String> _completedUnits;

  CurriculumProgressService._(this._prefs, this._lang, this._progress, this._completedUnits);

  // Bumped on every actual mutation so screens can watch a single cheap
  // primitive (via context.select) instead of the whole AppStateProvider —
  // completion state spans arbitrary units/lessons, so there's no single
  // boolean/count that captures "did anything change" more precisely than
  // a version counter without deeper rework of the storage shape.
  int _version = 0;
  int get version => _version;

  static Future<CurriculumProgressService> create(String courseLanguage) async {
    final prefs = await SharedPreferences.getInstance();
    final progress = <String, Set<int>>{};
    final scopedPrefix = '$_kProgressPrefix$courseLanguage:';

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(scopedPrefix)) continue;
      final unitId = key.substring(scopedPrefix.length);
      final raw = prefs.getString(key);
      if (raw == null) continue;
      progress[unitId] = (jsonDecode(raw) as List).map((e) => e as int).toSet();
    }

    if (courseLanguage == 'en') {
      final legacyRaw = prefs.getString(_kLegacyProgress);
      if (legacyRaw != null) {
        // One-time migration: split the old single blob into per-unit,
        // per-language keys, then drop it so future boots skip straight to
        // the fast path above.
        final map = jsonDecode(legacyRaw) as Map<String, dynamic>;
        for (final entry in map.entries) {
          if (progress.containsKey(entry.key)) continue;
          final indices = (entry.value as List).map((e) => e as int).toSet();
          progress[entry.key] = indices;
          await prefs.setString('$scopedPrefix${entry.key}', jsonEncode(indices.toList()));
        }
        await prefs.remove(_kLegacyProgress);
      }
      // Pre-language-rollout per-unit keys (no language suffix at all) —
      // migrate any that survived the blob migration above (installs that
      // already had per-unit keys before this rollout).
      for (final key in prefs.getKeys().toList()) {
        if (!key.startsWith(_kProgressPrefix)) continue;
        final rest = key.substring(_kProgressPrefix.length);
        if (rest.contains(':')) continue; // already language-scoped
        if (progress.containsKey(rest)) continue;
        final raw = prefs.getString(key);
        if (raw == null) continue;
        progress[rest] = (jsonDecode(raw) as List).map((e) => e as int).toSet();
        await prefs.setString('$scopedPrefix$rest', raw);
        await prefs.remove(key);
      }
    }

    final scopedCompletedKey = '$_kCompletedUnitsPrefix:$courseLanguage';
    Set<String> completedUnits;
    final scopedCompleted = prefs.getStringList(scopedCompletedKey);
    if (scopedCompleted != null) {
      completedUnits = scopedCompleted.toSet();
    } else if (courseLanguage == 'en') {
      final legacy = prefs.getStringList(_kCompletedUnitsPrefix) ?? const [];
      completedUnits = legacy.toSet();
      if (legacy.isNotEmpty) {
        await prefs.setStringList(scopedCompletedKey, legacy);
        await prefs.remove(_kCompletedUnitsPrefix);
      }
    } else {
      completedUnits = {};
    }

    return CurriculumProgressService._(prefs, courseLanguage, progress, completedUnits);
  }

  bool isLessonComplete(String unitId, int lessonIndex) =>
      _progress[unitId]?.contains(lessonIndex) ?? false;

  Set<int> completedLessonsForUnit(String unitId) => _progress[unitId] ?? const {};

  Future<void> markLessonComplete(String unitId, int lessonIndex) async {
    final set = _progress.putIfAbsent(unitId, () => {});
    if (!set.add(lessonIndex)) return;
    _version++;
    await _prefs.setString('$_kProgressPrefix$_lang:$unitId', jsonEncode(set.toList()));
  }

  bool isUnitComplete(String unitId) => _completedUnits.contains(unitId);

  Future<void> markUnitComplete(String unitId) async {
    if (!_completedUnits.add(unitId)) return;
    _version++;
    await _prefs.setStringList('$_kCompletedUnitsPrefix:$_lang', _completedUnits.toList());
  }

  double unitProgressFraction(String unitId, int totalLessons) {
    if (totalLessons == 0) return 0;
    return completedLessonsForUnit(unitId).length / totalLessons;
  }
}
