import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/dashboard_stats.dart';
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
    CloudTtsService? cloudTts,
    AiTutorService? aiTutor,
    PronunciationAssessmentService? pronunciation,
    UnitDataRepository? unitData,
    CurriculumRepository? curriculum,
    AiContentRepository? aiContent,
    PersistenceService? persistence,
    CurriculumProgressService? curriculumProgress,
    PracticeProgressService? practiceProgress,
  })  : remoteContent = remoteContent ?? RemoteContentService(),
        tts = tts ?? TtsService(),
        speech = speech ?? SpeechService(),
        chime = chime ?? ChimeService(),
        push = push ?? PushService(),
        _seedCloudTts = cloudTts,
        _seedAiTutor = aiTutor,
        _seedPronunciation = pronunciation,
        _seedUnitData = unitData,
        _seedCurriculum = curriculum,
        _seedAiContent = aiContent,
        _seedPersistence = persistence,
        _seedCurriculumProgress = curriculumProgress,
        _seedPracticeProgress = practiceProgress;

  final RemoteContentService remoteContent;
  final TtsService tts;
  final SpeechService speech;
  final ChimeService chime;
  final PushService push;

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

  late final PersistenceService persistence;
  late final CurriculumProgressService curriculumProgress;
  late final PracticeProgressService practiceProgress;
  late final UnitDataRepository unitData;
  late final CurriculumRepository curriculum;
  late final AiContentRepository aiContent;
  late final CloudTtsService cloudTts;
  late final AiTutorService aiTutor;
  late final PronunciationAssessmentService pronunciation;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    cloudTts = _seedCloudTts ?? CloudTtsService(fallback: tts);
    aiTutor = _seedAiTutor ?? AiTutorService();
    pronunciation = _seedPronunciation ?? PronunciationAssessmentService();
    unitData = _seedUnitData ?? UnitDataRepository(content: remoteContent);
    curriculum = _seedCurriculum ?? CurriculumRepository(content: remoteContent);
    aiContent = _seedAiContent ?? AiContentRepository(content: remoteContent);

    // None of these depend on each other, so kick them all off together
    // instead of chaining sequential awaits — the persistence-box opens
    // (disk I/O) run alongside the content loads (network) and the speech
    // plugin init (platform channel), shaving real time off cold boot.
    final persistenceFuture = _seedPersistence != null
        ? Future.value(_seedPersistence)
        : PersistenceService.create();
    final curriculumProgressFuture = _seedCurriculumProgress != null
        ? Future.value(_seedCurriculumProgress)
        : CurriculumProgressService.create();
    final practiceProgressFuture = _seedPracticeProgress != null
        ? Future.value(_seedPracticeProgress)
        : PracticeProgressService.create();
    await Future.wait([
      unitData.loadAll(),
      curriculum.loadAll(),
      aiContent.loadAll(),
      speech.init(),
    ]);
    persistence = await persistenceFuture;
    curriculumProgress = await curriculumProgressFuture;
    practiceProgress = await practiceProgressFuture;

    _ready = true;
    notifyListeners();
    // Fire-and-forget: push permission/token registration must never block
    // or fail boot.
    unawaited(push.register());
  }

  static const int dailyXpGoal = 50;

  int get todayXp => persistence.todayXp;
  int get totalXp => persistence.totalXp;
  int get weekXp => persistence.weekXp;
  int get streakDays => persistence.streakDays;
  bool get hasSession => persistence.hasSession;
  bool get introDone => persistence.introDone;
  String get voiceGender => persistence.voiceGender;

  JourneyProgress get journeyProgress => computeJourneyProgress(curriculum, curriculumProgress);
  DomainProgress get domainProgress => computeDomainProgress(curriculum, curriculumProgress);

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
    super.dispose();
  }
}
