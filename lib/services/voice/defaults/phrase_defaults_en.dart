import '../matching/phrase_matcher.dart';
import 'phrase_defaults.dart';

const voicePhrasesEn = VoicePhraseSet(
  wake: ['hey spotube', 'ok spotube', 'hey spot tube'],
  commands: {
    VoiceCommandId.play: ['play', 'resume', 'continue'],
    VoiceCommandId.pause: ['pause', 'stop music'],
    VoiceCommandId.playPause: ['toggle playback'],
    VoiceCommandId.next: ['next', 'next song', 'skip'],
    VoiceCommandId.previous: ['previous', 'previous song'],
    VoiceCommandId.seekForward: ['skip forward', 'ten seconds forward'],
    VoiceCommandId.seekBackward: ['skip back', 'ten seconds back'],
    VoiceCommandId.seekTo: ['seek to {percent} percent', 'go to {percent}'],
    VoiceCommandId.volumeUp: ['louder', 'volume up'],
    VoiceCommandId.volumeDown: ['quieter', 'volume down'],
    VoiceCommandId.setVolume: [
      'set volume {percent}',
      'volume {percent} percent'
    ],
    VoiceCommandId.search: ['search {query}', 'find {query}'],
    VoiceCommandId.playPlaylist: ['play playlist {name}'],
    VoiceCommandId.like: ['like this', 'favorite this'],
    VoiceCommandId.unlike: ['unlike this', 'unfavorite'],
    VoiceCommandId.addToQueue: ['add to queue', 'queue this'],
    VoiceCommandId.openQueue: ['open queue', 'show queue'],
    VoiceCommandId.stopListening: ['stop listening', 'never mind'],
  },
);
