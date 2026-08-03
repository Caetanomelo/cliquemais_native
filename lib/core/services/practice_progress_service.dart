import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which [UnitMeta] units the student has finished a full Drive Mode
/// / Vocabulário practice session for. This is independent of
/// [CurriculumProgressService], which tracks the structured lesson
/// curriculum (keyed by `LessonUnit.id`) — Drive Mode and Vocabulário are
/// launched straight from `unit_meta.json` via the level/unit picker, so
/// their completion is tracked per raw unit number instead.
class PracticeProgressService {
  static const _kDrive = 'practice_drive_completed_units';
  static const _kVocab = 'practice_vocab_completed_units';

  final SharedPreferences _prefs;
  final Set<int> _driveCompleted;
  final Set<int> _vocabCompleted;

  PracticeProgressService._(this._prefs, this._driveCompleted, this._vocabCompleted);

  static Future<PracticeProgressService> create() async {
    final prefs = await SharedPreferences.getInstance();
    Set<int> read(String key) => (prefs.getStringList(key) ?? const []).map(int.parse).toSet();
    return PracticeProgressService._(prefs, read(_kDrive), read(_kVocab));
  }

  Set<int> get driveCompletedUnits => _driveCompleted;
  Set<int> get vocabCompletedUnits => _vocabCompleted;

  Future<void> markDriveUnitsComplete(List<int> units) async {
    if (!_addAll(_driveCompleted, units)) return;
    await _prefs.setStringList(_kDrive, _driveCompleted.map((e) => e.toString()).toList());
  }

  Future<void> markVocabUnitsComplete(List<int> units) async {
    if (!_addAll(_vocabCompleted, units)) return;
    await _prefs.setStringList(_kVocab, _vocabCompleted.map((e) => e.toString()).toList());
  }

  bool _addAll(Set<int> set, List<int> units) {
    var changed = false;
    for (final u in units) {
      if (set.add(u)) changed = true;
    }
    return changed;
  }
}
