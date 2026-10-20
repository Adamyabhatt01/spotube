import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';

/// Play/pause + favorite controls shared by the radio tile and card.
///
/// Kept as its own [HookConsumerWidget] so both layouts get identical behavior:
/// pressing play on the live station toggles pause/resume rather than restarting
/// the stream, and the star reflects and writes the persisted favorite set.
class RadioStationActions extends HookConsumerWidget {
  const RadioStationActions({
    super.key,
    required this.station,
  });

  final RadioStation station;

  @override
  Widget build(BuildContext context, ref) {
    // Narrowed to this station's transport state: the controller itself has no
    // equality by default, so watching it here would rebuild every mounted
    // card in the grid and every rail on each volume frame and ICY title.
    final status = ref.watch(radioStationStatusProvider(station.favoriteKey));
    final isActive = status.isActive;
    // A station is "loading" only while it is the live one and the stream is
    // still connecting; any other station keeps a plain play affordance.
    final isLoading = status.isLoading;
    final isPlaying = status.isPlaying;

    final favoriteKeys = ref.watch(radioFavoriteKeysProvider);
    final favorited = favoriteKeys.contains(station.favoriteKey);

    final controller = ref.read(radioPlaybackControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.ghost(
          icon: Icon(favorited ? SpotubeIcons.heartFilled : SpotubeIcons.heart),
          onPressed: () =>
              ref.read(radioFavoritesProvider.notifier).toggle(station),
        ),
        const Gap(8),
        IconButton.secondary(
          enabled: !isLoading,
          icon: switch ((isLoading, isPlaying)) {
            (true, _) => const CircularProgressIndicator(size: 18),
            (false, true) => const Icon(SpotubeIcons.pause),
            (false, false) => const Icon(SpotubeIcons.play),
          },
          onPressed: () {
            if (!isActive) {
              controller.play(station);
            } else if (isPlaying) {
              controller.pause();
            } else {
              controller.resume();
            }
          },
        ),
      ],
    );
  }
}

/// Sidebar pin toggle for a station. Mirrors the playlist pin affordance:
/// a pin icon reflecting the pinned state, toggling the sidebar pin list
/// with a "pinned" toast on pin.
class RadioStationPinButton extends ConsumerWidget {
  const RadioStationPinButton({super.key, required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPinned = ref.watch(
      userPreferencesProvider.select(
        (s) => s.pinnedStationIds.contains(station.favoriteKey),
      ),
    );
    return IconButton.ghost(
      icon: Icon(isPinned ? SpotubeIcons.pinOn : SpotubeIcons.pinOff),
      onPressed: () {
        final wasPinned = ref
            .read(userPreferencesProvider)
            .pinnedStationIds
            .contains(station.favoriteKey);
        ref
            .read(userPreferencesProvider.notifier)
            .togglePinnedStation(station.favoriteKey);
        if (!wasPinned && context.mounted) {
          showToast(
            context: context,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(context.l10n.pinned_to_sidebar),
              );
            },
          );
        }
      },
    );
  }
}

/// Square cover: the station favicon when it has one, a radio glyph otherwise.
///
/// The corner radius defaults to the list-tile artwork radius; grid cards
/// pass the shared card radius so both layouts match their Playbutton
/// counterparts instead of carrying their own geometry.
class RadioStationCover extends StatelessWidget {
  const RadioStationCover({
    super.key,
    required this.station,
    required this.size,
    this.radius,
  });

  final RadioStation station;
  final double size;
  final BorderRadiusGeometry? radius;

