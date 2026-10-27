import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/player/radio/radio_player_actions.dart';
import 'package:spotube/modules/player/radio/radio_player_controls.dart';
import 'package:spotube/modules/player/radio/radio_player_track_details.dart';
import 'package:spotube/modules/player/volume_slider.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// The mobile/narrow counterpart to [RadioBottomPlayer], mirroring the music
/// `PlayerOverlay`: a 63px collapsed strip that slides up into a full radio
/// panel. It keeps its own [PanelController] so it never shares state with the
/// music overlay across a source switch.
final radioPlayerOverlayControllerProvider =
    StateProvider<PanelController>((ref) => PanelController());

class RadioPlayerOverlay extends HookConsumerWidget {
  const RadioPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final canShow =
        ref.watch(radioPlaybackControllerProvider.select((s) => s.isRadio));
    final panelController = ref.watch(radioPlayerOverlayControllerProvider);
    final screenSize = MediaQuery.sizeOf(context);

    return SlidingUpPanel(
      maxHeight: screenSize.height,
      backdropEnabled: false,
      minHeight: canShow ? 63 : 0,
      onPanelSlide: (position) {
        ref.read(navigationPanelHeight.notifier).state = 50 * (1 - position);
      },
      controller: panelController,
      color: Colors.transparent,
      parallaxEnabled: true,
      renderPanelSheet: false,
      header: SizedBox(
        height: 63,
        width: screenSize.width,
        child: RadioPlayerCollapsedSection(panelController: panelController),
      ),
      panelBuilder: (scrollController) => RadioPlayerPanel(
        panelController: panelController,
        scrollController: scrollController,
      ),
    );
  }
}

class RadioPlayerCollapsedSection extends HookConsumerWidget {
  final PanelController panelController;
  const RadioPlayerCollapsedSection({
    super.key,
    required this.panelController,
  });

  @override
  Widget build(BuildContext context, ref) {
    final canShow =
        ref.watch(radioPlaybackControllerProvider.select((s) => s.isRadio));
    final theme = Theme.of(context);

    final shouldShow = useState(true);
    final blurFrozen = ref.watch(chromeBlurFrozen);

    ref.listen(navigationPanelHeight, (_, height) {
      shouldShow.value = height.ceil() == 50;
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: canShow && shouldShow.value
          ? Padding(
              padding: const EdgeInsets.all(5),
              child: SurfaceCard(
                surfaceBlur: blurFrozen ? 0 : theme.surfaceBlur,
                surfaceOpacity: theme.surfaceOpacity,
                padding: EdgeInsets.zero,
                borderRadius: theme.borderRadiusLg,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: RadioPlayerTrackDetails(
                        coverSize: 48,
                        onTap: panelController.open,
                      ),
                    ),
                    const Row(
                      children: [
                        RadioPlayerControls(),
                        Gap(5),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// The expanded mobile panel: large cover, station name, live title, transport,
/// volume and the radio options menu.
class RadioPlayerPanel extends HookConsumerWidget {
  final PanelController panelController;
  final ScrollController? scrollController;

  const RadioPlayerPanel({
    super.key,
    required this.panelController,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final playback = ref.watch(radioPlaybackControllerProvider);
    final station = playback.activeStation;
    if (station == null) return const SizedBox.shrink();

    final mode =
        ref.watch(userPreferencesProvider.select((s) => s.volumeControlMode));
    final layout = context.layout;
    final volumeOverride =
        themeEnforces(layout, ThemeShellKeys.volume) ? layout.player.showVolume : null;
    final showVolume = volumeOverride ?? mode != VolumeControlMode.hidden;

    return Container(
      color: theme.colorScheme.background,
      padding: EdgeInsets.all(16 * theme.scaling),
      child: ListView(
        controller: scrollController,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton.ghost(
                icon: const Icon(SpotubeIcons.close),
                onPressed: panelController.close,
              ),
            ],
          ),
          Center(
            child: RadioStationCover(
              station: station,
              size: 200 * theme.scaling,
            ),
          ),
          const Gap(16),
          Text(
            station.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.h4.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(4),
          Text(
            radioStatusLine(playback),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.small
                .copyWith(color: theme.colorScheme.mutedForeground),
          ),
          const Gap(20),
          const Center(child: RadioPlayerControls()),
          const Gap(12),
          const Center(child: RadioPlayerActions()),
          if (showVolume)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: const RadioPanelVolume(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RadioPanelVolume extends ConsumerWidget {
  const RadioPanelVolume({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final volume =
        ref.watch(radioPlaybackControllerProvider.select((s) => s.volume));
    return VolumeSlider(
      fullWidth: true,
      value: volume,
      onChanged: (value) =>
          ref.read(radioPlaybackControllerProvider.notifier).setVolume(value),
    );
  }
}
