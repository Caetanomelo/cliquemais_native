import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../core/dashboard_stats.dart';
import '../core/services/auth_service.dart';
import '../core/services/completions_service.dart';
import '../core/services/persistence_service.dart';
import '../core/services/tts_service.dart';
import '../core/services/speech_service.dart';
import '../core/services/chime_service.dart';
import '../core/services/curriculum_progress_service.dart';
import '../core/services/practice_progress_service.dart';
import '../core/services/cloud_tts_service.dart';
import '../core/services/ai_tutor_service.dart';
import '../core/services/pronunciation_assessment_service.dart';
import '../core/services/push_service.dart';
import '../core/services/remote_content_service.dart';
import '../data/repositories/unit_data_repository.dart';
import '../data/repositories/curriculum_repository.dart';
import '../data/repositories/ai_content_repository.dart';

/// Root app state: wires all services together and exposes the bits screens
/// need reactively (XP, session flags, voice gender, curriculum data).
/// A single ChangeNotifier was right-sized for Phase 1's 4 screens; Phase 2
/// keeps it since the curriculum/tutor/TTS pieces are still simple lookups
/// and network calls, not shared mutable UI state.
class AppStateProvider extends ChangeNotifier {
  // Every dependency is injectable so tests (and the boot flow itself) can
  // swap in fakes instead of hitting real network/disk/platform channels —
  // previously each service was `new`'d up inline here, so nothing about
  // this class could be exercised without the real implementations. Screens
  // only ever go through the single AppStateProvider instance (via
  // provider), so this is the one seam that needed it.
  AppStateProvider({
    RemoteContentService? remoteContent,
    TtsService? tts,
    SpeechService? speech,
    ChimeService? chime,
    PushService? push,
    AuthService? auth,
    CloudTtsService? cloudTts,
    AiTutorService? aiTutor,
    PronunciationAssessmentService? pronunciation,
    UnitDataRepository? unitData,
    CurriculumRepository? curriculum,
    AiContentRepository? aiContent,
    PersistenceService? persistence,
    CurriculumProgressService? curriculumProgress,
    PracticeProgressService? practiceProgress,
    CompletionsService? completions,
  }) : remoteContent = remoteContent ?? RemoteContentService(),
       tts = tts ?? TtsService(),
       speech = speech ?? SpeechService(),
       chime = chime ?? ChimeService(),
       push = push ?? PushService(),
       auth = auth ?? AuthService(),
       _seedCloudTts = cloudTts,
       _seedAiTutor = aiTutor,
       _seedPronunciation = pronunciation,
       _seedUnitData = unitData,
       _seedCurriculum = curriculum,
       _seedAiContent = aiContent,
       _seedPersistence = persistence,
       _seedCurriculumProgress = curriculumProgress,
       _seedPracticeProgress = practiceProgress,
       _seedCompletions = completions;

  final RemoteContentService remoteContent;
  final TtsService tts;
  final SpeechService speech;
  final ChimeService chime;
  final PushService push;
  final AuthService auth;

  StreamSubscription<AuthState>? _authSub;

  // Built (or adopted from the constructor) in init(), since the real
  // implementations need an async factory (persistence/progress) or depend
  // on another injected service (cloudTts on tts, the repositories on
  // remoteContent) that isn't known until the constructor body has run.
  final CloudTtsService? _seedCloudTts;
  final AiTutorService? _seedAiTutor;
  final PronunciationAssessmentService? _seedPronunciation;
  final UnitDataRepository? _seedUnitData;
  final CurriculumRepository? _seedCurriculum;
  final AiContentRepository? _seedAiContent;
  final PersistenceService? _seedPersistence;
  final CurriculumProgressService? _seedCurriculumProgress;
  final PracticeProgressService? _seedPracticeProgress;
  final CompletionsService? _seedCompletions;

