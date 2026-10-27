import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/presentation_state.dart';

import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';

Future<void> Function(SpotubeTrackObject track) useTrackTilePlayCallback(
  WidgetRef ref,
) {
  final context = useContext();
  final options = TrackPresentationOptions.of(context);
  final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
  final historyNotifier = ref.watch(playbackHistoryActionsProvider);

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
      // Same rule as the local branch, but against the *remote* queue: the
      // collection being loaded there does not prove this row is in it, and
      // jumping the local player would move the wrong device. A missing row
      // is loaded (and appended when the fetched page lacks it), not jumped.
      final remoteIndex =
          remoteQueue.tracks.indexWhere((element) => element.id == track.id);
      if (remoteIndex != -1) {
        await remotePlayback.jumpTo(remoteIndex);
      } else {
        final tracks = await options.pagination.onFetchAll();
        // The screen may show a sorted or filtered order, so the tapped
        // track's position has to be resolved against this list by id.
        var initialIndex =
            tracks.indexWhere((element) => element.id == track.id);
        final tracksToLoad = initialIndex == -1
            ? <SpotubeTrackObject>[...tracks, track]
            : tracks;
        if (initialIndex == -1) initialIndex = tracksToLoad.length - 1;

        await remotePlayback.load(
          options.collection is SpotubeSimpleAlbumObject
              ? WebSocketLoadEventData.album(
                  tracks: tracksToLoad,
                  collection: options.collection as SpotubeSimpleAlbumObject,
                  initialIndex: initialIndex,
                )
              : WebSocketLoadEventData.playlist(
                  tracks: tracksToLoad,
                  collection: options.collection as SpotubeSimplePlaylistObject,
                  initialIndex: initialIndex,
                ),
        );
      }
    } else {
      // Read fresh queue state at tap time instead of watching it.
      final queueTracks = ref.read(audioPlayerProvider.select((s) => s.tracks));
      // Membership, not collection membership: a collection can be listed as
      // active while the tapped row is not in the queue at all (the tail
      // append failed, or only part of a paginated collection was added).
      // Jumping to a missing index is a silent no-op, so the old track kept
      // playing and every tap on that row looked dead. Load the collection
      // instead, exactly as a tap from a non-active collection would.
      if (AudioPlayerState.listContainsTrack(queueTracks, track)) {
        await playlistNotifier.jumpToTrack(track);
      } else {
        // Start on the page already on screen; the tail of the collection
        // streams into the queue in the background.
        final initialTracks = options.tracks;
        // The rows render `presentationTracks`, which the sort dropdown and
        // the track filter reorder relative to this list. The queue loads in
        // `initialTracks` order, so start on the tapped track by id — using
        // the visible row number here would play a different song.
        var initialIndex =
            initialTracks.indexWhere((element) => element.id == track.id);
        // A visible row can be missing from the loaded list (pagination and
        // the presentation provider are separate). Loading with -1 clamps to
        // 0, i.e. plays the wrong song; append the tapped row instead.
        final tracksToLoad = initialIndex == -1
            ? <SpotubeTrackObject>[...initialTracks, track]
            : initialTracks;
        if (initialIndex == -1) initialIndex = tracksToLoad.length - 1;

        await playlistNotifier.load(
          tracksToLoad,
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
  }, [options, playlistNotifier, historyNotifier]);

  return onTapTrackTile;
}
