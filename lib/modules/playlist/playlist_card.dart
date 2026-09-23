import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/components/playbutton_view/playbutton_tile.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

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
    // Perf: only collection membership is consumed (isPlaylistPlaying).
    final playlistCollections =
        ref.watch(audioPlayerProvider.select((s) => s.collections));
    final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
    final historyNotifier = ref.read(playbackHistoryActionsProvider);

    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;

    final isPlaylistPlaying = useMemoized<bool>(
      () => playlistCollections.contains(playlist.id),
      [playlistCollections, playlist.id],
    );
    // Short-circuits the watch, so only the card that is actually in the queue
    // subscribes: a track change used to rebuild every visible card.
    final isFetchingActiveTrack =
        isPlaylistPlaying && ref.watch(queryingTrackInfoProvider);

    final updating = useState(false);
    final me = ref.watch(metadataPluginUserProvider);

    final fetchInitialTracks = useCallback(() async {
      if (playlist.id == 'user-liked-tracks') {
        final tracks = await ref.read(metadataPluginSavedTracksProvider.future);
        return tracks.items;
      }

      final result = await ref
          .read(metadataPluginPlaylistTracksProvider(playlist.id).future);

      return result.items;
    }, [playlist.id, ref]);

    final fetchAllTracks = useCallback(() async {
      await fetchInitialTracks();

      if (playlist.id == 'user-liked-tracks') {
        return ref.read(metadataPluginSavedTracksProvider.notifier).fetchAll();
      }

      return ref
          .read(metadataPluginPlaylistTracksProvider(playlist.id).notifier)
          .fetchAll();
    }, [playlist.id, ref, fetchInitialTracks]);

    final onTap = useCallback(() {
      context.navigateTo(PlaylistRoute(id: playlist.id, playlist: playlist));
    }, [context, playlist]);

    final onPlaybuttonPressed = useCallback(() async {
      try {
        updating.value = true;
        if (isPlaylistPlaying && playing) {
          return audioPlayer.pause();
        } else if (isPlaylistPlaying && !playing) {
          return audioPlayer.resume();
        }

        final fetchedInitialTracks = await fetchInitialTracks();

        if (fetchedInitialTracks.isEmpty || !context.mounted) return;

        final isRemoteDevice = await showSelectDeviceDialog(context, ref);
        if (isRemoteDevice == null) return;
        if (isRemoteDevice) {
          final remotePlayback = ref.read(connectProvider.notifier);
          final allTracks = await fetchAllTracks();
          await remotePlayback.load(
            WebSocketLoadEventData.playlist(
              tracks: allTracks,
              collection: playlist,
            ),
          );
        } else {
          await playlistNotifier.load(fetchedInitialTracks, autoPlay: true);
          playlistNotifier.addCollection(playlist.id);
          historyNotifier.addPlaylists([playlist]);

          unawaited(appendCollectionTail(
            appendTail: (tail) => playlistNotifier.addTracks(tail),
            readCollections: () => ref.read(audioPlayerProvider).collections,
            collectionId: playlist.id,
            alreadyLoaded: fetchedInitialTracks,
            fetchAll: fetchAllTracks,
          ));
        }
      } finally {
        if (context.mounted) {
          updating.value = false;
        }
      }
    }, [
      isPlaylistPlaying,
      playing,
      fetchInitialTracks,
      context,
      showSelectDeviceDialog,
      ref,
      connectProvider,
      fetchAllTracks,
      playlistNotifier,
      playlist.id,
      historyNotifier,
      playlist,
      updating
    ]);

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

    final isLoading =
        (isPlaylistPlaying && isFetchingActiveTrack) || updating.value;
    final isOwner = playlist.owner.id == me.asData?.value?.id &&
        me.asData?.value?.id != null;

    if (_isTile) {
      return PlaybuttonTile(
        title: playlist.name,
        description: playlist.description,
        image: null,
        imageUrl: imageUrl,
        isPlaying: isPlaylistPlaying,
        isLoading: isLoading,
        isOwner: isOwner,
        onTap: onTap,
        onPlaybuttonPressed: onPlaybuttonPressed,
        onAddToQueuePressed: onAddToQueuePressed,
      );
    }

    return PlaybuttonCard(
      title: playlist.name,
      description: playlist.description,
      image: null,
      imageUrl: imageUrl,
      isPlaying: isPlaylistPlaying,
      isLoading: isLoading,
      isOwner: isOwner,
      onTap: onTap,
      onPlaybuttonPressed: onPlaybuttonPressed,
      onAddToQueuePressed: onAddToQueuePressed,
    );
  }
}