  @override
  Widget build(BuildContext context) {
    final radius = this.radius ?? context.theme.borderRadiusMd;
    final faviconUrl = station.faviconUrl;
    // The station API occasionally returns an empty or non-remote string.
    // Passing that to [UniversalImage] reads it as an asset/memory path and
    // logs `Unable to load asset: "<station name>"`; only real URLs are
    // network-fetched, everything else gets the glyph.
    final hasRemoteFavicon = faviconUrl != null &&
        (faviconUrl.startsWith('http://') ||
            faviconUrl.startsWith('https://'));
    if (!hasRemoteFavicon) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.theme.colorScheme.secondary,
          borderRadius: radius,
        ),
        child: Icon(
          SpotubeIcons.radio,
          size: size * 0.45,
          color: context.theme.colorScheme.secondaryForeground,
        ),
      );
    }

    final decodeSide = (size * context.theme.scaling * 2).roundToDouble();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: radius),
      child: UniversalImage(
        path: faviconUrl,
        width: decodeSide,
        height: decodeSide,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// A single line [RadioStation], used by the compact (mobile) list layout.
/// Marks the live station with an "On air" pill so the currently playing row
/// reads at a glance; the transport controls already reflect play state.
class RadioStationTile extends ConsumerWidget {
  const RadioStationTile({super.key, required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, ref) {
    final scale = context.theme.scaling;
    final isOnAir = ref.watch(radioPlaybackControllerProvider.select(
      (s) => s.activeStation?.favoriteKey == station.favoriteKey && s.playing,
    ));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          RadioStationCover(station: station, size: 50 * scale),
          const Gap(12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOnAir) ...[
                      const Gap(8),
                      const _OnAirPill(),
                    ],
                  ],
                ),
                if (station.subtitle
                    case final String subtitle
                    when subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
              ],
            ),
          ),
          const Gap(8),
          RadioStationPinButton(station: station),
          const Gap(8),
          RadioStationActions(station: station),
        ],
      ),
    );
  }
}

/// A grid [RadioStation] card, used once the viewport is medium-and-up.
///
/// Built on [CardImage] so it occupies the same fixed [gridCardHeight] cell as
/// every other browse card. The favorite/play actions ride a hover-revealed
/// overlay pinned to the cover's bottom-right — the same slot the shared
/// playbutton card uses — and the overlay reuses [RadioStationActions]
/// verbatim, so card and list share one set of behaviors.
class RadioStationCard extends ConsumerWidget {
  const RadioStationCard({super.key, required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context, ref) {
    final coverSize = context.gridCardWidth;
    final subtitle = station.subtitle;
    return SizedBox(
      width: coverSize,
      child: CardImage(
        image: Stack(
          children: [
            RadioStationCover(
              station: station,
              size: coverSize,
              radius: BorderRadius.circular(context.cardCornerRadius),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: StatedWidget.builder(
                builder: (context, states) {
                  final revealed =
                      states.contains(WidgetState.hovered) || kIsMobile;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: revealed ? 1 : 0,
                    child: RadioStationPinButton(station: station),
                  );
                },
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: StatedWidget.builder(
                builder: (context, states) {
                  final revealed =
                      states.contains(WidgetState.hovered) || kIsMobile;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: revealed ? 1 : 0,
                    child: RadioStationActions(station: station),
                  );
                },
              ),
            ),
          ],
        ),
        title: Tooltip(
          tooltip: TooltipContainer(child: Text(station.name)).call,
          child: Text(
            station.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // A blank line keeps the two-line subtitle slot the shared card
        // reserves, so rows with and without metadata stay the same height.
        subtitle: Text(
          subtitle == null || subtitle.isEmpty ? '\n' : subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Tapping the cover starts (or restarts) the stream; pause lives on the
        // overlay so the two actions stay distinct.
        onPressed: () =>
            ref.read(radioPlaybackControllerProvider.notifier).play(station),
      ),
    );
  }
}

/// The compact "On air" marker shown beside the live station in the list.
class _OnAirPill extends StatelessWidget {
  const _OnAirPill();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = theme.colorScheme.destructive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: theme.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        'On air',
        style: theme.typography.xSmall.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10 * theme.scaling,
        ),
      ),
    );
  }
}
