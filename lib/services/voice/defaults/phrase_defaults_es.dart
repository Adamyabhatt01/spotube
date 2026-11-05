import '../matching/phrase_matcher.dart';
import 'phrase_defaults.dart';

const voicePhrasesEs = VoicePhraseSet(
  wake: ['oye spotube', 'hey spotube'],
  commands: {
    VoiceCommandId.play: ['reproducir', 'continúa', 'pon la música'],
    VoiceCommandId.pause: ['pausa', 'para la música'],
    VoiceCommandId.playPause: ['alternar reproducción'],
    VoiceCommandId.next: ['siguiente', 'pon la siguiente'],
    VoiceCommandId.previous: ['anterior', 'la anterior'],
    VoiceCommandId.seekForward: ['adelanta diez segundos', 'skip forward'],
    VoiceCommandId.seekBackward: ['retrocede diez segundos', 'skip back'],
    VoiceCommandId.seekTo: ['ve al {percent} por ciento', 'go to {percent}'],
    VoiceCommandId.volumeUp: ['sube el volumen', 'más fuerte'],
    VoiceCommandId.volumeDown: ['baja el volumen', 'más suave'],
    VoiceCommandId.setVolume: [
      'pon el volumen al {percent}',
      'set volume {percent}'
    ],
    VoiceCommandId.search: ['busca {query}', 'buscar {query}', 'pon {query}'],
    VoiceCommandId.playPlaylist: [
      'pon la playlist {name}',
      'reproduce la lista {name}'
    ],
    VoiceCommandId.like: ['me gusta', 'añadir a me gusta'],
    VoiceCommandId.unlike: ['ya no me gusta', 'quita de me gusta'],
    VoiceCommandId.addToQueue: ['añadir a la cola', 'pon en cola'],
    VoiceCommandId.openQueue: ['abrir la cola', 'mostrar la cola'],
    VoiceCommandId.stopListening: ['para de escuchar', 'olvídalo'],
  },
);
