import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginSavedAlbumNotifier
    extends PaginatedAsyncNotifier<SpotubeSimpleAlbumObject>
    with SavedListCacheMixin<SpotubeSimpleAlbumObject> {
  @override
  String? get snapshotKey => librarySnapshotKeySavedAlbums;

  @override
  SpotubeSimpleAlbumObject Function(Map<String, dynamic>)?
      get snapshotDecoder => SpotubeSimpleAlbumObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> fetch(
    int offset,
    int limit,
  ) async {
    return await (await metadataPlugin).user.savedAlbums(
          limit: limit,
          offset: offset,
        );
  }

  @override
  build() async {
    await ref.watch(metadataPluginAuthenticatedProvider.future);
    return await buildSavedList();
  }

  Future<void> addFavorite(List<SpotubeSimpleAlbumObject> albums) async {
    if (albums.isEmpty || state.value == null) return;
    final oldState = state.value;

    state = AsyncData(
      state.value!.copyWith(
        items: [
          ...albums,
          ...state.value!.items,
        ],
      ),
    );
    try {
      await (await metadataPlugin).album.save(albums.map((e) => e.id).toList());
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    for (final album in albums) {
      ref.invalidate(metadataPluginIsSavedAlbumProvider(album.id));
    }
    unawaited(persistSnapshot());
  }

  Future<void> removeFavorite(List<SpotubeSimpleAlbumObject> albums) async {
    if (albums.isEmpty || state.value == null) return;

    final oldState = state.value;

    final albumIds = albums.map((e) => e.id).toList();
    state = AsyncData(
      state.value!.copyWith(
        items: state.value!.items
            .where(
              (e) => albumIds.contains((e).id) == false,
            )
            .toList(),
      ),
    );
    try {
      await (await metadataPlugin).album.unsave(albumIds);
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    for (final album in albums) {
      ref.invalidate(metadataPluginIsSavedAlbumProvider(album.id));
    }
    unawaited(persistSnapshot());
  }
}

final metadataPluginSavedAlbumsProvider = AsyncNotifierProvider<
    MetadataPluginSavedAlbumNotifier,
    SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>(
  () => MetadataPluginSavedAlbumNotifier(),
);

/// Batches per-album "is this saved?" lookups into `isSavedAlbums(ids)` calls
/// of at most 50 ids — same shape as Spotify's
/// `GET /me/albums/contains?ids=`. Replaces the previous pattern where every
/// family instance walked the whole saved-albums list. Overridable so tests
/// can substitute a fake query without a live plugin.
final savedAlbumBatcherProvider = Provider<IsSavedBatcher>((ref) {
  return IsSavedBatcher((ids) async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }
    return plugin.user.isSavedAlbums(ids);
  });
});

final metadataPluginIsSavedAlbumProvider =
    FutureProvider.autoDispose.family<bool, String>(
  (ref, albumId) => ref.watch(savedAlbumBatcherProvider).request(albumId),
);
