import '../matching/phrase_matcher.dart';
import 'phrase_defaults.dart';

const voicePhrasesFr = VoicePhraseSet(
  wake: ['hé spotube', 'hey spotube', 'salut spotube'],
  commands: {
    VoiceCommandId.play: ['lecture', 'continuer', 'mets la musique'],
    VoiceCommandId.pause: ['pause', 'arrête la musique'],
    VoiceCommandId.playPause: ['bascule lecture'],
    VoiceCommandId.next: ['suivant', 'titre suivant'],
    VoiceCommandId.previous: ['précédent', 'titre précédent'],
    VoiceCommandId.seekForward: ['avance de dix secondes', 'skip forward'],
    VoiceCommandId.seekBackward: ['recule de dix secondes', 'skip back'],
    VoiceCommandId.seekTo: ['va à {percent} pour cent', 'go to {percent}'],
    VoiceCommandId.volumeUp: ['monte le volume', 'plus fort'],
    VoiceCommandId.volumeDown: ['baisse le volume', 'moins fort'],
    VoiceCommandId.setVolume: [
      'mets le volume à {percent}',
      'set volume {percent}'
    ],
    VoiceCommandId.search: ['cherche {query}', 'recherche {query}'],
    VoiceCommandId.playPlaylist: [
      'joue la playlist {name}',
      'mets la liste {name}'
    ],
    VoiceCommandId.like: ['j’aime bien', 'aime'],
    VoiceCommandId.unlike: ['je n’aime plus'],
    VoiceCommandId.addToQueue: ['ajouter à la file', 'mets dans la file'],
    VoiceCommandId.openQueue: ['ouvre la file', 'montre la file'],
    VoiceCommandId.stopListening: ['arrête d’écouter', 'annule'],
  },
);
