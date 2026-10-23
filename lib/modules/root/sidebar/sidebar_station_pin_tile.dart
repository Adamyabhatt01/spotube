import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';
import 'package:spotube/provider/radio/pinned_station.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';

/// One pinned radio station row: cover and label both play.
///
/// A per-pin widget rather than inline hooks in the sidebar's pin loop, for
/// the same reason as [SidebarPinTile]: pin count changes would reorder hook
/// calls. Unlike playlists there is no station-detail route, so the whole
/// row toggles playback instead of navigating — play when another (or no)
/// station is live, pause/resume when this one is.
///
/// An unresolvable pin (never favorited, never played, directory miss)
/// renders nothing, exactly like a deleted playlist pin: skipped, never
/// a dead tile. Loading renders nothing either; the pin appears once its
/// station object arrives.
class SidebarStationPinTile extends HookConsumerWidget {
  /// Raw persisted id: the station's `provider:id` favorite key.
  final String favoriteKey;
  final bool showLabels;

  const SidebarStationPinTile({
    required this.favoriteKey,
    required this.showLabels,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(pinnedStationProvider(favoriteKey)).asData?.value;
    final hovered = useState(false);

    if (station == null) return const SizedBox.shrink();

    final status = ref.watch(radioStationStatusProvider(favoriteKey));
    final isActive = status.isActive;
    final isPlaying = status.isPlaying;
    final isLoading = status.isLoading;
    final controller = ref.read(radioPlaybackControllerProvider.notifier);

    void onTap() {
      if (isLoading) return;
      if (!isActive) {
        controller.play(station);
      } else if (isPlaying) {
        controller.pause();
      } else {
        controller.resume();
      }
    }

    final scaling = Theme.of(context).scaling;

    return NavigationButton(
      // Same explicit style/alignment contract as the other sidebar rows.
      // Active (rather than route-selected: stations have no route) reads
      // as the secondary treatment, mirroring the playlist pin's selected
      // state.
      style: isActive
          ? const ButtonStyle.secondary()
          : (showLabels ? const ButtonStyle.ghost() : null),
      alignment: showLabels ? AlignmentDirectional.centerStart : null,
      label: showLabels
          ? Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      onPressed: onTap,
      child: Tooltip(
        tooltip: TooltipContainer(child: Text(station.name)).call,
        child: MouseRegion(
          onEnter: (_) => hovered.value = true,
          onExit: (_) => hovered.value = false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                label: context.l10n.play,
                button: true,
                child: Stack(
                  children: [
                    SidebarPinCover(
                      imageUrl: station.faviconUrl,
                      side: sidebarPinCoverSide,
                      fallbackIcon: SpotubeIcons.radio,
                    ),
                    if (hovered.value || isActive)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6 * scaling),
                          ),
                          child: Center(
                            child: isLoading
                                ? const CircularProgressIndicator(size: 14)
                                : Icon(
                                    isPlaying
                                        ? SpotubeIcons.pause
                                        : SpotubeIcons.play,
                                    size: 14 * scaling,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
