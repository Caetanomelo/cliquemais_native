import 'text_normalize.dart';

/// Result of scoring a spoken transcript against a target phrase, VPC-style
/// (0-100 integer percentage plus an exact-match flag).
class VpcScoreResult {
  final int score;
  final bool exact;
  const VpcScoreResult({required this.score, required this.exact});
}

/// Unifies Drive Mode's `_scoreWords` (index.html:3983) and VPC's
/// `_scoreWords`/`_exactMatch` (decoded_app.html:8261-8276) — the source
/// itself notes they're "the same algorithm". VPC's normalization
/// (NFD accent-folding via `_normText`) is used for both, since it is
/// strictly more correct; Drive Mode's raw 0.0-1.0 fraction and 0.40
/// threshold, and VPC's 0-100 percentage and exact-match gating, are
/// both preserved as-is.
class ScoringService {
  /// Drive Mode: raw fraction (0.0-1.0) of target words matched by the
  /// spoken words. Threshold for auto-advance is 0.40 (index.html:4313).
  static double driveScore(String transcript, String phraseEn) {
    final tWords = _wordsVpc(phraseEn);
    final uWords = _wordsVpc(transcript);
    if (tWords.isEmpty) return 0;
    final tSet = tWords.toSet();
    var matched = 0;
    for (final w in uWords) {
      if (tSet.contains(w)) matched++;
    }
    return matched / tWords.length;
  }

  /// VPC: 0-100 integer percentage of target words matched.
  static int vpcWordScore(String target, String spoken) {
    final tWords = _wordsVpc(target);
    final sWords = _wordsVpc(spoken);
    if (tWords.isEmpty) return 0;
    final tSet = tWords.toSet();
    var matched = 0;
    for (final w in sWords) {
      if (tSet.contains(w)) matched++;
    }
    final pct = (matched / tWords.length * 100).round();
    return pct > 100 ? 100 : pct;
  }

  /// VPC: normalized full-phrase equality (case/accent/punctuation-insensitive).
  static bool vpcExactMatch(String target, String spoken) {
    return _normVpcFull(target) == _normVpcFull(spoken);
  }

  /// Convenience: computes both VPC score and exact-match in one call,
  /// mirroring `pendingScore={score:_scoreWords(...),spoken,exact:_exactMatch(...)}`.
  static VpcScoreResult scoreVpc(String target, String spoken) {
    return VpcScoreResult(
      score: vpcWordScore(target, spoken),
      exact: vpcExactMatch(target, spoken),
    );
  }

  static String _normVpcFull(String s) => TextNormalize.normVpc(s);

  static List<String> _wordsVpc(String s) {
    return _normVpcFull(s).split(' ').where((w) => w.length > 1).toList();
  }
}
