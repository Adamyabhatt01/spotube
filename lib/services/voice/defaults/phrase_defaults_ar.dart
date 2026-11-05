import '../matching/phrase_matcher.dart';
import 'phrase_defaults.dart';

// Modern Standard Arabic phrasing; dialects are the user's editable domain.
const voicePhrasesAr = VoicePhraseSet(
  wake: ['مرحبا سبوتوب', 'hey spotube'],
  commands: {
    VoiceCommandId.play: ['شغل الموسيقى', 'أكمل', 'شغل'],
    VoiceCommandId.pause: ['إيقاف', 'وقف الموسيقى'],
    VoiceCommandId.playPause: ['تبديل التشغيل'],
    VoiceCommandId.next: ['التالي', 'الأغنية التالية'],
    VoiceCommandId.previous: ['السابق', 'الأغنية السابقة'],
    VoiceCommandId.seekForward: ['تقدم عشر ثوان', 'skip forward'],
    VoiceCommandId.seekBackward: ['تراجع عشر ثوان', 'skip back'],
    VoiceCommandId.seekTo: ['اذهب إلى {percent} بالمئة', 'go to {percent}'],
    VoiceCommandId.volumeUp: ['ارفع الصوت', 'أعلى'],
    VoiceCommandId.volumeDown: ['اخفض الصوت', 'أوطأ'],
    VoiceCommandId.setVolume: [
      'اضبط الصوت على {percent}',
      'set volume {percent}'
    ],
    VoiceCommandId.search: ['ابحث عن {query}', 'دور على {query}'],
    VoiceCommandId.playPlaylist: [
      'شغل قائمة {name}',
      'افتح قائمة التشغيل {name}'
    ],
    VoiceCommandId.like: ['أعجبني', 'إعجاب'],
    VoiceCommandId.unlike: ['ألغ الإعجاب', 'ما أعجبني'],
    VoiceCommandId.addToQueue: ['أضف إلى قائمة الانتظار'],
    VoiceCommandId.openQueue: ['افتح قائمة الانتظار'],
    VoiceCommandId.stopListening: ['توقف عن الاستماع', 'احذف'],
  },
);
