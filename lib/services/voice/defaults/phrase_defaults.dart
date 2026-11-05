import '../matching/phrase_matcher.dart';
import '../matching/text_normalizer.dart';
import 'phrase_defaults_ar.dart';
import 'phrase_defaults_en.dart';
import 'phrase_defaults_es.dart';
import 'phrase_defaults_fr.dart';
import 'phrase_defaults_hi.dart';

/// Shipped phrase sets. These are Dart maps, not assets: they must be
/// available before any model download and are the reset target in the
/// editor. Slot commands use `{query}`, `{name}` or `{percent}`.
class VoicePhraseSet {
  final List<String> wake;
  final Map<VoiceCommandId, List<String>> commands;
  const VoicePhraseSet({required this.wake, required this.commands});
}

List<String> defaultWakePhrases(VoiceLanguage lang) => phraseSetFor(lang).wake;

List<String> defaultCommandPhrases(VoiceLanguage lang, VoiceCommandId id) =>
    phraseSetFor(lang).commands[id] ?? const [];

VoicePhraseSet phraseSetFor(VoiceLanguage lang) => switch (lang) {
      VoiceLanguage.en => voicePhrasesEn,
      VoiceLanguage.hi => voicePhrasesHi,
      VoiceLanguage.es => voicePhrasesEs,
      VoiceLanguage.fr => voicePhrasesFr,
      VoiceLanguage.ar => voicePhrasesAr,
    };
