import 'package:flutter_test/flutter_test.dart';
import 'package:cliquemais_native/core/services/scoring_service.dart';

void main() {
  group('ScoringService.driveScore', () {
    test('exact match scores 1.0', () {
      expect(ScoringService.driveScore('Hi, my name is Laura', 'Hi, my name is Laura'), 1.0);
    });

    test('partial word overlap scores a fraction', () {
      final score = ScoringService.driveScore('hi my name', 'Hi, my name is Laura');
      expect(score, closeTo(3 / 5, 0.001));
    });

    test('no overlap scores 0', () {
      expect(ScoringService.driveScore('completely different', 'Hi, my name is Laura'), 0.0);
    });

    test('is accent- and case-insensitive', () {
      final score = ScoringService.driveScore('VOCÊ ESTÁ bem', 'você está bem');
      expect(score, 1.0);
    });
  });

  group('ScoringService.scoreVpc', () {
    test('exact match: 100 score, exact=true', () {
      final r = ScoringService.scoreVpc('good morning', 'good morning');
      expect(r.score, 100);
      expect(r.exact, isTrue);
    });

    test('partial word overlap: exact=false, score < 100', () {
      final r = ScoringService.scoreVpc('good morning everyone', 'good morning');
      expect(r.exact, isFalse);
      expect(r.score, lessThan(100));
      expect(r.score, greaterThan(0));
    });

    test('accented spoken text can still exact-match ascii target', () {
      final r = ScoringService.scoreVpc('cafe', 'café');
      expect(r.exact, isTrue);
    });

    test('completely wrong answer scores 0 and is not exact', () {
      final r = ScoringService.scoreVpc('good morning', 'xyz');
      expect(r.score, 0);
      expect(r.exact, isFalse);
    });
  });
}
