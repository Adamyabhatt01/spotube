import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/components/play_pause_icon.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/playlist/playlist_context_menu.dart';
import 'package:spotube/modules/playlist/playlist_delete.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/modules/root/sidebar/sidebar_pin_cover.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

/// One pinned playlist row: the label navigates, the cover plays.
///
/// This is deliberately different from `PlaylistCard`, whose cover and title
/// both open the playlist; the sidebar keeps its dedicated play affordance.
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
    final queueUpdating = useState(false);
    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final historyNotifier = ref.read(playbackHistoryActionsProvider);
    final me = ref.watch(metadataPluginUserProvider);
    final isOwner = playlist.owner.id == me.asData?.value?.id &&
        me.asData?.value?.id != null;

    // Same add-to-queue path as PlaylistCard: page 1 + streamed tail behind
    // it, with an undo toast.
    final onAddToQueuePressed = useCallback(() async {
      queueUpdating.value = true;
      try {
        if (play.isPlaylistPlaying) return;
        final fetched = await play.fetchAllTracks();
        if (fetched.isEmpty) return;
        await playlistNotifier.addTracks(fetched);
        await playlistNotifier.addCollection(playlist.id);
        await historyNotifier.addPlaylists([playlist]);
        if (context.mounted) {
          showToast(
            context: context,
            builder: (context, overlay) => SurfaceCard(
              child: Basic(
                content: Text(
                  context.l10n.added_num_tracks_to_queue(fetched.length),
                ),
                trailing: Button.outline(
                  child: Text(context.l10n.undo),
                  onPressed: () {
                    playlistNotifier.removeTracks(fetched.map((e) => e.id));
                  },
                ),
              ),
            ),
          );
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      } finally {
        queueUpdating.value = false;
      }
    }, [
      play.isPlaylistPlaying,
      play.fetchAllTracks,
      playlistNotifier,
      playlist.id,
      playlist,
      historyNotifier,
      context,
      queueUpdating,
    ]);

    final router = context.watchRouter;
    final selected = router.currentPath.startsWith(tile.pathPrefix);

    final scaling = Theme.of(context).scaling;

    return PlaylistContextMenu(
      playlist: playlist,
      isOwner: isOwner,
      isPinned: true,
      isPlaying: play.isPlaying,
      isLoading: play.isLoading,
      isQueueLoading: queueUpdating.value,
      onOpen: () => openSideBarTile(context, ref, tile),
      onPlayPause: play.onPlaybuttonPressed,
      onAddToQueue: onAddToQueuePressed,
      onTogglePin: () => ref
          .read(userPreferencesProvider.notifier)
          .togglePinnedPlaylist(playlist.id),
      onDelete: () => deletePlaylistWithConfirmation(context, ref.read, playlist.id),
      child: NavigationButton(
      // Same explicit style/alignment contract as the other sidebar rows:
      // the reorderable wrapper re-scopes sidebar container data (see
      // SidebarReorderableItem). In the rail the real container data still
      // applies, so nothing is passed there.
      style: selected
          ? const ButtonStyle.secondary()
          : (showLabels ? const ButtonStyle.ghost() : null),
      alignment: showLabels ? AlignmentDirectional.centerStart : null,
      label: showLabels
          ? Text(tile.title, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      overflow: NavigationOverflow.ellipsis,
      onPressed: () {
        openSideBarTile(context, ref, tile);
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
                            borderRadius: BorderRadius.circular(6 * scaling),
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
      ),
    );
  }
}
