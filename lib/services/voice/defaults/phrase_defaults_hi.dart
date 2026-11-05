import '../matching/phrase_matcher.dart';
import 'phrase_defaults.dart';

// Devanagari and Roman aliases are listed together deliberately: the
// normalizer keys both spellings to the same form.
const voicePhrasesHi = VoicePhraseSet(
  wake: ['hey spotube', 'है स्पॉटयूब'],
  commands: {
    VoiceCommandId.play: [
      'गाना चालू करो',
      'गाना बजाओ',
      'gana chalu karo',
      'gana bajaao',
      'play'
    ],
    VoiceCommandId.pause: ['रोको', 'गाना रुको', 'roko', 'pause'],
    VoiceCommandId.playPause: ['चालू रुक करो'],
    VoiceCommandId.next: ['अगला गाना', 'आगे बढ़ो', 'agla gaana', 'next'],
    VoiceCommandId.previous: ['पिछला गाना', 'peeche', 'previous'],
    VoiceCommandId.seekForward: ['दस सेकंड आगे', 'skip forward'],
    VoiceCommandId.seekBackward: ['दस सेकंड पीछे', 'skip back'],
    VoiceCommandId.seekTo: ['{percent} प्रतिशत पर जाओ', 'go to {percent}'],
    VoiceCommandId.volumeUp: [
      'आवाज़ बढ़ाओ',
      'आवाज तेज़ करो',
      'aawaz badhao',
      'louder'
    ],
    VoiceCommandId.volumeDown: ['आवाज़ कम करो', 'aawaz kam karo', 'quieter'],
    VoiceCommandId.setVolume: ['वॉल्यूम {percent} करो', 'set volume {percent}'],
    VoiceCommandId.search: ['{query} खोजो', 'खोजो {query}', 'search {query}'],
    VoiceCommandId.playPlaylist: [
      '{name} प्लेलिस्ट बजाओ',
      'प्लेलिस्ट बजाओ {name}',
      'play playlist {name}'
    ],
    VoiceCommandId.like: ['पसंद है', 'pasand hai', 'like this'],
    VoiceCommandId.unlike: ['नापसंद', 'napasand', 'unlike this'],
    VoiceCommandId.addToQueue: [
      'क्यू में डालो',
      'queue mein daalo',
      'add to queue'
    ],
    VoiceCommandId.openQueue: ['क्यू दिखाओ', 'queue dikhaao', 'open queue'],
    VoiceCommandId.stopListening: ['बस करो', 'bas karo', 'stop listening'],
  },
);
