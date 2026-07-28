import 'package:shared_preferences/shared_preferences.dart';

/// Wraps shared_preferences with the Phase-1 key set. Mirrors a subset of
/// the web app's localStorage keys — `cp_checkpoint`/`_CP_KEY` is
/// deliberately NOT ported (it existed only to bridge the iframe's
/// null-origin localStorage isolation, which doesn't exist natively).
class PersistenceService {
  static const _kVoiceGender = 'dm_voice_gender';
  static const _kIntroDone = 'dm_intro_done';
  static const _kHasSession = 'has_session';
  static const _kSchemaVersion = 'schema_version';
  static const _kTodayXp = 'today_xp';
  static const _kTotalXp = 'total_xp';
  static const _kLastXpDate = 'last_xp_date';
  static const _kWeekXp = 'week_xp';
  static const _kLastXpWeek = 'last_xp_week';
  static const _kStreakDays = 'streak_days';
  static const _kLastActiveDate = 'last_active_date';

  static const currentSchemaVersion = '1';

  final SharedPreferences _prefs;
  PersistenceService(this._prefs);

  static Future<PersistenceService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PersistenceService(prefs);
  }

  String get voiceGender => _prefs.getString(_kVoiceGender) ?? 'female';
  Future<void> setVoiceGender(String v) => _prefs.setString(_kVoiceGender, v);

  bool get introDone => _prefs.getBool(_kIntroDone) ?? false;
  Future<void> setIntroDone(bool v) => _prefs.setBool(_kIntroDone, v);

  bool get hasSession => _prefs.getBool(_kHasSession) ?? false;
  Future<void> setHasSession(bool v) => _prefs.setBool(_kHasSession, v);

  String get schemaVersion => _prefs.getString(_kSchemaVersion) ?? currentSchemaVersion;
  Future<void> setSchemaVersion(String v) => _prefs.setString(_kSchemaVersion, v);

  int get todayXp => _prefs.getInt(_kTodayXp) ?? 0;
  int get totalXp => _prefs.getInt(_kTotalXp) ?? 0;
  int get weekXp => _prefs.getInt(_kWeekXp) ?? 0;
  int get streakDays => _prefs.getInt(_kStreakDays) ?? 0;
  String? get lastXpDate => _prefs.getString(_kLastXpDate);

  /// Adds [amount] XP, rolling `today_xp`/`week_xp` over on calendar/ISO-week
  /// boundaries and bumping the daily streak when XP lands on a new day.
  Future<void> addXp(int amount) async {
    final today = _todayKey();
    var todayTotal = todayXp;
    if (lastXpDate != today) {
      todayTotal = 0;
      await _bumpStreak(today);
    }
    todayTotal += amount;
    final total = totalXp + amount;

    final week = _weekKey();
    var weekTotal = weekXp;
    if (_prefs.getString(_kLastXpWeek) != week) {
      weekTotal = 0;
    }
    weekTotal += amount;

    await _prefs.setInt(_kTodayXp, todayTotal);
    await _prefs.setInt(_kTotalXp, total);
    await _prefs.setString(_kLastXpDate, today);
    await _prefs.setInt(_kWeekXp, weekTotal);
    await _prefs.setString(_kLastXpWeek, week);
  }

  /// Increments the streak when today is exactly one day after the last
  /// active day; resets to 1 on a gap or first-ever activity.
  Future<void> _bumpStreak(String today) async {
    final last = _prefs.getString(_kLastActiveDate);
    final gapDays = last == null ? null : DateTime.parse(today).difference(DateTime.parse(last)).inDays;
    final next = (gapDays == 1) ? streakDays + 1 : 1;
    await _prefs.setInt(_kStreakDays, next);
    await _prefs.setString(_kLastActiveDate, today);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Coarse year+week bucket (not strict ISO-8601) — good enough to roll
  /// `week_xp` over roughly weekly without pulling in a date-utils package.
  String _weekKey() {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return '${now.year}-W${(dayOfYear / 7).floor()}';
  }
}
