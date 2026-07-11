import 'package:flutter/foundation.dart';

/// One pronunciation fix: replace [term] with [say] (a respelling the TTS engine
/// pronounces correctly) for the given target-language [lang], applied to the
/// TTS input only — the on-screen translation is untouched.
class PronEntry {
  final String term;
  final String say;
  final String lang;
  PronEntry({required this.term, required this.say, required this.lang});
}

/// On-device pronunciation dictionary. Grapheme-respelling approach: robust and
/// engine-agnostic (platform TTS exposes no lexicon API). When we move to a
/// neural TTS (Supertonic-3/Piper) we can swap this for a real IPA lexicon.
class Pronunciation extends ChangeNotifier {
  final List<PronEntry> entries = [
    PronEntry(term: 'ESD', say: 'E S D', lang: 'vi'),
    PronEntry(term: 'ESD', say: 'E S D', lang: 'en'),
    PronEntry(term: 'PPE', say: 'P P E', lang: 'vi'),
    PronEntry(term: 'VinFast', say: 'Vin Phát', lang: 'vi'),
    PronEntry(term: 'Samsung', say: '삼성', lang: 'ko'),
  ];

  void add(PronEntry e) {
    entries.insert(0, e);
    notifyListeners();
  }

  void removeAt(int i) {
    entries.removeAt(i);
    notifyListeners();
  }

  /// Apply all fixes for [langCode] to [text] (case-insensitive).
  String apply(String text, String langCode) {
    var out = text;
    for (final e in entries) {
      if (e.lang != langCode) continue;
      final re = RegExp(RegExp.escape(e.term), caseSensitive: false, unicode: true);
      out = out.replaceAll(re, e.say);
    }
    return out;
  }
}
