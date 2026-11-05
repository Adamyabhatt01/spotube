// Reduction of a phrase or a recognizer transcript to a single comparable
// "phonetic-ish" key, so a user can type a phrase in any script the model
// might emit and it still matches.
//
// The key is deliberately lossy: ASR output of fixed phrases varies by
// accent, spacing and script, and only the lossy form is stable across
// "गाना चालू करो", "gaana chalu karo" and "gana calu karo".
library;

/// Languages with a shipped phrase-default set.
enum VoiceLanguage {
  en('en'),
  hi('hi'),
  es('es'),
  fr('fr'),
  ar('ar');

  const VoiceLanguage(this.code);
  final String code;

  static VoiceLanguage fromCode(String code) =>
      VoiceLanguage.values.firstWhere((e) => e.code == code, orElse: () => en);
}

class VoiceTextNormalizer {
  const VoiceTextNormalizer();

  static final _harakat = RegExp(
    '[\u064B-\u0652\u0670\u0640\u06DF\u06E0\u06E2\u06E3\u06E5\u06E6\u06E7\u06E8\u06EA-\u06ED]',
  );

  // Arabic script unification before transliteration.
  static const _arabicFolding = {
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ة': 'ه',
    'ى': 'ي',
    'ؤ': 'و',
    'ئ': 'ي',
  };

  // Consonantal Latin for Arabic letters; short vowels are dropped on both
  // sides later, which is what lets a typed Latin phrase with vowels match
  // the script, where they are mostly unwritten.
  static const _arabicToLatin = {
    'ا': 'a',
    'ب': 'b',
    'ت': 't',
    'ث': 'th',
    'ج': 'j',
    'ح': 'h',
    'خ': 'kh',
    'د': 'd',
    'ذ': 'dh',
    'ر': 'r',
    'ز': 'z',
    'س': 's',
    'ش': 'sh',
    'ص': 's',
    'ض': 'd',
    'ط': 't',
    'ظ': 'z',
    'ع': 'a',
    'غ': 'gh',
    'ف': 'f',
    'ق': 'q',
    'ك': 'k',
    'ل': 'l',
    'م': 'm',
    'ن': 'n',
    'ه': 'h',
    'و': 'w',
    'ي': 'y',
    'لَا': 'la',
  };

  // Devanagari to Latin. A consonant carries an inherent schwa that a
  // following halant removes and a dependent vowel replaces.
  static const _devaConsonants = {
    'क': 'k',
    'ख': 'kh',
    'ग': 'g',
    'घ': 'gh',
    'ङ': 'n',
    'च': 'ch',
    'छ': 'chh',
    'ज': 'j',
    'झ': 'jh',
    'ञ': 'n',
    'ट': 't',
    'ठ': 'th',
    'ड': 'd',
    'ढ': 'dh',
    'ण': 'n',
    'त': 't',
    'थ': 'th',
    'द': 'd',
    'ध': 'dh',
    'न': 'n',
    'प': 'p',
    'फ': 'ph',
    'ब': 'b',
    'भ': 'bh',
    'म': 'm',
    'य': 'y',
    'र': 'r',
    'ल': 'l',
    'ळ': 'l',
    'व': 'v',
    'श': 'sh',
    'ष': 'sh',
    'स': 's',
    'ह': 'h',
    // Conjuncts like क्ष are not keys here: lookup is per code unit, and the
    // halant path already composes them (क + ् + ष → k + sh).
  };

  static const _devaVowels = {
    'अ': 'a',
    'आ': 'aa',
    'इ': 'i',
    'ई': 'ee',
    'उ': 'u',
    'ऊ': 'oo',
    'ऋ': 'ri',
    'ए': 'e',
    'ऐ': 'ai',
    'ओ': 'o',
    'औ': 'au',
  };

  // Dependent vowel signs, keyed with the matra code point.
  static const _devaMatras = {
    'ा': 'aa',
    'ि': 'i',
    'ी': 'ee',
    'ु': 'u',
    'ू': 'oo',
    'ृ': 'ri',
    'े': 'e',
    'ै': 'ai',
    'ो': 'o',
    'ौ': 'au',
  };

  static const _devaSpecial = {
    '्': '', // halant: handled by the scanner
    'ं': 'n', 'ँ': 'n', 'ः': 'h', 'ऽ': '',
    'ॐ': 'om',
    'ऱ': 'r',
  };

