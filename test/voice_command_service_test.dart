import 'package:flutter_test/flutter_test.dart';
import 'package:cliquemais_native/core/services/voice_command_service.dart';

void main() {
  group('VoiceCommandService.match', () {
    test('exact alias match returns high confidence', () {
      final m = VoiceCommandService.match('next');
      expect(m, isNotNull);
      expect(m!.intent, VoiceIntent.next);
      expect(m.confidence, 1.0);
      expect(m.isHigh, isTrue);
    });

    test('Portuguese alias resolves to the same intent', () {
      final m = VoiceCommandService.match('próximo');
      expect(m?.intent, VoiceIntent.next);
    });

    test('prefix match scores below exact but above threshold', () {
      final m = VoiceCommandService.match('repeat that please');
      expect(m, isNotNull);
      expect(m!.intent, VoiceIntent.repeat);
      expect(m.confidence, lessThan(1.0));
      expect(m.confidence, greaterThanOrEqualTo(VoiceCommandService.thresholdAccept));
    });

    test('unrelated transcript returns null (below threshold)', () {
      final m = VoiceCommandService.match('the quick brown fox jumps over the lazy dog');
      expect(m, isNull);
    });

    test('empty/null transcript returns null', () {
      expect(VoiceCommandService.match(''), isNull);
      expect(VoiceCommandService.match(null), isNull);
    });

    test('exit and confirm resolve distinctly', () {
      expect(VoiceCommandService.match('quit')?.intent, VoiceIntent.exit);
      expect(VoiceCommandService.match('yes')?.intent, VoiceIntent.confirm);
    });
  });
}