  late final PersistenceService persistence;
  // Not `final` — setCourseLanguage() recreates these three for the new
  // language so switching course mid-session can't show (or silently merge
  // into) another course's progress.
  late CurriculumProgressService curriculumProgress;
  late PracticeProgressService practiceProgress;
  late CompletionsService completions;
  late final UnitDataRepository unitData;
  late final CurriculumRepository curriculum;
  late final AiContentRepository aiContent;
  late final CloudTtsService cloudTts;
  late final AiTutorService aiTutor;
  late final PronunciationAssessmentService pronunciation;

  bool _ready = false;
  bool get ready => _ready;

  // init() can be retried from SplashScreen's "try again" button after a
  // failed attempt (e.g. no network on cold boot — RemoteContentService no
  // longer has a disk-cache fallback to quietly succeed from). These guards
  // keep a retry from re-running the one-time, non-idempotent parts: the
  // `late final` service fields would throw LateInitializationError if
  // reassigned, and auth.init() calls Supabase.initialize(), which throws
  // if called a second time.
  bool _servicesReady = false;
  bool _authInited = false;

  // Fase 8: real per-domain/XP/streak analytics, fetched live from Supabase
  // (see CompletionsService.fetchAnalyticsSummary). null until the first
  // successful fetch after login — every getter below falls back to the
  // local-only figures until then, same as the web dashboard's behavior
  // before _refreshRealAnalytics() resolves.
  DomainTotals? _domainTotals;
  AnalyticsSummary? _analyticsSummary;

  Future<void> init() async {
    if (!_servicesReady) {
      cloudTts = _seedCloudTts ?? CloudTtsService(fallback: tts);
      aiTutor = _seedAiTutor ?? AiTutorService();
      pronunciation = _seedPronunciation ?? PronunciationAssessmentService();
      unitData = _seedUnitData ?? UnitDataRepository(content: remoteContent);
      curriculum =
          _seedCurriculum ?? CurriculumRepository(content: remoteContent);
      aiContent = _seedAiContent ?? AiContentRepository(content: remoteContent);
    }

    // unitData/curriculum content doesn't depend on course language (both
    // ship every language's content in one payload, resolved client-side —
    // see Lesson/CorpTrack.forLanguage), so they, persistence, and auth can
    // all start immediately, independent of each other.
    // Only created (and only assigned to the `late final persistence` field
    // below) on the first attempt — a retry after a failed attempt must not
    // touch it again.
    final Future<PersistenceService>? persistenceFuture = _servicesReady
        ? null
        : (_seedPersistence != null ? Future.value(_seedPersistence) : PersistenceService.create());
    final unitDataFuture = unitData.loadAll();
    final curriculumFuture = curriculum.loadAll();
    // auth.init() (Supabase.initialize() + session restore) must resolve
    // before init() returns and _ready flips true — SplashScreen reads
    // isLoggedIn immediately after boot to decide whether to skip Hero+Login,
    // and that read was unreliable when auth.init() only ran inside the
    // fire-and-forget _initAuth() below, after _ready was already set.
    // Guarded so a retry after a failed attempt can't call it twice —
    // Supabase.initialize() throws on a second call.
    final authFuture = _authInited ? Future<void>.value() : auth.init().then((_) => _authInited = true);

    // aiContent, curriculumProgress, practiceProgress, and completions all
    // need the course language up front (a `?language=` query param, or a
    // key/column to scope local storage and Supabase reads by), so they
    // wait for persistenceFuture to resolve before kicking off — then join
    // the same final wait as the language-independent loads above.
    if (persistenceFuture != null) {
      persistence = await persistenceFuture;
      _servicesReady = true;
    }
    final lang = persistence.courseLanguage;
    final aiContentFuture = aiContent.loadAll(lang, persistence.nativeLanguage);
    final curriculumProgressFuture = _seedCurriculumProgress != null
        ? Future.value(_seedCurriculumProgress)
        : CurriculumProgressService.create(lang);
    final practiceProgressFuture = _seedPracticeProgress != null
        ? Future.value(_seedPracticeProgress)
        : PracticeProgressService.create(lang);
    final completionsFuture = _seedCompletions != null
        ? Future.value(_seedCompletions)
        : CompletionsService.create(auth, lang);

    await Future.wait([unitDataFuture, curriculumFuture, authFuture, aiContentFuture]);
    curriculumProgress = await curriculumProgressFuture;
    practiceProgress = await practiceProgressFuture;
    completions = await completionsFuture;
    _domainTotals = computeDomainTotals(curriculum, unitData);

    _ready = true;
    notifyListeners();
    // Fire-and-forget: push permission/token registration must never block
    // or fail boot.
    unawaited(push.register());
    // auth.init() already ran above — this only wires up the listener and
    // does the post-boot flush/refresh, it must never call auth.init() again
    // (Supabase.initialize() cannot be called twice).
    unawaited(_initAuth());
  }

