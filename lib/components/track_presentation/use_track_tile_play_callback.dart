import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/presentation_state.dart';
import 'package:spotube/extensions/list.dart';

import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';

Future<void> Function(SpotubeTrackObject track) useTrackTilePlayCallback(
  WidgetRef ref,
) {
  final context = useContext();
  final options = TrackPresentationOptions.of(context);
  // Perf: only the collection membership drives the memoized callback.
  final playlistCollections =
      ref.watch(audioPlayerProvider.select((s) => s.collections));
  final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
  final historyNotifier = ref.watch(playbackHistoryActionsProvider);

  final isActive = useMemoized(
    () => playlistCollections.contains(options.collectionId),
    [playlistCollections, options.collectionId],
  );

  final onTapTrackTile = useCallback((SpotubeTrackObject track) async {
    final state = ref.read(presentationStateProvider(options.collection));
    final notifier =
        ref.read(presentationStateProvider(options.collection).notifier);

    if (state.selectedTracks.isNotEmpty) {
      if (state.selectedTracks.contains(track)) {
        notifier.deselectTrack(track);
      } else {
        notifier.selectTrack(track);
      }
      return;
    }

    final isRemoteDevice = await showSelectDeviceDialog(context, ref);
    if (isRemoteDevice == null) return;

    if (isRemoteDevice) {
      final remotePlayback = ref.read(connectProvider.notifier);
      final remoteQueue = ref.read(queueProvider);
      if (remoteQueue.collections.contains(options.collectionId) ||
          remoteQueue.tracks.any((s) => s.id == track.id)) {
        await playlistNotifier.jumpToTrack(track);
      } else {
        final tracks = await options.pagination.onFetchAll();
        // The screen may show a sorted or filtered order, so the tapped
        // track's position has to be resolved against this list by id.
        final initialIndex =
            tracks.indexWhere((element) => element.id == track.id);
        await remotePlayback.load(
          options.collection is SpotubeSimpleAlbumObject
              ? WebSocketLoadEventData.album(
                  tracks: tracks,
                  collection: options.collection as SpotubeSimpleAlbumObject,
                  initialIndex: initialIndex,
                )
              : WebSocketLoadEventData.playlist(
                  tracks: tracks,
                  collection: options.collection as SpotubeSimplePlaylistObject,
                  initialIndex: initialIndex,
                ),
        );
      }
    } else {
      // Read fresh queue state at tap time instead of watching it.
      final queueTracks = ref.read(audioPlayerProvider.select((s) => s.tracks));
      if (isActive || queueTracks.containsBy(track, (a) => a.id)) {
        await playlistNotifier.jumpToTrack(track);
      } else {
        // Start on the page already on screen; the tail of the collection
        // streams into the queue in the background.
        final initialTracks = options.tracks;
        // The rows render `presentationTracks`, which the sort dropdown and
        // the track filter reorder relative to this list. The queue loads in
        // `initialTracks` order, so start on the tapped track by id — using
        // the visible row number here would play a different song.
        final initialIndex =
            initialTracks.indexWhere((element) => element.id == track.id);
        await playlistNotifier.load(
          initialTracks,
          initialIndex: initialIndex,
          autoPlay: true,
        );
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
    }
  }, [isActive, options, playlistNotifier, historyNotifier]);

  return onTapTrackTile;
}
