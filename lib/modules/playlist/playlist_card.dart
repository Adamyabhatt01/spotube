import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/components/playbutton_view/playbutton_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';

class PlaylistCard extends HookConsumerWidget {
  final SpotubeSimplePlaylistObject playlist;
  final bool _isTile;

  const PlaylistCard(
    this.playlist, {
    super.key,
  }) : _isTile = false;

  const PlaylistCard.tile(
    this.playlist, {
    super.key,
  }) : _isTile = true;

  @override
  Widget build(BuildContext context, ref) {
    // Shared play path with the sidebar pins: pause/resume while this
    // collection plays, otherwise load page 1 + stream the tail behind it.
    final play = usePlaylistPlay(ref, playlist);
    final isPlaylistPlaying = play.isPlaylistPlaying;
    final updating = useState(false);
    // The hook's spinner covers playback; the card's own `updating` covers
    // add-to-queue below — together they are the original `isLoading`.
    final isLoading = play.isLoading || updating.value;
    final fetchAllTracks = play.fetchAllTracks;
    final onPlaybuttonPressed = play.onPlaybuttonPressed;

    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final historyNotifier = ref.read(playbackHistoryActionsProvider);

    final me = ref.watch(metadataPluginUserProvider);

    final onTap = useCallback(() {
      context.navigateTo(PlaylistRoute(id: playlist.id, playlist: playlist));
    }, [context, playlist]);

    final onAddToQueuePressed = useCallback(() async {
      updating.value = true;
      try {
        if (isPlaylistPlaying) return;

        final fetchedInitialTracks = await fetchAllTracks();

        if (fetchedInitialTracks.isEmpty) return;

        playlistNotifier.addTracks(fetchedInitialTracks);
        playlistNotifier.addCollection(playlist.id);
        historyNotifier.addPlaylists([playlist]);
        if (context.mounted) {
          showToast(
            context: context,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Basic(
                  content: Text(
                    context.l10n
                        .added_num_tracks_to_queue(fetchedInitialTracks.length),
                  ),
                  trailing: Button.outline(
                    child: Text(context.l10n.undo),
                    onPressed: () {
                      playlistNotifier
                          .removeTracks(fetchedInitialTracks.map((e) => e.id));
                    },
                  ),
                ),
              );
            },
          );
        }
      } finally {
        updating.value = false;
      }
    }, [
      isPlaylistPlaying,
      fetchAllTracks,
      playlistNotifier,
      playlist.id,
      historyNotifier,
      playlist,
      context,
      updating
    ]);

    final imageUrl = useMemoized(
      () => playlist.images.from200PxTo300PxOrSmallestImage(
        ImagePlaceholder.collection,
      ),
      [playlist.images],
    );

    final isOwner = playlist.owner.id == me.asData?.value?.id &&
        me.asData?.value?.id != null;

    final isPinned = ref.watch(
      userPreferencesProvider
          .select((s) => s.pinnedPlaylistIds.contains(playlist.id)),
    );
    final onPinPressed = useCallback(() {
      final wasPinned = ref
          .read(userPreferencesProvider)
          .pinnedPlaylistIds
          .contains(playlist.id);
      ref
          .read(userPreferencesProvider.notifier)
          .togglePinnedPlaylist(playlist.id);
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
    }, [playlist.id, ref, context]);

    if (_isTile) {
      return PlaybuttonTile(
        title: playlist.name,
        description: playlist.description,
        image: null,
        imageUrl: imageUrl,
        isPlaying: isPlaylistPlaying,
        // The icon follows the audio, not the queue membership: pausing
        // from elsewhere left the button showing "pause".
        isActuallyPlaying: play.isPlaying,
        isLoading: isLoading,
        isOwner: isOwner,
        isPinned: isPinned,
        onTap: onTap,
        onPlaybuttonPressed: onPlaybuttonPressed,
        onAddToQueuePressed: onAddToQueuePressed,
        onPinPressed: onPinPressed,
      );
    }

    return PlaybuttonCard(
      title: playlist.name,
      description: playlist.description,
      image: null,
      imageUrl: imageUrl,
      isPlaying: isPlaylistPlaying,
      // The icon follows the audio, not the queue membership: pausing from
      // elsewhere left the button showing "pause".
      isActuallyPlaying: play.isPlaying,
      isLoading: isLoading,
      isOwner: isOwner,
      isPinned: isPinned,
      onTap: onTap,
      onPlaybuttonPressed: onPlaybuttonPressed,
      onAddToQueuePressed: onAddToQueuePressed,
      onPinPressed: onPinPressed,
    );
  }
}
