/// Normalizes text for indexing and search.
/// Must use the same function at index time and at query time.
class SearchNormalizer {
  /// Generates unique trigrams from a normalized string.
  ///
  /// For a string of length N, generates N-2 trigrams (positions 0..N-3).
  /// Uses a Set for uniqueness.
  static Set<String> generateTrigrams(String normalized) {
    final trigrams = <String>{};
    if (normalized.length < 3) {
      return trigrams;
    }

    for (int i = 0; i <= normalized.length - 3; i++) {
      final trigram = normalized.substring(i, i + 3);
      trigrams.add(trigram);
    }

    return trigrams;
  }

  /// Lowercase, replace ё→е, keep only [a-z0-9а-я], collapse whitespace.
  static String normalize(String text) {
    if (text.isEmpty) return '';

    String normalized = text.toLowerCase().replaceAll('ё', 'е');

    final buffer = StringBuffer();
    for (int i = 0; i < normalized.length; i++) {
      final codeUnit = normalized.codeUnitAt(i);
      if ((codeUnit >= 97 && codeUnit <= 122) ||   // a-z
          (codeUnit >= 48 && codeUnit <= 57) ||     // 0-9
          (codeUnit >= 1072 && codeUnit <= 1103)) { // а-я
        buffer.writeCharCode(codeUnit);
      } else {
        buffer.write(' ');
      }
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

