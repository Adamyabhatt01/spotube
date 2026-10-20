import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/components/track_presentation/presentation_actions.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';

import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

typedef UseActionCallbacks = ({
  /// Whether this collection is in the player's queue.
  bool isActive,
  /// Whether the audio is currently sounding.
  ///
  /// Distinct from [isActive]: a collection stays in the queue while
  /// paused, so the play/pause icon has to follow the audio.
  bool isPlaying,
  /// Whether starting playback is still being prepared.
  bool isPlayLoading,
  /// Whether the shuffle action is still being prepared.
  bool isShuffleLoading,
  /// Whether the collection has at least one loaded track.
  ///
  /// Header actions stay disabled until this is true: a tap during the first
  /// page load (or on an empty collection) must never reach
  /// [Random.nextInt] with a length of zero.
  bool hasTracks,
  Future<void> Function() onShuffle,
  Future<void> Function() onPlay,
  VoidCallback onAddToQueue,
});

UseActionCallbacks useActionCallbacks(WidgetRef ref) {
  final isPlayLoading = useState(false);
  final isShuffleLoading = useState(false);
  final context = useContext();
  final options = TrackPresentationOptions.of(context);
  // Perf: only the collection membership is consumed (isActive memo).
  final playlistCollections =
      ref.watch(audioPlayerProvider.select((s) => s.collections));
  final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
  final historyNotifier = ref.watch(playbackHistoryActionsProvider);

  final isActive = useMemoized(
    () => playlistCollections.contains(options.collectionId),
    [playlistCollections, options.collectionId],
  );

  // Whether the audio is actually sounding right now. Narrowly selected so
  // the header only rebuilds on start/stop, not on queue edits.
  final isPlaying = ref.watch(
    audioPlayerProvider.select((s) => s.playing),
  );

  final onShuffle = useCallback(() async {
    try {
      isShuffleLoading.value = true;

      final initialTracks = options.tracks;
      if (!context.mounted) return;

      final isRemoteDevice = await showSelectDeviceDialog(context, ref);
      if (isRemoteDevice == null) return;
      if (isRemoteDevice) {
        final allTracks = await options.pagination.onFetchAll();
        if (allTracks.isEmpty) return;
        final remotePlayback = ref.read(connectProvider.notifier);
        await remotePlayback.load(
          options.collection is SpotubeSimpleAlbumObject
              ? WebSocketLoadEventData.album(
                  tracks: allTracks,
                  collection: options.collection as SpotubeSimpleAlbumObject,
                  initialIndex: Random().nextInt(allTracks.length))
              : WebSocketLoadEventData.playlist(
                  tracks: allTracks,
                  collection: options.collection as SpotubeSimplePlaylistObject,
                  initialIndex: Random().nextInt(allTracks.length),
                ),
        );
        await remotePlayback.setShuffle(true);
      } else {
        // An empty list has no valid `nextInt` index. Stopping here keeps the
        // old crash (`RangeError: 0`) unreachable even if a caller forgets to
        // disable the button while the collection is still loading.
        if (initialTracks.isEmpty) return;

        await playlistNotifier.load(
          initialTracks,
          autoPlay: true,
          initialIndex: Random().nextInt(initialTracks.length),
        );
        await audioPlayer.setShuffle(true);
        playlistNotifier.addCollection(options.collectionId);
        if (options.collection is SpotubeSimpleAlbumObject) {
          historyNotifier
              .addAlbums([options.collection as SpotubeSimpleAlbumObject]);
        } else {
          historyNotifier.addPlaylists(
              [options.collection as SpotubeSimplePlaylistObject]);
        }

        unawaited(appendCollectionTail(
          appendTail: (tail) => playlistNotifier.addTracks(tail),
          readCollections: () => ref.read(audioPlayerProvider).collections,
          collectionId: options.collectionId,
          alreadyLoaded: initialTracks,
          fetchAll: options.pagination.onFetchAll,
        ));
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    } finally {
      isShuffleLoading.value = false;
    }
  }, [options, playlistNotifier, historyNotifier]);

  final onPlay = useCallback(() async {
    try {
      // Already loaded: toggle the existing playback instead of reloading
      // the collection from the top. This is what makes the header button a
      // real pause/resume control, and what lets the icon follow the audio
      // rather than the queue membership.
      //
      // Checked before the device dialog, like the album and playlist cards
      // do: a pause/resume has no target device to pick.
      if (isActive) {
        if (isPlaying) {
          await audioPlayer.pause();
        } else {
          await audioPlayer.resume();
        }
        return;
      }

      isPlayLoading.value = true;

      final initialTracks = options.tracks;

      if (!context.mounted) return;

      final isRemoteDevice = await showSelectDeviceDialog(context, ref);
      if (isRemoteDevice == null) return;
      if (isRemoteDevice) {
        final allTracks = await options.pagination.onFetchAll();
        if (allTracks.isEmpty) return;

        final remotePlayback = ref.read(connectProvider.notifier);
        await remotePlayback.load(
          options.collection is SpotubeSimpleAlbumObject
              ? WebSocketLoadEventData.album(
                  tracks: allTracks,
                  collection: options.collection as SpotubeSimpleAlbumObject,
                )
              : WebSocketLoadEventData.playlist(
                  tracks: allTracks,
                  collection: options.collection as SpotubeSimplePlaylistObject,
                ),
        );
      } else {
        if (initialTracks.isEmpty) return;

        await playlistNotifier.load(initialTracks, autoPlay: true);
        playlistNotifier.addCollection(options.collectionId);

        if (options.collection is SpotubeSimpleAlbumObject) {
          historyNotifier.addAlbums(
            [options.collection as SpotubeSimpleAlbumObject],
          );
        } else {
          historyNotifier.addPlaylists(
            [options.collection as SpotubeSimplePlaylistObject],
          );
        }

        unawaited(appendCollectionTail(
          appendTail: (tail) => playlistNotifier.addTracks(tail),
          readCollections: () => ref.read(audioPlayerProvider).collections,
          collectionId: options.collectionId,
          alreadyLoaded: initialTracks,
          fetchAll: options.pagination.onFetchAll,
        ));
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    } finally {
      if (context.mounted) {
        isPlayLoading.value = false;
      }
    }
  }, [options, playlistNotifier, historyNotifier, isActive, isPlaying]);

  final onAddToQueue = useCallback(() {
    final tracks = options.tracks;
    if (tracks.isEmpty) return;
    playlistNotifier.addTracks(tracks);
    playlistNotifier.addCollection(options.collectionId);
    if (options.collection is SpotubeSimpleAlbumObject) {
      historyNotifier
          .addAlbums([options.collection as SpotubeSimpleAlbumObject]);
    } else {
      historyNotifier
          .addPlaylists([options.collection as SpotubeSimplePlaylistObject]);
    }
    if (!context.mounted) return;
    showToastForAction(context, "add-to-queue", tracks.length);
  }, [options, playlistNotifier, historyNotifier]);

  return (
    isActive: isActive,
    isPlaying: isPlaying,
    isPlayLoading: isPlayLoading.value,
    isShuffleLoading: isShuffleLoading.value,
    hasTracks: options.tracks.isNotEmpty,
    onShuffle: onShuffle,
    onPlay: onPlay,
    onAddToQueue: onAddToQueue,
  );
}
