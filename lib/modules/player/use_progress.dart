import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

({
  double progressStatic,
  Duration position,
  Duration duration,
  double bufferProgress
}) useProgress(WidgetRef ref) {
  // media_kit's `buffer` (demuxer-cache-time) fires several times a second
  // while the network refills, and the hint bar only ever renders whole
  // seconds. Quantize before the hook sees it, and hold one stream object so
  // the rebuild does not resubscribe (Stream has no value equality).
  final bufferedSecondsStream = useMemoized(
    () => audioPlayer.bufferedPositionStream
        .map((buffered) => buffered.inSeconds)
        .distinct(),
    const [],
  );
  final bufferProgress = useStream(bufferedSecondsStream).data ?? 0;

  final duration = useState(Duration.zero);
  final position = useState(Duration.zero);

  final sliderMax = duration.value.inSeconds;
  final sliderValue = position.value.inSeconds;

  useEffect(() {
    duration.value = audioPlayer.duration;

    final durationSubscription = audioPlayer.durationStream.listen((event) {
      duration.value = event;
    });

    position.value = audioPlayer.position;

    // Shared whole-second ticks (~1/sec instead of the raw ~5/sec), and the
    // player service forces a tick after a seek so a scrub shows up within one
    // position event instead of waiting for the second to roll over.
    final positionSubscription =
        audioPlayer.positionTickStream.listen((event) {
      position.value = event;
    });

    return () {
      positionSubscription.cancel();
      durationSubscription.cancel();
    };
  }, []);

  return (
    progressStatic:
        sliderMax == 0 || sliderValue > sliderMax ? 0 : sliderValue / sliderMax,
    position: position.value,
    duration: duration.value,
    bufferProgress: sliderMax == 0 || bufferProgress > sliderMax
        ? 0
        : bufferProgress / sliderMax,
  );
}
