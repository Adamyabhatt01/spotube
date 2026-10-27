part of '../home_search_suggestions.dart';

/// Reads the currently loaded library lists without subscribing — the panel
/// only lives while typing, and the enclosing bar rebuilds (recreating the
/// closure) on every keystroke anyway.
({
  List<SpotubeFullTrackObject> tracks,
  List<SpotubeSimplePlaylistObject> playlists,
  List<SpotubeSimpleAlbumObject> albums,
  List<SpotubeFullArtistObject> artists,
}) readLibrarySnapshot(WidgetRef ref) {
  return (
    tracks: ref.read(metadataPluginSavedTracksProvider).asData?.value.items ??
        const <SpotubeFullTrackObject>[],
    playlists:
        ref.read(metadataPluginSavedPlaylistsProvider).asData?.value.items ??
            const <SpotubeSimplePlaylistObject>[],
    albums: ref.read(metadataPluginSavedAlbumsProvider).asData?.value.items ??
        const <SpotubeSimpleAlbumObject>[],
    artists: ref.read(metadataPluginSavedArtistsProvider).asData?.value.items ??
        const <SpotubeFullArtistObject>[],
  );
}

/// Opens a library suggestion's page. Recent and see-all rows are submits,
/// not navigations, so they never reach this — [LibrarySearchSuggestion] is
/// the exhaustive set.
void openLibrarySuggestion(
  BuildContext context,
  FocusNode focusNode,
  LibrarySearchSuggestion option,
) {
  focusNode.unfocus();
  switch (option) {
    case TrackSearchSuggestion(:final track):
      context.navigateTo(TrackRoute(trackId: track.id));
    case PlaylistSearchSuggestion(:final playlist):
      context.navigateTo(
        PlaylistRoute(id: playlist.id, playlist: playlist),
      );
    case AlbumSearchSuggestion(:final album):
      context.navigateTo(AlbumRoute(id: album.id, album: album));
    case ArtistSearchSuggestion(:final artist):
      context.navigateTo(ArtistRoute(artistId: artist.id));
  }
}

/// Opens an artist credited on a row. Song and album credits carry the
/// lighter [SpotubeSimpleArtistObject], not the full object a search hit
/// produces, so they cannot go through [openLibrarySuggestion] — but they end
/// up on the same route.
void openCreditedArtist(
  BuildContext context,
  FocusNode focusNode,
  SpotubeSimpleArtistObject artist,
) {
  focusNode.unfocus();
  context.navigateTo(ArtistRoute(artistId: artist.id));
}

