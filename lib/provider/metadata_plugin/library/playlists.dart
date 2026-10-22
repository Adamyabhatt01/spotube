import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginSavedPlaylistsNotifier
    extends PaginatedAsyncNotifier<SpotubeSimplePlaylistObject>
    with SavedListCacheMixin<SpotubeSimplePlaylistObject> {
  MetadataPluginSavedPlaylistsNotifier() : super();

  @override
  String? get snapshotKey => librarySnapshotKeySavedPlaylists;

  @override
  SpotubeSimplePlaylistObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeSimplePlaylistObject.fromJson;

  /// Playlist rows carry the cover URL Spotify regenerates whenever the
  /// playlist's tracks change. Confirming only page one on a warm build left
  /// every playlist past it showing last session's collage until the user
  /// happened to scroll to its page, so this list re-walks all pages in the
  /// background instead.
  ///
  /// It also makes a manual refresh walk every page, which this list needs
  /// for a second reason: Spotify appends a newly created playlist to the
  /// *end* of the library, so a page-one probe cannot see it — and that is
  /// exactly the row a second device is missing.
  @override
  bool get refreshAllPages => true;

  /// Attempts after an in-app add/remove, cumulative from the write. Spotify
  /// rebuilds the collage asynchronously, so one read right after the write
  /// usually still sees the old cover.
  static const _coverRefreshLadder = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 10),
  ];

  @override
  fetch(int offset, int limit) async {
    final playlists = await (await metadataPlugin)
        .user
        .savedPlaylists(limit: limit, offset: offset);

    return playlists;
  }

  @override
  build() async {
    // The account, not the auth provider: the auth provider's state flaps
    // whenever the plugin is reloaded, and every flap rebuilt this list.
    // `select` so an unchanged answer does not notify: the auth provider is
    // rebuilt whenever the plugin is reloaded, and every one of those
    // rebuilds re-read the whole library for nothing — and threw away
    // whatever the library sync was in the middle of.
    ref.watch(metadataAccountProvider.select((signedIn) => signedIn));

    final playlists = await buildSavedList();

    return playlists;
  }

  void updatePlaylist(SpotubeSimplePlaylistObject playlist) {
    if (state.value == null) return;

    if (state.value!.items.none((e) => e.id == playlist.id)) return;

    state = AsyncData(
      state.value!.copyWith(
        items: state.value!.items
            .map((element) => element.id == playlist.id ? playlist : element)
            .toList(),
      ),
    );
    scheduleSnapshotPersist();
  }

  /// Registers a playlist that was just created remotely. The create call
  /// already followed it into the library, so no extra "save" request is
  /// needed; this only keeps the current screen and its snapshot in sync.
  void insertPlaylist(SpotubeSimplePlaylistObject playlist) {
    final current = state.value;
    if (current == null) return;

    final exists = current.items.any((e) => e.id == playlist.id);
    state = AsyncData(
      current.copyWith(
        items: exists
            ? current.items
                .map(
                    (element) => element.id == playlist.id ? playlist : element)
                .toList()
            : [playlist, ...current.items],
        total: exists ? current.total : current.total + 1,
      ),
    );
    scheduleSnapshotPersist();
  }

  Future<void> addFavorite(SpotubeSimplePlaylistObject playlist) async {
    // The list may never have been opened (the detail page now reads this
    // notifier on demand instead of watching it). Without a cached list there
    // is nothing to update optimistically, but the write must still happen.
    final oldState = state.value;

    if (oldState != null) {
      state = AsyncData(
        oldState.copyWith(
          items: [
            playlist,
            ...oldState.items,
          ],
        ),
      );
    }

    try {
      await (await metadataPlugin).playlist.save(playlist.id);
    } catch (e) {
      if (oldState != null) state = AsyncData(oldState);
      rethrow;
    }
    ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlist.id));
    scheduleSnapshotPersist();
  }

  Future<void> removeFavorite(SpotubeSimplePlaylistObject playlist) async {
    final oldState = state.value;
    if (oldState != null) {
      state = AsyncData(
        oldState.copyWith(
          items: oldState.items.where((e) => (e).id != playlist.id).toList(),
        ),
      );
    }

    try {
      await (await metadataPlugin).playlist.unsave(playlist.id);
    } catch (e) {
      if (oldState != null) state = AsyncData(oldState);
      rethrow;
    }
    ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlist.id));
    scheduleSnapshotPersist();
  }

  Future<void> delete(String playlistId) async {
    final oldState = state;
    final hadValue = state.value != null;
    try {
      if (hadValue) state = const AsyncLoading();
      await (await metadataPlugin).playlist.deletePlaylist(playlistId);
      ref.invalidateSelf();
      ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlistId));
      ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
    } catch (e) {
      if (hadValue) state = oldState;
      rethrow;
    }
  }

  Future<void> addTracks(String playlistId, List<String> trackIds) async {
    await (await metadataPlugin)
        .playlist
        .addTracks(playlistId, trackIds: trackIds);

    ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
    refreshCoverLater(playlistId);
  }

  Future<void> removeTracks(String playlistId, List<String> trackIds) async {
    await (await metadataPlugin)
        .playlist
        .removeTracks(playlistId, trackIds: trackIds);

    // Spotify is not the only copy. The download mirror keeps its own
    // membership rows, and the playlist page falls back to them while the
    // refetch is in flight — without this delete the removed track is
    // re-painted from the local table a moment after succeeding upstream.
    await detachTracksFromPlaylist(
      ref.read(databaseProvider),
      playlistId: playlistId,
      trackIds: trackIds,
    );

    ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
    refreshCoverLater(playlistId);
  }

  /// Re-reads one playlist's cover after Spotify has had time to rebuild the
  /// collage, then updates both this list's row and the open playlist page.
  ///
  /// Best-effort: the detail page already refetches its own metadata on open,
  /// but the library card reads this list, so nothing else would update it
  /// before the next app launch.
  void refreshCoverLater(String playlistId) {
    unawaited(_refreshCover(playlistId));
  }

  Future<void> _refreshCover(String playlistId) async {
    for (final delay in _coverRefreshLadder) {
      await Future<void>.delayed(delay);

      try {
        final refreshed = await (await metadataPlugin).playlist.getPlaylist(
              playlistId,
            );
        final current = state.value?.items.firstWhereOrNull(
          (playlist) => playlist.id == playlistId,
        );
        // The row was unsaved or never loaded; there is nothing to refresh.
        if (current == null) return;

        final before = _coverSignature(current.images);
        // Spotify can answer with no images for a beat while it rebuilds the
        // collage. That is not a cover change; keep the one on screen instead
        // of blanking the card.
        final images =
            refreshed.images.isEmpty ? current.images : refreshed.images;
        updatePlaylist(
          SpotubeSimplePlaylistObject(
            id: refreshed.id,
            name: refreshed.name,
            description: refreshed.description,
            externalUri: refreshed.externalUri,
            owner: refreshed.owner,
            images: images,
          ),
        );
        // The playlist page watches its own metadata provider; drop it only
        // once the collage actually changed, so an unchanged cover does not
        // make the page reload on every attempt.
        if (_coverSignature(images) != before) {
          ref.invalidate(metadataPluginPlaylistProvider(playlistId));
          return;
        }
      } catch (_) {
        // Cover art is best-effort; a failed read must not surface anywhere.
        return;
      }
    }
  }
}

