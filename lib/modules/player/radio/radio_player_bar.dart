import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/player/radio/radio_player_actions.dart';
import 'package:spotube/modules/player/radio/radio_player_controls.dart';
import 'package:spotube/modules/player/radio/radio_player_track_details.dart';
import 'package:spotube/modules/player/volume_slider.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// The docked bottom bar while a radio station owns audio focus. It reproduces
/// the music `BottomPlayer`'s exact shell — a full-width [SurfaceCard] with the
/// same three-column [Row] — so the swap between sources is seamless, but every
/// child is radio-specific (no scrubber, no queue).
class RadioBottomPlayer extends StatelessWidget {
  const RadioBottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      borderRadius: BorderRadius.zero,
      surfaceBlur: context.theme.surfaceBlur,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: RadioPlayerTrackDetails(coverSize: 80),
          ),
          // transport
          Flexible(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.only(top: 5),
              child: RadioPlayerControls(),
            ),
          ),
          // options + volume
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioPlayerActions(),
              RadioBottomPlayerVolume(),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bar's volume control, mirroring `BottomPlayerVolume` (same
/// `volumeControlMode` preference and geometry) but wired to the radio
/// player's own volume rather than the music `volumeProvider`.
class RadioBottomPlayerVolume extends ConsumerWidget {
  const RadioBottomPlayerVolume({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final mode =
        ref.watch(userPreferencesProvider.select((s) => s.volumeControlMode));
    if (mode == VolumeControlMode.hidden) return const SizedBox.shrink();

    final volume =
        ref.watch(radioPlaybackControllerProvider.select((s) => s.volume));
    return Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.only(right: 10),
      child: VolumeSlider(
        fullWidth: true,
        revealOnHover: mode == VolumeControlMode.hover,
        value: volume,
        onChanged: (value) {
          ref.read(radioPlaybackControllerProvider.notifier).setVolume(value);
        },
      ),
    );
  }
}
