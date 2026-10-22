import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginSavedArtistNotifier
    extends PaginatedAsyncNotifier<SpotubeFullArtistObject>
    with SavedListCacheMixin<SpotubeFullArtistObject> {
  @override
  String? get snapshotKey => librarySnapshotKeySavedArtists;

  @override
  SpotubeFullArtistObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullArtistObject.fromJson;

  /// The followed-artists list is small — tens of rows, not thousands — so a
  /// re-read walks all of it.
  ///
  /// That is what makes a re-read able to see an artist followed on another
  /// device: only a full walk is sure to include a row that was not there
  /// before.
  @override
  bool get refreshAllPages => true;

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
    // The account, not the auth provider: the auth provider's state flaps
    // whenever the plugin is reloaded, and every flap rebuilt this list.
    // `select` so an unchanged answer does not notify: the auth provider is
    // rebuilt whenever the plugin is reloaded, and every one of those
    // rebuilds re-read the whole library for nothing — and threw away
    // whatever the library sync was in the middle of.
    ref.watch(metadataAccountProvider.select((signedIn) => signedIn));
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
    for (final artist in artists) {
      ref.invalidate(metadataPluginIsSavedArtistProvider(artist.id));
    }
    scheduleSnapshotPersist();
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
    for (final artist in artists) {
      ref.invalidate(metadataPluginIsSavedArtistProvider(artist.id));
    }
    scheduleSnapshotPersist();
  }
}

final metadataPluginSavedArtistsProvider = AsyncNotifierProvider<
    MetadataPluginSavedArtistNotifier,
    SpotubePaginationResponseObject<SpotubeFullArtistObject>>(
  () => MetadataPluginSavedArtistNotifier(),
);

/// Batches per-artist "is this followed?" lookups into `isSavedArtists(ids)`
/// calls of at most 50 ids — same shape as Spotify's
/// `GET /me/following/contains?type=artist&ids=`. Replaces the previous
/// pattern where every family instance walked the whole followed-artists list.
/// Overridable so tests can substitute a fake query without a live plugin.
final savedArtistBatcherProvider = Provider<IsSavedBatcher>((ref) {
  return IsSavedBatcher((ids) async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }
    return plugin.user.isSavedArtists(ids);
  });
});

final metadataPluginIsSavedArtistProvider =
    FutureProvider.autoDispose.family<bool, String>(
  (ref, artistId) => ref.watch(savedArtistBatcherProvider).request(artistId),
);
