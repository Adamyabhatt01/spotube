import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/components/play_pause_icon.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';

/// One pinned playlist row: the label navigates (today's behavior), the
/// cover plays (mirroring `PlaylistCard`'s cover tap).
///
/// A per-pin widget rather than inline hooks in the sidebar's pin loop: pin
/// count changes would reorder hook calls. The desktop drag overlay grabs on
/// movement only, so a tap with no movement still reaches the cover's tap
/// below it; the gesture arena gives the inner tap the win over the row's
/// navigation tap, never both.
///
/// Intrinsic-safe by construction (see `sidebarBottomClearanceOf`): fixed
/// cover edge, no `Expanded`/`LayoutBuilder` anywhere in the row.
class SidebarPinTile extends HookConsumerWidget {
  final SideBarTiles tile;
  final bool showLabels;

  const SidebarPinTile({
    required this.tile,
    required this.showLabels,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pinned tiles always carry their playlist; static tiles never render here.
    final playlist = tile.playlist!;
    final play = usePlaylistPlay(ref, playlist);
    final hovered = useState(false);
    // The hook already excludes audible playback from `isLoading`; keep the
    // glyph correct even if a caller's preparation future outlives startup.
    final showSpinner = play.isLoading && !play.isPlaying;

    final router = context.watchRouter;
    final selected = router.currentPath.startsWith(tile.pathPrefix);

    final scaling = Theme.of(context).scaling;

    return NavigationButton(
      // Same explicit style/alignment contract as the other sidebar rows:
      // the reorderable wrapper re-scopes sidebar container data (see
      // SidebarReorderableItem). In the rail the real container data still
      // applies, so nothing is passed there.
      style: selected
          ? const ButtonStyle.secondary()
          : (showLabels ? const ButtonStyle.ghost() : null),
      alignment: showLabels ? AlignmentDirectional.centerStart : null,
      label: showLabels ? Text(tile.title) : null,
      onPressed: () {
        context.navigateTo(tile.route);
      },
      child: Tooltip(
        tooltip: TooltipContainer(child: Text(tile.title)).call,
        child: MouseRegion(
          onEnter: (_) => hovered.value = true,
          onExit: (_) => hovered.value = false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: play.isLoading && !play.isPlaying
                ? null
                : play.onPlaybuttonPressed,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Semantics(
                label: context.l10n.play,
                button: true,
                child: Stack(
                  children: [
                    SidebarPinCover(
                      imageUrl: tile.imageUrl,
                      side: sidebarPinCoverSide,
                    ),
                    if (hovered.value ||
                        play.isPlaylistPlaying ||
                        play.isLoading)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius:
                                BorderRadius.circular(6 * scaling),
                          ),
                          child: Center(
                            child: showSpinner
                                ? const CircularProgressIndicator(size: 14)
                                : AnimatedPlayPauseIcon(
                                    // The icon follows the audio, not the
                                    // queue membership: pausing from
                                    // elsewhere left the pin showing
                                    // "pause".
                                    isPlaying: play.isPlaying,
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
