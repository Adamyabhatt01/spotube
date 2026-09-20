import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

/// Returns the index of the active lyric line at the current playback
/// position, i.e. the most recent line whose timestamp is at or before
/// `position + delay`.
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
  final position = useState(Duration.zero);
  final activeIndex = useState(0);

  useEffect(() {
    return audioPlayer.positionStream.listen((pos) {
      try {
        position.value = pos;
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }).cancel;
  }, []);

  final effectivePosition = position.value + Duration(seconds: delay);

  // Binary search for the most recent line with time <= effectivePosition.
  // Lyrics are sorted by timestamp; this avoids a linear scan per frame.
  var lo = 0;
  var hi = lyrics.length - 1;
  var result = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lyrics[mid].time <= effectivePosition) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  if (result != activeIndex.value) {
    activeIndex.value = result;
  }

  return activeIndex.value;
}