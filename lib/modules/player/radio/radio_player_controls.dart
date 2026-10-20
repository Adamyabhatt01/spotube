import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/utils/platform.dart';

/// Live-stream transport: play/pause and stop only. No scrubber, duration, next
/// or previous — a live radio stream has none of those. Mirrors the music
/// [PlayerControls] button sizing so the bar height is unchanged when the
/// source switches.
class RadioPlayerControls extends HookConsumerWidget {
  const RadioPlayerControls({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final playback = ref.watch(radioPlaybackControllerProvider);
    final controller = ref.read(radioPlaybackControllerProvider.notifier);

    final connecting = playback.buffering && !playback.playing;
    final buttonSize =
        kIsMobile ? const ButtonSize(1.5) : const ButtonSize(1.2);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          tooltip: TooltipContainer(
            child: Text(
              playback.playing
                  ? context.l10n.pause_playback
                  : context.l10n.resume_playback,
            ),
          ).call,
          child: IconButton.primary(
            size: buttonSize,
            shape: ButtonShape.circle,
            icon: connecting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(),
                  )
                : Icon(
                    playback.playing ? SpotubeIcons.pause : SpotubeIcons.play,
                  ),
            onPressed: () =>
                playback.playing ? controller.pause() : controller.resume(),
          ),
        ),
        const Gap(8),
        Tooltip(
          tooltip: const TooltipContainer(child: Text('Stop')).call,
          child: IconButton.ghost(
            size: buttonSize,
            icon: const Icon(SpotubeIcons.stop),
            onPressed: controller.stop,
          ),
        ),
      ],
    );
  }
}
