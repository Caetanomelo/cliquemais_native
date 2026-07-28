import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks per-unit/per-lesson completion for the full curriculum, mirroring
/// the web app's `state.progress[unitId][lessonIdx]`. Persisted as a single
/// JSON blob (unit id -> completed lesson indices) plus a completed-units set.
class CurriculumProgressService {
  static const _kProgress = 'curriculum_progress';
  static const _kCompletedUnits = 'curriculum_completed_units';

  final SharedPreferences _prefs;
  final Map<String, Set<int>> _progress;
  final Set<String> _completedUnits;

  CurriculumProgressService._(this._prefs, this._progress, this._completedUnits);

  static Future<CurriculumProgressService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kProgress);
    final progress = <String, Set<int>>{};
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        progress[entry.key] = (entry.value as List).map((e) => e as int).toSet();
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
    await _persistProgress();
  }

  bool isUnitComplete(String unitId) => _completedUnits.contains(unitId);

  Future<void> markUnitComplete(String unitId) async {
    if (!_completedUnits.add(unitId)) return;
    await _prefs.setStringList(_kCompletedUnits, _completedUnits.toList());
  }

  double unitProgressFraction(String unitId, int totalLessons) {
    if (totalLessons == 0) return 0;
    return completedLessonsForUnit(unitId).length / totalLessons;
  }

  Future<void> _persistProgress() async {
    final serializable = _progress.map((k, v) => MapEntry(k, v.toList()));
    await _prefs.setString(_kProgress, jsonEncode(serializable));
  }
}
