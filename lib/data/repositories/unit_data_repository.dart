import 'dart:convert';

import '../../core/services/remote_content_service.dart';
import '../models/unit_meta.dart';
import '../models/phrase.dart';
import '../models/vocab_item.dart';

/// Loads the four data assets extracted from the web app:
/// unit_meta.json (`_UNIT_MAP_5C`), drive_phrases.json (`_UNIT_PHRASES`),
/// vocab_items.json (vocab-type lesson items in `UNITS`) and
/// emoji_map.json (`EMOJI_MAP`). Content comes straight from
/// [RemoteContentService] (Netlify/Supabase-hosted) — no offline fallback.
class UnitDataRepository {
  final RemoteContentService _content;
  UnitDataRepository({RemoteContentService? content}) : _content = content ?? RemoteContentService();

  List<UnitMeta>? _unitMeta;
  List<UnitPhrases>? _drivePhrases;
  List<UnitVocab>? _vocabItems;
  Map<String, String>? _emojiMap;

  Future<void> loadAll() async {
    await Future.wait([
      _loadUnitMeta(),
      _loadDrivePhrases(),
      _loadVocabItems(),
      _loadEmojiMap(),
    ]);
  }

  Future<void> _loadUnitMeta() async {
    final raw = await _content.loadString('unit_meta.json');
    final list = jsonDecode(raw) as List;
    _unitMeta = list.map((e) => UnitMeta.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.unit.compareTo(b.unit));
  }

  Future<void> _loadDrivePhrases() async {
    final raw = await _content.loadString('drive_phrases.json');
    final list = jsonDecode(raw) as List;
    _drivePhrases = list.map((e) => UnitPhrases.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.unit.compareTo(b.unit));
  }

  Future<void> _loadVocabItems() async {
    final raw = await _content.loadString('vocab_items.json');
    final list = jsonDecode(raw) as List;
    _vocabItems = list.map((e) => UnitVocab.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.unit.compareTo(b.unit));
  }

  Future<void> _loadEmojiMap() async {
    final raw = await _content.loadString('emoji_map.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _emojiMap = map.map((k, v) => MapEntry(k, v as String));
  }

  List<UnitMeta> get unitMeta => _unitMeta ?? const [];
  List<UnitPhrases> get drivePhrases => _drivePhrases ?? const [];
  List<UnitVocab> get vocabItems => _vocabItems ?? const [];
  Map<String, String> get emojiMap => _emojiMap ?? const {};

  UnitMeta? metaForUnit(int unit) {
    for (final m in unitMeta) {
      if (m.unit == unit) return m;
    }
    return null;
  }

  List<Phrase> phrasesForUnit(int unit) {
    for (final u in drivePhrases) {
      if (u.unit == unit) return u.phrases;
    }
    return const [];
  }

  List<VocabItem> vocabForUnit(int unit) {
    for (final u in vocabItems) {
      if (u.unit == unit) return u.items;
    }
    return const [];
  }

  /// Emoji lookup is case-insensitive, matching `getEmoji(word)` in the
  /// source app which lowercases the key before indexing `EMOJI_MAP`.
  String? emojiFor(String word) => emojiMap[word.toLowerCase()];
}