/// The panel's play button: songs play directly, albums and playlists load
/// their collection, artists load their top tracks — the same actions the grid
/// cards' play buttons perform. The caller opens the page alongside it.
Future<void> playLibrarySuggestion(
  BuildContext context,
  WidgetRef ref,
  LibrarySearchSuggestion option,
) async {
  switch (option) {
    case TrackSearchSuggestion(:final track):
      final notifier = ref.read(audioPlayerProvider.notifier);
      final queue = ref.read(audioPlayerProvider);
      if (queue.tracks.any((element) => element.id == track.id)) {
        await notifier.jumpToTrack(track);
        return;
      }
      await notifier.load([track], autoPlay: true);
      unawaited(ref.read(playbackHistoryActionsProvider).addTrack(track));
    case AlbumSearchSuggestion(:final album):
      if (_resumeIfLoaded(ref, album.id)) return;
      Future<List<SpotubeFullTrackObject>> fetchInitial() async =>
          (await ref.read(metadataPluginAlbumTracksProvider(album.id).future))
              .items;
      Future<List<SpotubeFullTrackObject>> fetchAll() async {
        await fetchInitial();
        return ref
            .read(metadataPluginAlbumTracksProvider(album.id).notifier)
            .fetchAll();
      }

      await _playCollection(
        context,
        ref,
        collectionId: album.id,
        fetchInitial: fetchInitial,
        fetchAll: fetchAll,
        loadRemote: (tracks) => ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.album(
                tracks: tracks,
                collection: album,
              ),
            ),
        recordHistory: () =>
            ref.read(playbackHistoryActionsProvider).addAlbums([album]),
      );
    case PlaylistSearchSuggestion(:final playlist):
      if (_resumeIfLoaded(ref, playlist.id)) return;
      final isLiked = playlist.id == 'user-liked-tracks';
      Future<List<SpotubeFullTrackObject>> fetchInitial() async => isLiked
          ? (await ref.read(metadataPluginSavedTracksProvider.future)).items
          : (await ref.read(
                  metadataPluginPlaylistTracksProvider(playlist.id).future))
              .items;
      Future<List<SpotubeFullTrackObject>> fetchAll() async {
        await fetchInitial();
        return isLiked
            ? ref.read(metadataPluginSavedTracksProvider.notifier).fetchAll()
            : ref
                .read(
                  metadataPluginPlaylistTracksProvider(playlist.id).notifier,
                )
                .fetchAll();
      }

      await _playCollection(
        context,
        ref,
        collectionId: playlist.id,
        fetchInitial: fetchInitial,
        fetchAll: fetchAll,
        loadRemote: (tracks) => ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.playlist(
                tracks: tracks,
                collection: playlist,
              ),
            ),
        recordHistory: () =>
            ref.read(playbackHistoryActionsProvider).addPlaylists([playlist]),
      );
    case ArtistSearchSuggestion(:final artist):
      // Artists own no collection id, so this is a plain queue load of their
      // top tracks rather than [_playCollection].
      final topTracks = (await ref
              .read(metadataPluginArtistTopTracksProvider(artist.id).future))
          .items
          .toList();
      if (topTracks.isEmpty || !context.mounted) return;

      final isRemoteDevice = await showSelectDeviceDialog(context, ref);
      if (isRemoteDevice == null) return;

      if (isRemoteDevice) {
        await ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.playlist(
                tracks: topTracks,
                collection: null,
              ),
            );
        return;
      }

      final notifier = ref.read(audioPlayerProvider.notifier);
      final queue = ref.read(audioPlayerProvider);
      if (queue.tracks.any((element) => element.id == topTracks.first.id)) {
        await notifier.jumpToTrack(topTracks.first);
        return;
      }
      await notifier.load(topTracks, autoPlay: true);
  }
}

/// True when the collection is already the active queue: the cover then just
/// resumes it (a no-op while playing) instead of restarting from the top.
bool _resumeIfLoaded(WidgetRef ref, String collectionId) {
  if (!ref.read(audioPlayerProvider).collections.contains(collectionId)) {
    return false;
  }
  final player = ref.read(audioPlayerPortProvider);
  if (!player.isPlaying) {
    unawaited(player.resume());
  }
  return true;
}

Future<void> _playCollection(
  BuildContext context,
  WidgetRef ref, {
  required String collectionId,
  required Future<List<SpotubeFullTrackObject>> Function() fetchInitial,
  required Future<List<SpotubeFullTrackObject>> Function() fetchAll,
  required Future<void> Function(List<SpotubeFullTrackObject>) loadRemote,
  required void Function() recordHistory,
}) async {
  final initialTracks = await fetchInitial();
  if (initialTracks.isEmpty || !context.mounted) return;

  final isRemoteDevice = await showSelectDeviceDialog(context, ref);
  if (isRemoteDevice == null) return;

  if (isRemoteDevice) {
    await loadRemote(await fetchAll());
    return;
  }

  final notifier = ref.read(audioPlayerProvider.notifier);
  await notifier.load(initialTracks, autoPlay: true);
  notifier.addCollection(collectionId);
  recordHistory();

  unawaited(appendCollectionTail(
    appendTail: (tail) => notifier.addTracks(tail),
    readCollections: () => ref.read(audioPlayerProvider).collections,
    collectionId: collectionId,
    alreadyLoaded: initialTracks,
    fetchAll: fetchAll,
  ));
}
