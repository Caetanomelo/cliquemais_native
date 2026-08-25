class DialogueLine {
  final String speaker;
  final String text;
  final String pt;
  const DialogueLine({required this.speaker, required this.text, required this.pt});

  // Turns are stored as flat {speaker,en,es,pt} triples (backend migration
  // 038) — [text] reads the `en` field, the base/course-default language.
  factory DialogueLine.fromJson(Map<String, dynamic> j) => DialogueLine(
        speaker: j['speaker'] as String,
        text: j['en'] as String,
        // A handful of dialogue lines in the source content never got a PT
        // translation authored (pre-existing gap, not a porting error).
        pt: j['pt'] as String? ?? '',
      );

  // Same triple, picking [code] (e.g. 'es') as the course-language text
  // instead of `en` — used to build Lesson/CorpTrack.byLanguage variants.
  factory DialogueLine.forCode(Map<String, dynamic> j, String code) => DialogueLine(
        speaker: j['speaker'] as String,
        text: j[code] as String? ?? j['en'] as String,
        pt: j['pt'] as String? ?? '',
      );
}

List<List<DialogueLine>> dialoguesFromJson(dynamic v) => (v as List? ?? [])
    .map((d) => (d as List).map((l) => DialogueLine.fromJson(l as Map<String, dynamic>)).toList())
    .toList();

List<List<DialogueLine>> dialoguesForCode(dynamic v, String code) => (v as List? ?? [])
    .map((d) => (d as List).map((l) => DialogueLine.forCode(l as Map<String, dynamic>, code)).toList())
    .toList();
