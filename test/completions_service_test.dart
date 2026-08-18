import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:cliquemais_native/core/services/auth_service.dart';
import 'package:cliquemais_native/core/services/completions_service.dart';

// AuthService.isLoggedIn/currentUser normally read the live Supabase client
// (only reachable after AuthService.init() against a real project), so a
// fake standing in for "logged in, but with no resolvable user id" is the
// simplest way to exercise CompletionsService's queueing logic without a
// network dependency: currentUser==null makes _writeToSupabase() return
// false deterministically (no Supabase singleton access, no exception to
// catch), which is exactly the same code path a real offline write failure
// takes.
class _FakeAuthService extends AuthService {
  final bool loggedIn;
  _FakeAuthService(this.loggedIn);
  @override
  bool get isLoggedIn => loggedIn;
  @override
  User? get currentUser => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompletionsService', () {
    test('record() is a no-op when logged out, matching web Auth.recordCompletion', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await CompletionsService.create(_FakeAuthService(false));
      await svc.record(module: 'drive_mode', contentId: 'drive:1', unit: 0, domain: 'pronunciation');
      expect(svc.isCompleted('drive:1'), isFalse);
    });

    test('record() caches locally and queues the write when logged in but offline', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await CompletionsService.create(_FakeAuthService(true));
      await svc.record(module: 'vocab_lab', contentId: 'vocab:42', unit: 3, domain: 'vocabulary');
      expect(svc.isCompleted('vocab:42'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('content_completions_local_ids'), ['vocab:42']);
      expect(prefs.getStringList('content_completions_pending'), hasLength(1));
    });

    test('record() is idempotent for the same content_id', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await CompletionsService.create(_FakeAuthService(true));
      await svc.record(module: 'drive_mode', contentId: 'drive:7', unit: 1, domain: 'pronunciation');
      await svc.record(module: 'drive_mode', contentId: 'drive:7', unit: 1, domain: 'pronunciation');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('content_completions_pending'), hasLength(1));
    });

    test('a pending write from a previous session survives create() and stays queued while still offline', () async {
      SharedPreferences.setMockInitialValues({
        'content_completions_local_ids': ['drive:9'],
        'content_completions_pending': [
          '{"module":"drive_mode","contentId":"drive:9","unit":2,"domain":"pronunciation","xp":5}',
        ],
      });
      final svc = await CompletionsService.create(_FakeAuthService(true));
      expect(svc.isCompleted('drive:9'), isTrue);
      await svc.flushPending();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('content_completions_pending'), hasLength(1));
    });
  });
}