  Future<void> _initAuth() async {
    // auth.init() resolves after CompletionsService.create() already tried
    // (and no-op'd, since isLoggedIn was still false at that point) its own
    // startup flush — retry now that a session may have just been restored,
    // and again on every future sign-in so anything queued while logged out
    // gets pushed as soon as there's somewhere to push it to.
    unawaited(completions.flushPending());
    unawaited(refreshRealAnalytics());
    unawaited(_syncCourseLanguageFromProfile());
    unawaited(_syncNativeLanguageFromProfile());
    _authSub = auth.onAuthStateChange.listen((_) {
      unawaited(completions.flushPending());
      unawaited(refreshRealAnalytics());
      unawaited(_syncCourseLanguageFromProfile());
      unawaited(_syncNativeLanguageFromProfile());
      notifyListeners();
    });
    notifyListeners();
  }

  /// The `profiles.target_language` column is the source of truth once
  /// logged in (it's shared with the web app, and may have been set there);
  /// local persistence is only the pre-login/offline default. Runs after
  /// every sign-in (including the initial session restore) so a device that
  /// never opened Settings on this course language still gets it right.
  Future<void> _syncCourseLanguageFromProfile() async {
    if (!isLoggedIn) return;
    final profile = await auth.getProfile();
    final remote = profile?['target_language'] as String?;
    if (remote != null && remote != persistence.courseLanguage) {
      await setCourseLanguage(remote);
    }
  }

  /// Espelha _syncCourseLanguageFromProfile, mas sem reload de conteudo --
  /// curriculum/corp-tracks ja vem inteiros do backend e resolvem
  /// client-side via forPair, entao so quem muda de idioma-alvo precisa
  /// refetch.
  Future<void> _syncNativeLanguageFromProfile() async {
    if (!isLoggedIn) return;
    final profile = await auth.getProfile();
    final remote = profile?['native_language'] as String?;
    if (remote != null && remote != persistence.nativeLanguage) {
      await persistence.setNativeLanguage(remote);
      notifyListeners();
    }
  }

  /// Re-fetches the Analytics Core numbers from Supabase — called on login
  /// and on every auth state change; also safe to call from a pull-to-refresh
  /// (see DashboardScreen) after finishing a practice session, since
  /// completions.record() itself doesn't push a live update here.
  Future<void> refreshRealAnalytics() async {
    if (!isLoggedIn) {
      if (_analyticsSummary != null) {
        _analyticsSummary = null;
        notifyListeners();
      }
      return;
    }
    final summary = await completions.fetchAnalyticsSummary();
    _analyticsSummary = summary;
    notifyListeners();
  }

  bool get isLoggedIn => auth.isLoggedIn;

  static const int dailyXpGoal = 50;

  int get todayXp => persistence.todayXp;
  int get totalXp => persistence.totalXp;
  int get weekXp => persistence.weekXp;
  int get streakDays => persistence.streakDays;
  bool get hasSession => persistence.hasSession;
  bool get introDone => persistence.introDone;
  String get voiceGender => persistence.voiceGender;
  String get courseLanguage => persistence.courseLanguage;
  String get nativeLanguage => persistence.nativeLanguage;

