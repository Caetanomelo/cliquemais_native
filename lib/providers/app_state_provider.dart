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
  late final PersistenceService persistence;
  late final CurriculumProgressService curriculumProgress;
  late final PracticeProgressService practiceProgress;
  final RemoteContentService remoteContent = RemoteContentService();
  late final UnitDataRepository unitData;
  late final CurriculumRepository curriculum;
  late final AiContentRepository aiContent;
  final TtsService tts = TtsService();
  final SpeechService speech = SpeechService();
  final ChimeService chime = ChimeService();
  final PushService push = PushService();
  late final CloudTtsService cloudTts;
  late final AiTutorService aiTutor;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    persistence = await PersistenceService.create();
    curriculumProgress = await CurriculumProgressService.create();
    practiceProgress = await PracticeProgressService.create();
    cloudTts = CloudTtsService(fallback: tts);
    aiTutor = AiTutorService();
    unitData = UnitDataRepository(content: remoteContent);
    curriculum = CurriculumRepository(content: remoteContent);
    aiContent = AiContentRepository(content: remoteContent);
    await unitData.loadAll();
    await curriculum.loadAll();
    await aiContent.loadAll();
    await speech.init();
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
    chime.dispose();
    super.dispose();
  }
}