String _coverSignature(List<SpotubeImageObject> images) =>
    images.map((image) => image.url).join('|');

final metadataPluginSavedPlaylistsProvider = AsyncNotifierProvider<
    MetadataPluginSavedPlaylistsNotifier,
    SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>(
  () => MetadataPluginSavedPlaylistsNotifier(),
);

/// Resolves a single "is this playlist saved?" check through the plugin's
/// dedicated `isSavedPlaylist(id)` endpoint instead of walking the entire
/// saved-playlists list per id. The playlist page and library cards each
/// watch exactly one family instance, so per-id lookup is one cheap call.
/// Overridable so tests can substitute a fake without a live plugin.
typedef IsSavedPlaylistLookup = Future<bool> Function(String id);

final savedPlaylistLookupProvider = Provider<IsSavedPlaylistLookup>((ref) {
  return (id) async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }
    return plugin.user.isSavedPlaylist(id);
  };
});

final metadataPluginIsSavedPlaylistProvider =
    FutureProvider.family<bool, String>(
  (ref, id) => ref.watch(savedPlaylistLookupProvider)(id),
);

/// Whether [playlistId] is one of the signed-in user's own playlists — i.e.
/// the one they can delete from the heart, rather than merely unsave.
///
/// This is the single subscription the playlist header, its action row and its
/// track list used to open separately (each widget watched the whole
/// saved-playlists list just to answer one boolean). Deriving it once here
/// means every consumer reads one cached answer instead of re-walking the list
/// on each unrelated library update.
final isUserPlaylistProvider = Provider.autoDispose.family<bool, String>(
  (ref, playlistId) {
    final items =
        ref.watch(metadataPluginSavedPlaylistsProvider).asData?.value.items;
    final meId = ref.watch(metadataPluginUserProvider).asData?.value?.id;
    if (items == null || meId == null) return false;
    return items.any((e) => e.id == playlistId && e.owner.id == meId);
  },
);