  JourneyProgress get journeyProgress =>
      computeJourneyProgress(curriculum, curriculumProgress);
  DomainProgress get domainProgress =>
      computeDomainProgress(curriculum, curriculumProgress);

  // Fase 8: real per-item Analytics Core figures. Fall back to the local,
  // curriculum-block/persistence-based numbers above until the first
  // Supabase fetch resolves (or if it fails/user is logged out) — same
  // graceful-degradation shape as the web dashboard's _refreshRealAnalytics.
  DomainProgress get realDomainProgress {
    final summary = _analyticsSummary;
    final totals = _domainTotals;
    if (summary == null || totals == null) return domainProgress;
    return domainProgressFromCounts(totals, summary.domainCounts);
  }

  int get realStreakDays => _analyticsSummary?.streak ?? streakDays;
  int get realWeekXp => _analyticsSummary?.xpWeek ?? weekXp;
  int get realTotalXp => _analyticsSummary?.xpTotal ?? totalXp;

  Future<void> addXp(int amount) async {
    await persistence.addXp(amount);
    notifyListeners();
  }

  Future<void> markDriveUnitsComplete(List<int> units) async {
    await practiceProgress.markDriveUnitsComplete(units);
    notifyListeners();
  }

  Future<void> markVocabUnitsComplete(List<int> units) async {
    await practiceProgress.markVocabUnitsComplete(units);
    notifyListeners();
  }

  Future<void> markSessionStarted() async {
    await persistence.setHasSession(true);
    notifyListeners();
  }

  Future<void> markIntroDone() async {
    await persistence.setIntroDone(true);
    notifyListeners();
  }

  Future<void> setVoiceGender(String gender) async {
    await persistence.setVoiceGender(gender);
    notifyListeners();
  }

  /// Reloads AI Tutor content for the new language (it's fetched with a
  /// `?language=` query param, unlike curriculum/corp-track content which
  /// ships every language in one payload and resolves client-side). Also
  /// pushes the choice to `profiles.target_language` when logged in, so it
  /// carries over to the web app and other devices.
  Future<void> setCourseLanguage(String lang) async {
    await persistence.setCourseLanguage(lang);
    if (isLoggedIn) {
      unawaited(auth.updateProfile(targetLanguage: lang));
    }
    await aiContent.loadAll(lang, persistence.nativeLanguage);
    // curriculumProgress/practiceProgress/completions cache their state in
    // memory per language at load time (see Fase 5) — reload them for the
    // new course so its progress doesn't mix with the previous language's.
    curriculumProgress = await CurriculumProgressService.create(lang);
    practiceProgress = await PracticeProgressService.create(lang);
    completions = await CompletionsService.create(auth, lang);
    notifyListeners();
  }

  /// Espelha setCourseLanguage, mas sem reload de lesson/corp_track --
  /// esse conteudo ja chega com as 3 traducoes num payload so, resolvido no
  /// client via forPair. aiContent e' diferente: e' buscado do servidor
  /// filtrado por native_language (ai_tutor_modes), entao precisa recarregar
  /// aqui tambem ou o Tutor IA continuaria respondendo no idioma nativo
  /// antigo ate o proximo boot.
  Future<void> setNativeLanguage(String lang) async {
    await persistence.setNativeLanguage(lang);
    if (isLoggedIn) {
      unawaited(auth.updateProfile(nativeLanguage: lang));
    }
    await aiContent.loadAll(persistence.courseLanguage, lang);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(tts.stop());
    unawaited(speech.cancel());
    cloudTts.dispose();
    aiTutor.dispose();
    pronunciation.dispose();
    push.dispose();
    chime.dispose();
    remoteContent.dispose();
    unawaited(_authSub?.cancel());
    super.dispose();
  }
}
