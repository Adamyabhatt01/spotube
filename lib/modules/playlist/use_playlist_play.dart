import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';

/// First page of [playlist]'s tracks for an immediate queue load.
///
/// [read] is a `read` tear-off (`WidgetRef.read` in widgets,
/// `ProviderContainer.read` in tests) — the helpers only ever read, which is
/// also what makes them unit-testable without pumping widgets.
///
/// Liked Tracks reads the `savedTracks` snapshot (stale-while-revalidate, so
/// it answers offline). A regular playlist reads the network provider, and on
/// failure falls back to the mirror — the same rule `PlaylistPage` renders
/// by — so an offline mirrored playlist still plays its downloaded subset.
/// Throws when neither answers (never mirrored, unreachable); callers turn
/// that into a toast, never a dead tap.
Future<List<SpotubeFullTrackObject>> fetchPlaylistInitialTracks(
  T Function<T>(ProviderListenable<T> provider) read,
  SpotubeSimplePlaylistObject playlist,
) async {
  if (playlist.id == likedTracksPlaylistId) {
    final tracks = await read(metadataPluginSavedTracksProvider.future);
    return tracks.items;
  }

  try {
    final result = await read(
      metadataPluginPlaylistTracksProvider(playlist.id).future,
    );
    return result.items;
  } catch (e, stack) {
    // An empty playlist is a legitimate `[]` from the network above, never
    // from here: an empty mirror means there is nothing to serve, so the
    // original failure propagates and the caller toasts instead of
    // silently loading nothing.
    final mirrored = await read(
      mirroredPlaylistTracksProvider(playlist.id).future,
    );
    if (mirrored.isEmpty) Error.throwWithStackTrace(e, stack);
    return mirrored;
  }
}

/// The whole [playlist] for queue completion and remote playback.
///
/// Page 1 first (so audio starts on the tap), then the provider walk.
/// Offline the walk throws and the already-loaded page 1 is what plays —
/// `appendCollectionTail` drops a failed tail by design.
Future<List<SpotubeFullTrackObject>> fetchPlaylistAllTracks(
  T Function<T>(ProviderListenable<T> provider) read,
  SpotubeSimplePlaylistObject playlist,
) async {
  await fetchPlaylistInitialTracks(read, playlist);

  if (playlist.id == likedTracksPlaylistId) {
    return read(metadataPluginSavedTracksProvider.notifier).fetchAll();
  }

  return read(metadataPluginPlaylistTracksProvider(playlist.id).notifier)
      .fetchAll();
}

typedef UsePlaylistPlay = ({
  bool isPlaylistPlaying,
  /// Whether the audio is currently sounding.
  ///
  /// Distinct from [isPlaylistPlaying]: the collection stays in the queue
  /// while paused, so the play/pause icon has to follow the audio.
  bool isPlaying,
  bool isLoading,
  Future<List<SpotubeFullTrackObject>> Function() fetchInitialTracks,
  Future<List<SpotubeFullTrackObject>> Function() fetchAllTracks,
  Future<void> Function() onPlaybuttonPressed,
});

/// Play/pause for a playlist card or sidebar pin: pause while this collection
/// plays, resume while it is paused, otherwise load page 1 with autoplay and
/// stream the tail in behind it. Extracted verbatim from `PlaylistCard` so
/// both surfaces share one playback path (including the Connect remote
/// branch and the history write).
UsePlaylistPlay usePlaylistPlay(
  WidgetRef ref,
  SpotubeSimplePlaylistObject playlist,
) {
  final context = useContext();
  // Perf: only collection membership is consumed (isPlaylistPlaying).
  final playlistCollections =
      ref.watch(audioPlayerProvider.select((s) => s.collections));
  final playlistNotifier = ref.watch(audioPlayerProvider.notifier);
  final historyNotifier = ref.read(playbackHistoryActionsProvider);
  final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;

  final playing =
      useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;

  final isPlaylistPlaying = useMemoized<bool>(
    () => playlistCollections.contains(playlist.id),
    [playlistCollections, playlist.id],
  );
  // Short-circuits the watch, so only the tile that is actually in the queue
  // subscribes: a track change used to rebuild every visible card.
  final isResolving =
      isPlaylistPlaying && ref.watch(isResolvingActiveTrackProvider);

  final updating = useState(false);

  final fetchInitialTracks = useCallback(
    () => fetchPlaylistInitialTracks(ref.read, playlist),
    [playlist, ref],
  );

  final fetchAllTracks = useCallback(
    () => fetchPlaylistAllTracks(ref.read, playlist),
    [playlist, ref],
  );

  final onPlaybuttonPressed = useCallback(() async {
    try {
      // Pause/resume has no preparation step and must not flash the button
      // into a spinner while the player is still stopping/starting.
      if (isPlaylistPlaying) {
        return playing ? audioPlayer.pause() : audioPlayer.resume();
      }

      updating.value = true;

      late final List<SpotubeFullTrackObject> fetchedInitialTracks;
      try {
        fetchedInitialTracks = await fetchInitialTracks();
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
        if (!context.mounted) return;
        // A tap that loads nothing used to end in an unhandled async throw.
        // Offline (or with nothing cached) say so; anything else is unexpected.
        showToast(
          context: context,
          builder: (context, overlay) => SurfaceCard(
            child: Text(
              isOnline
                  ? context.l10n.something_went_wrong
                  : context.l10n.you_are_offline,
            ),
          ),
        );
        return;
      }

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
    ref,
    playlist,
    playlistNotifier,
    historyNotifier,
    fetchAllTracks,
    updating,
    isOnline,
  ]);

  return (
    isPlaylistPlaying: isPlaylistPlaying,
    isPlaying: isPlaylistPlaying && playing,
    isLoading: isResolving || updating.value,
    fetchInitialTracks: fetchInitialTracks,
    fetchAllTracks: fetchAllTracks,
    onPlaybuttonPressed: onPlaybuttonPressed,
  );
}
