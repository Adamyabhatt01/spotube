import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/player/player_play_pause_button.dart';
import 'package:spotube/modules/player/player_track_details.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

class PlayerOverlayCollapsedSection extends HookConsumerWidget {
  final PanelController panelController;
  const PlayerOverlayCollapsedSection({
    super.key,
    required this.panelController,
  });

  @override
  Widget build(BuildContext context, ref) {
    final activeTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    final canShow = activeTrack != null;

    final theme = Theme.of(context);

    final shouldShow = useState(true);

    ref.listen(navigationPanelHeight, (_, height) {
      shouldShow.value = height.ceil() == 50;
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: canShow && shouldShow.value
          ? Padding(
              padding: const EdgeInsets.all(5),
              child: SurfaceCard(
                // Keep the frost through scrolls and play/pause. The old
                // freeze dropped the filter (and with a translucent theme,
                // the bar itself) exactly while the user was looking at it;
                // scrolling it was not a measured CPU win. The Android
                // manifest disables Impeller until the engine fix in 3.38.
                surfaceBlur: theme.surfaceBlur,
                surfaceOpacity: theme.surfaceOpacity,
                padding: EdgeInsets.zero,
                borderRadius: theme.borderRadiusLg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                panelController.open();
                              },
                              child: Container(
                                width: double.infinity,
                                color: Colors.transparent,
                                child: PlayerTrackDetails(
                                  track: activeTrack,
                                  color: theme.colorScheme.foreground,
                                ),
                              ),
                            ),
                          ),
                          const _CollapsedTransportControls(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// The mini player's transport row.
///
/// It watches source-resolution and playback state here, not in
/// [PlayerOverlayCollapsedSection.build], so a spinner finishing or a
/// play/pause toggle cannot rebuild the frosted [SurfaceCard] around it.
class _CollapsedTransportControls extends ConsumerWidget {
  const _CollapsedTransportControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isResolving = ref.watch(isResolvingActiveTrackProvider);

    return Row(
      children: [
        IconButton.ghost(
          icon: const Icon(SpotubeIcons.skipBack),
          onPressed: isResolving ? null : audioPlayer.skipToPrevious,
        ),
        const PlayerPlayPauseButton(showTooltip: false),
        IconButton.ghost(
          icon: const Icon(SpotubeIcons.skipForward),
          onPressed: isResolving ? null : audioPlayer.skipToNext,
        ),
        const Gap(5),
      ],
    );
  }
}
