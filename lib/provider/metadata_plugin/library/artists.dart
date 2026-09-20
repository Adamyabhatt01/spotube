import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginSavedArtistNotifier
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> fetch(
    int offset,
    int limit,
  ) async {
    final artists = await (await metadataPlugin).user.savedArtists(
          limit: limit,
          offset: offset,
        );

    return artists;
  }

  @override
  build() async {
    await ref.watch(metadataPluginAuthenticatedProvider.future);
    return await buildSavedList();
  }

  Future<void> addFavorite(List<SpotubeFullArtistObject> artists) async {
    if (artists.isEmpty || state.value == null) return;
    final oldState = state.value;

    state = AsyncData(
      state.value!.copyWith(
        items: [
          ...artists,
          ...state.value!.items,
        ],
      ),
    );
    try {
      await (await metadataPlugin)
          .artist
          .save(artists.map((e) => e.id).toList());
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    unawaited(persistSnapshot());
  }

  Future<void> removeFavorite(List<SpotubeFullArtistObject> artists) async {
    if (artists.isEmpty || state.value == null) return;

    final oldState = state.value;

    final artistIds = artists.map((e) => e.id).toList();
    state = AsyncData(
      state.value!.copyWith(
        items: state.value!.items
            .where(
              (e) => artistIds.contains((e).id) == false,
            )
            .toList(),
      ),
    );

    try {
      await (await metadataPlugin).artist.unsave(artistIds);
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    unawaited(persistSnapshot());
  }
}

final metadataPluginSavedArtistsProvider = AsyncNotifierProvider<
    MetadataPluginSavedArtistNotifier,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => MetadataPluginSavedArtistNotifier(),
);

/// Fetches the full set of saved-artist IDs once and shares it across every
/// per-artist lookup (same shape as `metadataPluginSavedTrackIdsProvider`).
/// Previously each per-id family instance ran its own whole-library
/// `fetchAll()` loop, multiplying Spotify requests — a direct cause of 429s.
final metadataPluginSavedArtistIdsProvider =
    FutureProvider.autoDispose<Set<String>>(
  (ref) async {
    final savedArtists =
        await ref.watch(metadataPluginSavedArtistsProvider.future);

    final allSavedArtists = savedArtists.hasMore
        ? await ref.read(metadataPluginSavedArtistsProvider.notifier).fetchAll()
        : savedArtists.items;

    return allSavedArtists.map((artist) => artist.id).toSet();
  },
);

final metadataPluginIsSavedArtistProvider =
    FutureProvider.autoDispose.family<bool, String>(
  (ref, artistId) async {
    final allSavedArtistIds =
        await ref.watch(metadataPluginSavedArtistIdsProvider.future);

    return allSavedArtistIds.contains(artistId);
  },
);
