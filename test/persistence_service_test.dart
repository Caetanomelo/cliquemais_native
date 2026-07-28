import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cliquemais_native/core/services/persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PersistenceService', () {
    test('defaults when nothing stored yet', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await PersistenceService.create();
      expect(svc.todayXp, 0);
      expect(svc.totalXp, 0);
      expect(svc.hasSession, isFalse);
      expect(svc.introDone, isFalse);
      expect(svc.voiceGender, 'female');
    });

    test('addXp accumulates today and total on the same day', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await PersistenceService.create();
      await svc.addXp(5);
      await svc.addXp(8);
      expect(svc.todayXp, 13);
      expect(svc.totalXp, 13);
    });

    test('addXp rolls today_xp over on a new calendar day but keeps total', () async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final yKey =
          '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'today_xp': 40,
        'total_xp': 100,
        'last_xp_date': yKey,
      });
      final svc = await PersistenceService.create();
      expect(svc.todayXp, 40);
      await svc.addXp(10);
      expect(svc.todayXp, 10);
      expect(svc.totalXp, 110);
    });

    test('setVoiceGender / setHasSession / setIntroDone persist', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = await PersistenceService.create();
      await svc.setVoiceGender('male');
      await svc.setHasSession(true);
      await svc.setIntroDone(true);
      expect(svc.voiceGender, 'male');
      expect(svc.hasSession, isTrue);
      expect(svc.introDone, isTrue);
    });
  });
}
