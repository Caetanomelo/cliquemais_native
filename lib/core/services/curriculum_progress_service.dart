import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks per-unit/per-lesson completion for the full curriculum, mirroring
/// the web app's `state.progress[unitId][lessonIdx]`. Persisted as one JSON
/// value per unit (`curriculum_progress:<unitId>` -> completed lesson
/// indices) plus a completed-units set — completing a lesson in unit12 only
/// ever rewrites unit12's key, not every other unit's progress alongside it.
class CurriculumProgressService {
  static const _kProgressPrefix = 'curriculum_progress:';
  // Pre-migration key: a single JSON blob covering every unit. Read once on
  // create() to seed existing installs, then deleted — after that, only the
  // per-unit keys above are ever written.
  static const _kLegacyProgress = 'curriculum_progress';
  static const _kCompletedUnits = 'curriculum_completed_units';

  final SharedPreferences _prefs;
  final Map<String, Set<int>> _progress;
  final Set<String> _completedUnits;

  CurriculumProgressService._(this._prefs, this._progress, this._completedUnits);

  // Bumped on every actual mutation so screens can watch a single cheap
  // primitive (via context.select) instead of the whole AppStateProvider —
  // completion state spans arbitrary units/lessons, so there's no single
  // boolean/count that captures "did anything change" more precisely than
  // a version counter without deeper rework of the storage shape.
  int _version = 0;
  int get version => _version;

  static Future<CurriculumProgressService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final progress = <String, Set<int>>{};

    final legacyRaw = prefs.getString(_kLegacyProgress);
    if (legacyRaw != null) {
      // One-time migration: split the old single blob into per-unit keys,
      // then drop it so future boots skip straight to the fast path below.
      final map = jsonDecode(legacyRaw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final indices = (entry.value as List).map((e) => e as int).toSet();
        progress[entry.key] = indices;
        await prefs.setString('$_kProgressPrefix${entry.key}', jsonEncode(indices.toList()));
      }
      await prefs.remove(_kLegacyProgress);
    } else {
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_kProgressPrefix)) continue;
        final unitId = key.substring(_kProgressPrefix.length);
        final raw = prefs.getString(key);
        if (raw == null) continue;
        progress[unitId] = (jsonDecode(raw) as List).map((e) => e as int).toSet();
      }
    }

    final completedUnits = (prefs.getStringList(_kCompletedUnits) ?? const []).toSet();
    return CurriculumProgressService._(prefs, progress, completedUnits);
  }

  bool isLessonComplete(String unitId, int lessonIndex) =>
      _progress[unitId]?.contains(lessonIndex) ?? false;

  Set<int> completedLessonsForUnit(String unitId) => _progress[unitId] ?? const {};

  Future<void> markLessonComplete(String unitId, int lessonIndex) async {
    final set = _progress.putIfAbsent(unitId, () => {});
    if (!set.add(lessonIndex)) return;
    _version++;
    await _prefs.setString('$_kProgressPrefix$unitId', jsonEncode(set.toList()));
  }

  bool isUnitComplete(String unitId) => _completedUnits.contains(unitId);

  Future<void> markUnitComplete(String unitId) async {
    if (!_completedUnits.add(unitId)) return;
    _version++;
    await _prefs.setStringList(_kCompletedUnits, _completedUnits.toList());
  }

  double unitProgressFraction(String unitId, int totalLessons) {
    if (totalLessons == 0) return 0;
    return completedLessonsForUnit(unitId).length / totalLessons;
  }
}
