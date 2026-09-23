import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
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

  @override
  fetch(int offset, int limit) async {
    final playlists = await (await metadataPlugin)
        .user
        .savedPlaylists(limit: limit, offset: offset);

    return playlists;
  }

  @override
  build() async {
    await ref.watch(metadataPluginAuthenticatedProvider.future);

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
    unawaited(persistSnapshot());
  }

  Future<void> addFavorite(SpotubeSimplePlaylistObject playlist) async {
    if (state.value == null) return;

    final oldState = state.value;

    state = AsyncData(
      state.value!.copyWith(
        items: [
          playlist,
          ...state.value!.items,
        ],
      ),
    );

    try {
      await (await metadataPlugin).playlist.save(playlist.id);
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlist.id));
    unawaited(persistSnapshot());
  }

  Future<void> removeFavorite(SpotubeSimplePlaylistObject playlist) async {
    if (state.value == null) return;

    final oldState = state.value;
    state = AsyncData(
      state.value!.copyWith(
        items: state.value!.items.where((e) => (e).id != playlist.id).toList(),
      ),
    );

    try {
      await (await metadataPlugin).playlist.unsave(playlist.id);
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlist.id));
    unawaited(persistSnapshot());
  }

  Future<void> delete(String playlistId) async {
    if (state.value == null) return;
    final oldState = state;
    try {
      state = const AsyncLoading();
      await (await metadataPlugin).playlist.deletePlaylist(playlistId);
      ref.invalidateSelf();
      ref.invalidate(metadataPluginIsSavedPlaylistProvider(playlistId));
      ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
    } catch (e) {
      state = oldState;
      rethrow;
    }
  }

  Future<void> addTracks(String playlistId, List<String> trackIds) async {
    if (state.value == null) return;

    await (await metadataPlugin)
        .playlist
        .addTracks(playlistId, trackIds: trackIds);

    ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
  }

  Future<void> removeTracks(String playlistId, List<String> trackIds) async {
    if (state.value == null) return;

    await (await metadataPlugin)
        .playlist
        .removeTracks(playlistId, trackIds: trackIds);

    ref.invalidate(metadataPluginPlaylistTracksProvider(playlistId));
  }
}

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