  static const _latinAccents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ñ': 'n',
    'ç': 'c',
    'ý': 'y',
    'ÿ': 'y',
    'ß': 'ss',
    'æ': 'ae',
    'œ': 'oe',
  };

  // Word-form numbers the recognizers emit, per language, mapped to digits
  // so "fifty", "cinquante" and "पचास" all parse to 50.
  static const numberWords = <VoiceLanguage, Map<String, int>>{
    VoiceLanguage.en: {
      'ten': 10,
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'fifty': 50,
      'sixty': 60,
      'seventy': 70,
      'eighty': 80,
      'ninety': 90,
      'hundred': 100,
    },
    VoiceLanguage.es: {
      'diez': 10,
      'veinte': 20,
      'treinta': 30,
      'cuarenta': 40,
      'cincuenta': 50,
      'sesenta': 60,
      'setenta': 70,
      'ochenta': 80,
      'noventa': 90,
      'cien': 100,
      'ciento': 100,
    },
    VoiceLanguage.fr: {
      'dix': 10,
      'vingt': 20,
      'trente': 30,
      'quarante': 40,
      'cinquante': 50,
      'soixante': 60,
      'soixante-dix': 70,
      'septante': 70,
      'quatre-vingt': 80,
      'quatre-vingts': 80,
      'nonante': 90,
      'cent': 100,
    },
    VoiceLanguage.hi: {
      'दस': 10,
      'बीस': 20,
      'तीस': 30,
      'चालीस': 40,
      'पचास': 50,
      'साठ': 60,
      'सत्तर': 70,
      'अस्सी': 80,
      'नब्बे': 90,
      'सौ': 100,
      'das': 10,
      'bees': 20,
      'teis': 30,
      'caalis': 40,
      'pachaas': 50,
      'saath': 60,
      'sattar': 70,
      'assi': 80,
      'nabbe': 90,
      'sau': 100,
    },
    VoiceLanguage.ar: {
      'عشرة': 10,
      'عشرون': 20,
      'ثلاثون': 30,
      'اربعون': 40,
      'خمسون': 50,
      'خمسين': 50,
      'ستون': 60,
      'سبعون': 70,
      'ثمانون': 80,
      'تسعون': 90,
      'مئة': 100,
      'miat': 100,
    },
  };

  /// The comparable form of [input]. Both stored phrases and transcripts are
  /// passed through this, so they meet in the same key space.
  String key(String input, VoiceLanguage language) {
    var s = input.toLowerCase();
    if (language == VoiceLanguage.hi || _containsDevanagari(s)) {
      s = _devanagariToLatin(s);
    } else if (language == VoiceLanguage.ar || _containsArabic(s)) {
      s = _arabicToLatinScript(s);
    } else {
      s = _foldAccents(s);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Length and doubling folds: gaana/ganaa/gana, chaloo/chalu.
    s = _collapse(s, 'aa', 'a');
    s = _collapse(s, 'ee', 'i');
    s = _collapse(s, 'oo', 'u');
    s = s.replaceAll(RegExp(r'(.)\1+'), r'$1');
    // Indic schwa-deletion makes "karo"/"kr" the same anchor; w/v merge.
    s = s.replaceAll('w', 'v');
    if (language == VoiceLanguage.ar) {
      // Consonant skeleton: short vowels are unwritten in the script but
      // typed in Latin.
      s = s.replaceAll(RegExp(r'[aeiou]'), '');
    }
    return s;
  }

  /// Parses a spoken or written 10-step percentage out of [words], e.g.
  /// "fifty", "50", "पचास". Only multiples of ten are supported by design.
  int? parseStepPercent(Iterable<String> words, VoiceLanguage language) {
    final table = numberWords[language] ?? const {};
    final joined = words.join('-');
    final asWord = table[joined.toLowerCase()];
    if (asWord != null) return _asStep(asWord);
    for (final word in words) {
      final direct = int.tryParse(word.replaceAll(RegExp(r'[^0-9]'), ''));
      if (direct != null && direct > 0) return _asStep(direct);
      final mapped = table[word.toLowerCase()];
      if (mapped != null) return _asStep(mapped);
    }
    return null;
  }

  static int? _asStep(int value) {
    if (value <= 0 || value > 100) return null;
    final step = ((value + 5) ~/ 10) * 10;
    return step == 0 ? 10 : (step > 100 ? 100 : step);
  }

  static bool _containsDevanagari(String s) =>
      RegExp('[\u0900-\u097F]').hasMatch(s);

  static bool _containsArabic(String s) =>
      RegExp('[\u0600-\u06FF]').hasMatch(s);

  static String _collapse(String s, String from, String to) =>
      s.replaceAll(from, to);

  String _foldAccents(String s) {
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(_latinAccents[ch] ?? ch);
    }
    return b.toString();
  }

  String _arabicToLatinScript(String s) {
    final cleaned = s.replaceAll(_harakat, '');
    final b = StringBuffer();
    for (final ch in cleaned.split('')) {
      final unified = _arabicFolding[ch] ?? ch;
      b.write(_arabicToLatin[unified] ?? unified);
    }
    return b.toString();
  }

  String _devanagariToLatin(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_devaConsonants.containsKey(ch)) {
        b.write(_devaConsonants[ch]);
        // Inherent schwa unless killed by a halant or replaced by a matra.
        final next = i + 1 < s.length ? s[i + 1] : '';
        if (next == '्') {
          i++; // consume halant, no vowel
        } else if (_devaMatras.containsKey(next)) {
          b.write(_devaMatras[next]);
          i++;
        } else {
          b.write('a');
        }
      } else if (_devaVowels.containsKey(ch)) {
        b.write(_devaVowels[ch]);
      } else if (_devaMatras.containsKey(ch)) {
        b.write(_devaMatras[ch]);
      } else if (_devaSpecial.containsKey(ch)) {
        b.write(_devaSpecial[ch]);
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }
}
