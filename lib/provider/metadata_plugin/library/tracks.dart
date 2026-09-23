import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

class MetadataPluginSavedTracksNotifier
    extends AutoDisposePaginatedAsyncNotifier<SpotubeFullTrackObject>
    with SavedListCacheMixin<SpotubeFullTrackObject> {
  MetadataPluginSavedTracksNotifier() : super();

  @override
  String? get snapshotKey => librarySnapshotKeySavedTracks;

  @override
  SpotubeFullTrackObject Function(Map<String, dynamic>)? get snapshotDecoder =>
      SpotubeFullTrackObject.fromJson;

  @override
  fetch(offset, limit) async {
    final tracks = await (await metadataPlugin).user.savedTracks(
          offset: offset,
          limit: limit,
        );

    return tracks;
  }

  @override
  build() async {
    ref.cacheFor();

    await ref.watch(metadataPluginAuthenticatedProvider.future);
    return await buildSavedList();
  }

  Future<void> addFavorite(List<SpotubeTrackObject> tracks) async {
    if (state.value == null) {
      return;
    }

    final oldState = state.value;
    state = AsyncData(
      state.value!.copyWith(
        items: [
          ...tracks.whereType<SpotubeFullTrackObject>(),
          ...state.value!.items
        ],
      ),
    );

    try {
      await (await metadataPlugin).track.save(tracks.map((e) => e.id).toList());
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    for (final track in tracks) {
      ref.invalidate(metadataPluginIsSavedTrackProvider(track.id));
    }
    unawaited(persistSnapshot());
  }

  Future<void> removeFavorite(List<SpotubeTrackObject> tracks) async {
    if (state.value == null) {
      return;
    }

    final oldState = state.value;
    state = AsyncData(
      state.value!.copyWith(
        items: state.value!.items
            .where(
              (savedTrack) => !tracks.any((track) => track.id == savedTrack.id),
            )
            .toList(),
      ),
    );

    try {
      await (await metadataPlugin)
          .track
          .unsave(tracks.map((e) => e.id).toList());
    } catch (e) {
      state = AsyncData(oldState!);
      rethrow;
    }
    for (final track in tracks) {
      ref.invalidate(metadataPluginIsSavedTrackProvider(track.id));
    }
    unawaited(persistSnapshot());
  }
}

final metadataPluginSavedTracksProvider = AutoDisposeAsyncNotifierProvider<
    MetadataPluginSavedTracksNotifier,
    SpotubePaginationResponseObject<SpotubeFullTrackObject>>(
  () => MetadataPluginSavedTracksNotifier(),
);

/// Batches per-track "is this liked?" lookups into `isSavedTracks(ids)` calls
/// of at most 50 ids — the same shape as Spotify's
/// `GET /me/tracks/contains?ids=`. Replaces the previous pattern where every
/// family instance triggered a full `fetchAll()` walk of the liked library.
/// Overridable so tests can substitute a fake query without a live plugin.
final savedTrackBatcherProvider = Provider<IsSavedBatcher>((ref) {
  return IsSavedBatcher((ids) async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }
    return plugin.user.isSavedTracks(ids);
  });
});

final metadataPluginIsSavedTrackProvider =
    FutureProvider.autoDispose.family<bool, String>(
  (ref, trackId) => ref.watch(savedTrackBatcherProvider).request(trackId),
);
