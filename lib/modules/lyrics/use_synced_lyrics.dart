import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

/// Returns the index of the active lyric line at the current playback
/// position, i.e. the most recent line whose timestamp is at or before
/// `position + delay`, or -1 before the first line starts.
///
/// The previous implementation only advanced when the playback second landed
/// exactly on a lyric's integer-second key (`lyricsMap.containsKey(...)`),
/// which made the highlight lag or freeze between lines and after seeks.
/// Comparing against the sorted lyric list directly keeps the highlight in
/// lockstep with the music.
int useSyncedLyrics(
  WidgetRef ref,
  List<LyricSlice> lyrics,
  int delay,
) {
  final activeIndex = useState(-1);

  void evaluate(Duration position) {
    final next = _activeLineIndex(lyrics, position + Duration(seconds: delay));
    if (next != activeIndex.value) {
      activeIndex.value = next;
    }
  }

  // Raw position events, on purpose: throttling them would delay the
  // highlight. Only a line change is allowed to rebuild the page, which is why
  // the index is resolved here instead of in a position ValueNotifier that the
  // whole lyric list would watch.
  useEffect(() {
    evaluate(audioPlayer.position);
    return audioPlayer.positionStream.listen(evaluate).cancel;
  }, [lyrics, delay]);

  return activeIndex.value;
}

/// Binary search for the most recent line with time <= [position].
/// Lyrics are sorted by timestamp; this avoids a linear scan per event.
int _activeLineIndex(List<LyricSlice> lyrics, Duration position) {
  var lo = 0;
  var hi = lyrics.length - 1;
  var result = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lyrics[mid].time <= position) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return result;
}
