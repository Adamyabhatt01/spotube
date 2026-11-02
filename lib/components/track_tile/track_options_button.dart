import 'package:auto_route/auto_route.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/links/artist_link.dart';
import 'package:spotube/components/track_tile/track_options.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/models/metadata/metadata.dart';

class TrackOptionsButton extends HookConsumerWidget {
  final SpotubeTrackObject track;
  final bool userPlaylist;
  final String? playlistId;
  final VoidCallback? onSelect;
  const TrackOptionsButton({
    super.key,
    required this.track,
    required this.userPlaylist,
    this.playlistId,
    this.onSelect,
  });

  static OverlayCompleter<dynamic> showOptions(
    BuildContext context,
    SpotubeTrackObject track, {
    bool userPlaylist = false,
    String? playlistId,
    VoidCallback? onSelect,
    Offset? position,
  }) {
    return showPopover(
      context: context,
      // A pointer-opened menu follows the cursor; the button-opened one stays
      // anchored to the tray below the row.
      position: position,
      follow: position == null,
      alignment: position == null ? Alignment.topRight : Alignment.topLeft,
      anchorAlignment: position == null ? Alignment.bottomRight : null,
      offset: position == null ? null : const Offset(4, 4),
      builder: (context) {
        return SizedBox(
          width: 220 * context.theme.scaling,
          // Without this boundary the rows inherit the track row's own
          // hovered/focused states and every entry renders as if the cursor
          // were on it. Same reason `AdaptivePopSheetList` wraps its menu.
          child: WidgetStatesProvider.boundary(
            child: Card(
              padding: const EdgeInsets.all(8),
              child: TrackOptions(
                track: track,
                playlistId: playlistId,
                userPlaylist: userPlaylist,
                onSelect: onSelect,
                onTapItem: () {
                  closeOverlay(context);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// The compact bottom-sheet variant, shared by the ⋯ button on small
  /// screens and by long-press on touch devices.
  static Future<void> showSheet(
    BuildContext context,
    SpotubeTrackObject track, {
    bool userPlaylist = false,
    String? playlistId,
    VoidCallback? onSelect,
  }) async {
    final imageProvider = UniversalImage.imageProvider(
      (track.album.images).smallest(ImagePlaceholder.albumArt),
      height: 80,
      width: 80,
    );

    await openDrawer<void>(
      context: context,
      position: OverlayPosition.bottom,
      draggable: true,
      showDragHandle: true,
      borderRadius: context.theme.borderRadiusMd,
      transformBackdrop: false,
      builder: (context) {
        return WidgetStatesProvider.boundary(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Basic(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: context.theme.borderRadiusMd,
                      image: DecorationImage(
                        fit: BoxFit.cover,
                        image: imageProvider,
                      ),
                    ),
                  ),
                  title: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).semiBold(),
                  subtitle: Align(
                    alignment: Alignment.centerLeft,
                    child: ArtistLink(
                      artists: track.artists,
                      onOverflowArtistClick: () => context.navigateTo(
                        TrackRoute(trackId: track.id),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                TrackOptions(
                  track: track,
                  userPlaylist: userPlaylist,
                  playlistId: playlistId,
                  onSelect: onSelect,
                  onTapItem: () {
                    closeDrawer(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    return IconButton.ghost(
      icon: const Icon(SpotubeIcons.moreHorizontal),
      onPressed: () {
        final mediaQuery = MediaQuery.sizeOf(context);

        if (mediaQuery.lgAndUp) {
          showOptions(
            context,
            track,
            userPlaylist: userPlaylist,
            playlistId: playlistId,
            onSelect: onSelect,
          );
        } else {
          showSheet(
            context,
            track,
            userPlaylist: userPlaylist,
            playlistId: playlistId,
            onSelect: onSelect,
          );
        }
      },
    );
  }
}
