/// Port of VoiceCommandRegistry (index.html:3635-3860) — Drive Mode's
/// local, offline command matcher. Pure string operations, no AI/network.
enum VoiceIntent { next, prev, repeat, pause, resume, exit, confirm, skip }

class VoiceCommandMatch {
  final VoiceIntent intent;
  final double confidence;
  final String alias;
  final String transcript;
  final bool isHigh;
  const VoiceCommandMatch({
    required this.intent,
    required this.confidence,
    required this.alias,
    required this.transcript,
    required this.isHigh,
  });
}

class _AliasEntry {
  final String raw;
  final String norm;
  final Set<String> wordSet;
  const _AliasEntry(this.raw, this.norm, this.wordSet);
}

class _RegistryEntry {
  final VoiceIntent intent;
  final List<_AliasEntry> aliases;
  const _RegistryEntry(this.intent, this.aliases);
}

class VoiceCommandService {
  static const double thresholdAccept = 0.55;
  static const double thresholdHigh = 0.85;

  static final Map<VoiceIntent, List<String>> _rawRegistry = {
    VoiceIntent.next: [
      'next', 'continue', 'go on', 'go ahead', 'move on',
      'next one', 'next phrase', 'next sentence', 'advance',
      'forward', 'keep going', 'proceed', 'seguinte', 'próximo',
      'continua', 'vamos',
    ],
    VoiceIntent.prev: [
      'back', 'previous', 'go back', 'before', 'last one',
      'previous phrase', 'repeat last', 'anterior', 'voltar',
      'volta',
    ],
    VoiceIntent.repeat: [
      'repeat', 'again', 'say again', 'one more time',
      'replay', 'play again', 'once more', 'repete',
      'repetir', 'de novo', 'mais uma vez', 'outra vez',
    ],
    VoiceIntent.pause: [
      'pause', 'stop', 'wait', 'hold on', 'hold',
      'pausa', 'para', 'espera',
    ],
    VoiceIntent.resume: [
      'resume', 'continue', 'start', 'go', 'play',
      'retomar', 'continuar',
    ],
    VoiceIntent.exit: [
      'exit', 'quit', 'close', 'end', 'stop drive mode',
      'leave', 'bye', 'finish', 'done', 'sair', 'fechar',
      'terminar',
    ],
    VoiceIntent.confirm: [
      'yes', 'ok', 'okay', 'correct', 'right', 'exactly',
      'sure', 'confirm', 'got it', 'sim', 'certo',
    ],
    VoiceIntent.skip: [
      'skip', 'pass', 'next please', 'skip this',
      'pula', 'passa',
    ],
  };

  static final List<_RegistryEntry> _registry = _rawRegistry.entries
      .map((e) => _RegistryEntry(
            e.key,
            e.value.map((alias) {
              final n = _normalise(alias);
              return _AliasEntry(alias, n, n.split(' ').where((w) => w.isNotEmpty).toSet());
            }).toList(),
          ))
      .toList();

  static String _normalise(String? str) {
    if (str == null || str.isEmpty) return '';
    var s = str.toLowerCase();
    s = s.replaceAll(RegExp(r'[à-åæ]'), 'a');
    s = s.replaceAll(RegExp(r'[è-ë]'), 'e');
    s = s.replaceAll(RegExp(r'[ì-ï]'), 'i');
    s = s.replaceAll(RegExp(r'[ò-öø]'), 'o');
    s = s.replaceAll(RegExp(r'[ù-ü]'), 'u');
    s = s.replaceAll('ç', 'c');
    s = s.replaceAll('ñ', 'n');
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }

  static double _scoreAlias(String tNorm, Set<String> tWordSet, _AliasEntry aEntry) {
    final aNorm = aEntry.norm;
    if (tNorm.isEmpty || aNorm.isEmpty) return 0;

    if (tNorm == aNorm) return 1.00;
    if (tNorm.startsWith(aNorm)) return 0.88;
    if (tNorm.contains(aNorm)) return 0.75;
    if (aNorm.contains(tNorm) && tNorm.length >= 3) return 0.65;

    final aWordSet = aEntry.wordSet;
    if (tWordSet.isEmpty || aWordSet.isEmpty) return 0;

    var matches = 0;
    for (final w in tWordSet) {
      if (aWordSet.contains(w)) matches++;
    }
    final longer = tWordSet.length > aWordSet.length ? tWordSet.length : aWordSet.length;
    final overlap = matches / longer;
    if (matches >= 1 && overlap >= 0.4) {
      return 0.50 + (overlap * 0.15);
    }
    return 0;
  }

  /// Returns the best-matching command, or null if below [thresholdAccept].
  static VoiceCommandMatch? match(String? transcript) {
    if (transcript == null || transcript.isEmpty) return null;

    final tNorm = _normalise(transcript);
    final tWordSet = tNorm.split(' ').where((w) => w.isNotEmpty).toSet();

    var bestScore = 0.0;
    VoiceIntent? bestIntent;
    String? bestAlias;

    outer:
    for (final entry in _registry) {
      for (final alias in entry.aliases) {
        final score = _scoreAlias(tNorm, tWordSet, alias);
        if (score > bestScore) {
          bestScore = score;
          bestIntent = entry.intent;
          bestAlias = alias.raw;
        }
        if (bestScore == 1.00) break outer;
      }
    }

    if (bestScore < thresholdAccept || bestIntent == null) return null;

    return VoiceCommandMatch(
      intent: bestIntent,
      confidence: (bestScore * 100).round() / 100,
      alias: bestAlias!,
      transcript: transcript,
      isHigh: bestScore >= thresholdHigh,
    );
  }
}
