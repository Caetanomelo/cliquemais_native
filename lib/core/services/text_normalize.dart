/// Ports the two normalization strategies used by the web app.
class TextNormalize {
  /// Drive Mode / VPC word-overlap normalization: lowercase, strip
  /// everything but a-z0-9 and spaces, collapse whitespace.
  /// (index.html `_scoreWords`'s inner `norm`, decoded_app.html `_scoreWords`/`_exactMatch`'s inner `norm`)
  static String asciiFold(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// VPC's `_normText`: trim, lowercase, NFD-decompose, strip combining
  /// diacritics — used before `asciiFold` in VPC scoring so accented
  /// characters fold to their base letter instead of being dropped.
  static String stripDiacritics(String s) {
    const withDiacritics =
        'àáâãäåāăąèéêëēĕėęěìíîïĩīĭįòóôõöøōŏőùúûüũūŭůűųçćĉċčñńņňÀÁÂÃÄÅĀĂĄÈÉÊËĒĔĖĘĚÌÍÎÏĨĪĬĮÒÓÔÕÖØŌŎŐÙÚÛÜŨŪŬŮŰŲÇĆĈĊČÑŃŅŇ';
    const base =
        'aaaaaaaaaeeeeeeeeeiiiiiiiioooooooooouuuuuuuuuuccccnnnnAAAAAAAAAEEEEEEEEEIIIIIIIIOOOOOOOOOOUUUUUUUUUUCCCCNNNN';
    final buf = StringBuffer();
    for (final ch in s.runes) {
      final chStr = String.fromCharCode(ch);
      final idx = withDiacritics.indexOf(chStr);
      buf.write(idx >= 0 ? base[idx] : chStr);
    }
    return buf.toString();
  }

  /// Full VPC normalization pipeline: `_normText` then the ascii fold.
  static String normVpc(String s) => asciiFold(stripDiacritics(s.trim().toLowerCase()));
}
