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

  // Same triple, picking [target] as the studied text and [native] as the
  // explanation — for any of the 6 valid (target, native) pairs.
  factory DialogueLine.forPair(Map<String, dynamic> j, String target, String native) => DialogueLine(
        speaker: j['speaker'] as String,
        text: j[target] as String? ?? j['en'] as String,
        pt: j[native] as String? ?? j['pt'] as String? ?? '',
      );
}

List<List<DialogueLine>> dialoguesFromJson(dynamic v) => (v as List? ?? [])
    .map((d) => (d as List).map((l) => DialogueLine.fromJson(l as Map<String, dynamic>)).toList())
    .toList();

List<List<DialogueLine>> dialoguesForPair(dynamic v, String target, String native) => (v as List? ?? [])
    .map((d) => (d as List).map((l) => DialogueLine.forPair(l as Map<String, dynamic>, target, native)).toList())
    .toList();
