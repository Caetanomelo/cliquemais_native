class DialogueLine {
  final String speaker;
  final String text;
  final String pt;
  const DialogueLine({required this.speaker, required this.text, required this.pt});

  factory DialogueLine.fromJson(Map<String, dynamic> j) => DialogueLine(
        speaker: j['speaker'] as String,
        text: j['text'] as String,
        // A handful of dialogue lines in the source content never got a PT
        // translation authored (pre-existing gap, not a porting error).
        pt: j['pt'] as String? ?? '',
      );
}

List<List<DialogueLine>> dialoguesFromJson(dynamic v) => (v as List? ?? [])
    .map((d) => (d as List).map((l) => DialogueLine.fromJson(l as Map<String, dynamic>)).toList())
    .toList();
