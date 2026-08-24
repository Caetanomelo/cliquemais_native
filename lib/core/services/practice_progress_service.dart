import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which [UnitMeta] units the student has finished a full Drive Mode
/// / Vocabulário practice session for. This is independent of
/// [CurriculumProgressService], which tracks the structured lesson
/// curriculum (keyed by `LessonUnit.id`) — Drive Mode and Vocabulário are
/// launched straight from `unit_meta.json` via the level/unit picker, so
/// their completion is tracked per raw unit number instead. Keys are scoped
/// by course language (`practice_drive_completed_units:<lang>`), same as
/// [CurriculumProgressService], so switching course language doesn't mix
/// completion between them.
class PracticeProgressService {
  static const _kDrive = 'practice_drive_completed_units';
  static const _kVocab = 'practice_vocab_completed_units';

  final SharedPreferences _prefs;
  final String _lang;
  final Set<int> _driveCompleted;
  final Set<int> _vocabCompleted;

  PracticeProgressService._(this._prefs, this._lang, this._driveCompleted, this._vocabCompleted);

  static Future<PracticeProgressService> create(String courseLanguage) async {
    final prefs = await SharedPreferences.getInstance();

    Future<Set<int>> read(String base) async {
      final scopedKey = '$base:$courseLanguage';
      final scoped = prefs.getStringList(scopedKey);
      if (scoped != null) return scoped.map(int.parse).toSet();
      // Pre-language-rollout data (English-only) had no suffix — migrate it
      // once, same non-destructive-then-write technique used elsewhere in
      // this rollout. Only relevant for 'en'.
      if (courseLanguage != 'en') return {};
      final legacy = prefs.getStringList(base);
      if (legacy == null) return {};
      await prefs.setStringList(scopedKey, legacy);
      await prefs.remove(base);
      return legacy.map(int.parse).toSet();
    }

    final drive = await read(_kDrive);
    final vocab = await read(_kVocab);
    return PracticeProgressService._(prefs, courseLanguage, drive, vocab);
  }

  Set<int> get driveCompletedUnits => _driveCompleted;
  Set<int> get vocabCompletedUnits => _vocabCompleted;

  Future<void> markDriveUnitsComplete(List<int> units) async {
    if (!_addAll(_driveCompleted, units)) return;
    await _prefs.setStringList('$_kDrive:$_lang', _driveCompleted.map((e) => e.toString()).toList());
  }

  Future<void> markVocabUnitsComplete(List<int> units) async {
    if (!_addAll(_vocabCompleted, units)) return;
    await _prefs.setStringList('$_kVocab:$_lang', _vocabCompleted.map((e) => e.toString()).toList());
  }

  bool _addAll(Set<int> set, List<int> units) {
    var changed = false;
    for (final u in units) {
      if (set.add(u)) changed = true;
    }
    return changed;
  }
}
