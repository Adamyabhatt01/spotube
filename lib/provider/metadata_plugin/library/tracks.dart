import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';
import 'package:spotube/provider/metadata_plugin/library/saved_track_likes.dart';
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

  /// The liked-tracks list is probed, never walked.
  ///
  /// It can hold thousands of rows — a full walk is a hundred requests —
  /// and it does not need one: Spotify orders liked tracks by the time they
  /// were saved, so a track liked on another device arrives at the *head* of
  /// the list, which the first page covers.

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

    // The account, not the auth provider: the auth provider's state flaps
    // whenever the plugin is reloaded, and every flap rebuilt this list.
    // `select` so an unchanged answer does not notify: the auth provider is
    // rebuilt whenever the plugin is reloaded, and every one of those
    // rebuilds re-read the whole library for nothing — and threw away
    // whatever the library sync was in the middle of.
    ref.watch(metadataAccountProvider.select((signedIn) => signedIn));
    return await buildSavedList();
  }

  /// Tracks with a save/unsave request in flight.
  ///
  /// The heart flips on the first tap, so a second tap before the first write
  /// finishes would otherwise race it: both would read the same stale answer
  /// and both would save. One write per track at a time makes the second tap
  /// a no-op while the first is still landing.
  final _toggling = <String>{};

  /// Flips the saved state of [track] using the app's optimistic view, so the
  /// heart and this decision can never disagree about what the last tap asked
  /// for.
  Future<void> toggleFavorite(SpotubeTrackObject track) async {
    if (!_toggling.add(track.id)) return;
    try {
      final liked = await ref.read(
        metadataPluginIsSavedTrackProvider(track.id).future,
      );
      if (liked) {
        await removeFavorite([track]);
      } else {
        await addFavorite([track]);
      }
    } finally {
      _toggling.remove(track.id);
    }
  }

  Future<void> addFavorite(List<SpotubeTrackObject> tracks) async {
    // The tap is the freshest fact we have. Write it before the request so
    // the heart and a second toggle both see it immediately, even while
    // Spotify's library query still says "not saved".
    final likes = ref.read(savedTrackLikesProvider.notifier);
    for (final track in tracks) {
      likes.set(track.id, true);
    }

    // The saved-tracks list can still be loading (or absent because this
    // notifier is auto-disposed). That must not turn a like into a no-op:
    // write the backend first, and only update/persist the optimistic list
    // when there is one to update.
    final oldState = state.value;
    if (oldState != null) {
      // A track can only be in Liked Songs once. The optimistic prepend used
      // to skip that rule, so a duplicate tap showed the same song twice
      // until the next full refresh.
      final known = {for (final saved in oldState.items) saved.id};
      final additions = <SpotubeFullTrackObject>[
        for (final track in tracks)
          if (track is SpotubeFullTrackObject && known.add(track.id)) track,
      ];
      if (additions.isNotEmpty) {
        state = AsyncData(
          oldState.copyWith(items: [...additions, ...oldState.items]),
        );
      }
    }

    try {
      await (await metadataPlugin).track.save(tracks.map((e) => e.id).toList());
    } catch (e) {
      for (final track in tracks) {
        likes.set(track.id, false);
      }
      if (oldState != null) state = AsyncData(oldState);
      rethrow;
    }
    for (final track in tracks) {
      ref.invalidate(metadataPluginIsSavedTrackProvider(track.id));
    }
    if (oldState != null) scheduleSnapshotPersist();
  }

  Future<void> removeFavorite(List<SpotubeTrackObject> tracks) async {
    final likes = ref.read(savedTrackLikesProvider.notifier);
    for (final track in tracks) {
      likes.set(track.id, false);
    }

    final oldState = state.value;
    if (oldState != null) {
      state = AsyncData(
        oldState.copyWith(
          items: oldState.items
              .where(
                (savedTrack) =>
                    !tracks.any((track) => track.id == savedTrack.id),
              )
              .toList(),
        ),
      );
    }

    try {
      await (await metadataPlugin)
          .track
          .unsave(tracks.map((e) => e.id).toList());
    } catch (e) {
      for (final track in tracks) {
        likes.set(track.id, true);
      }
      if (oldState != null) state = AsyncData(oldState);
      rethrow;
    }
    for (final track in tracks) {
      ref.invalidate(metadataPluginIsSavedTrackProvider(track.id));
    }
    if (oldState != null) scheduleSnapshotPersist();
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
  (ref, trackId) {
    // A tap this session outranks the plugin answer: `areEntitiesInLibrary`
    // trails `addToLibrary` by seconds. Returning it without awaiting the
    // query also keeps the heart out of AsyncLoading right after a tap, when
    // it must already show the new colour.
    final local = ref.watch(
      savedTrackLikesProvider.select((likes) => likes[trackId]),
    );
    if (local != null) return local;

    return ref.watch(savedTrackBatcherProvider).request(trackId);
  },
);
