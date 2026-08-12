import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Plays the pre-rendered chime assets (synthesized offline to match the
/// web app's Web-Audio oscillator recipe: success = C5/E5/G5 arpeggio,
/// fail = descending two-tone) — see `_playVpcChime`/`_playChime` in the
/// source apps. Pre-rendered assets avoid depending on a runtime audio
/// synthesis API, which Flutter has no first-party equivalent for.
class ChimeService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(bool success) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(success ? 'audio/chime_success.wav' : 'audio/chime_fail.wav'));
    } catch (e, st) {
      // Non-critical: a missing/broken audio backend shouldn't block scoring
      // flow, but still worth knowing about in Crashlytics as a non-fatal.
      unawaited(FirebaseCrashlytics.instance.recordError(e, st, reason: 'ChimeService.play failed', fatal: false));
    }
  }

  void dispose() {
    _player.dispose();
  }
}
