import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/extensions/list.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/discord_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/debounced_writer.dart';
import 'package:spotube/utils/perf_counters.dart';

/// Initialization status of [audioPlayerProvider]'s saved-state restore.
/// `AsyncLoading` while [AudioPlayerNotifier.syncSavedState] runs,
/// `AsyncData` once the queue is restored (or confirmed empty),
/// `AsyncError` when restore failed (degraded — playback starts with an
/// empty queue instead of crashing; the error is reported, never silent).
final audioPlayerInitStatusProvider =
    StateProvider<AsyncValue<void>>((_) => const AsyncLoading());

class AudioPlayerNotifier extends Notifier<AudioPlayerState> {
  BlackListNotifier get _blacklist => ref.read(blacklistProvider.notifier);

  /// Phase 2 perf: collapses flap-prone flag persistence (playing/loop/
  /// shuffle — e.g. buffering toggles playing false->true per stall) into a
  /// single trailing-edge write. UI `state` still updates synchronously at
  /// each event; only the Drift UPDATE is deferred. Queue/index writes stay
  /// immediate for resume accuracy. Flushed on dispose (see [build]).
  late final _flagPersistDebouncer = DebouncedWriter(
    const Duration(milliseconds: 400),
    (e, stack) => AppLogger.reportError(e, stack),
  );

  void _assertAllowedTracks(Iterable<SpotubeTrackObject> tracks) {
    assert(
      tracks.every(
        (track) =>
            track is SpotubeFullTrackObject || track is SpotubeLocalTrackObject,
      ),
      'All tracks must be either SpotubeFullTrackObject or SpotubeLocalTrackObject',
    );
  }

  void _assertAllowedTrack(SpotubeTrackObject tracks) {
    assert(
      tracks is SpotubeFullTrackObject || tracks is SpotubeLocalTrackObject,
      'Track must be either SpotubeFullTrackObject or SpotubeLocalTrackObject',
    );
  }

  /// Backend seam for playlist mutation. media_kit exposes only single
  /// add/insert/remove calls (no bulk API), so bulk methods must loop —
  /// but through these methods, which tests override with a recording
  /// fake to verify call counts, order and backend/state consistency.
  /// Production implementations delegate straight to [audioPlayer].
  Future<void> addMediaToBackend(SpotubeMedia media) =>
      audioPlayer.addTrack(media);

  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) =>
      audioPlayer.addTrackAt(media, index);

  Future<void> removeMediaFromBackend(int index) =>
      audioPlayer.removeTrack(index);

  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) =>
      audioPlayer.openPlaylist(
        medias,
        initialIndex: initialIndex,
        autoPlay: autoPlay,
      );

  int get backendCurrentIndex => audioPlayer.currentIndex;

  /// The backend's current media list, used to remember *which* queue a
  /// persistence write describes (see [_lastSyncedMedias]). A seam for the
  /// same reason as [backendCurrentIndex]: tests replace the native player.
  List<Media> get backendMedias => audioPlayer.playlist.medias;

  /// The media list the persisted `tracks` column describes, element-identical
  /// to what the backend holds. A playlist event whose medias are the same
  /// objects is an index/flag-only change, so re-decoding every media
  /// (`SpotubeMedia.media` → `fromJson`) and re-encoding the whole
  /// `tracks` column would persist what is already stored.
  List<Media>? _lastSyncedMedias;

  /// Depth of in-progress bulk native-queue mutations. While > 0, the
  /// playlistStream listener skips its state+DB sync: the native queue is
  /// transiently inconsistent mid-loop, and each event would otherwise
  /// trigger a rebuild plus a Drift write per track (N+1 writes and
  /// flicker for an N-track bulk op). Bulk methods perform exactly one
  /// final sync via [_persistQueueState].
  int _bulkMutationDepth = 0;

  /// Single persistence point for queue/index changes: one Drift
  /// transaction per logical mutation. The index is read back from the
  /// backend (native truth — e.g. removals ahead of the cursor shift it)
  /// and clamped, so a track ending mid-bulk cannot leave a stale index.
  Future<void> _persistQueueState() async {
    final database = ref.read(databaseProvider);
    final nativeIndex = backendCurrentIndex;
    final clamped = state.tracks.isEmpty
        ? 0
        : nativeIndex.clamp(0, state.tracks.length - 1);
    if (state.currentIndex != clamped) {
      state = state.copyWith(currentIndex: clamped);
    }
    await database.transaction(() async {
      await _updatePlayerState(
        AudioPlayerStateTableCompanion(
          tracks: Value(state.tracks),
          currentIndex: Value(state.currentIndex),
        ),
      );
    });
  }

  /// Restores the persisted queue/index into state and the backend.
  /// Public so tests can drive the real restore path against a stub
  /// database. A failed restore marks degraded status and leaves an
  /// empty, usable queue instead of failing the provider build.
  Future<void> syncSavedState() async {
    final status = ref.read(audioPlayerInitStatusProvider.notifier);
    try {
      final database = ref.read(databaseProvider);

      var playerState = await database
          .select(database.audioPlayerStateTable)
          .getSingleOrNull();

      if (playerState == null) {
        await database.into(database.audioPlayerStateTable).insert(
              AudioPlayerStateTableCompanion.insert(
                playing: audioPlayer.isPlaying,
                loopMode: audioPlayer.loopMode,
                shuffled: audioPlayer.isShuffled,
                collections: <String>[],
                tracks: const Value(<SpotubeTrackObject>[]),
                currentIndex: const Value(0),
                id: const Value(0),
              ),
            );

        playerState =
            await database.select(database.audioPlayerStateTable).getSingle();
      } else {
        await audioPlayer.setLoopMode(playerState.loopMode);
        await audioPlayer.setShuffle(playerState.shuffled);
      }

      final tracks = playerState.tracks;
      final currentIndex = playerState.currentIndex;

      if (tracks.isEmpty && state.tracks.isNotEmpty) {
        await _updatePlayerState(
          AudioPlayerStateTableCompanion(
            tracks: Value(state.tracks),
            currentIndex: Value(currentIndex),
          ),
        );
      } else if (tracks.isNotEmpty) {
        state = state.copyWith(
          tracks: tracks,
          currentIndex: currentIndex,
        );
        await audioPlayer.openPlaylist(
          tracks.asMediaList(),
          initialIndex: currentIndex,
          autoPlay: false,
        );
      }

      if (playerState.collections.isNotEmpty) {
        state = state.copyWith(
          collections: playerState.collections,
        );
      }

      status.state = const AsyncData(null);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      try {
        status.state = AsyncError(e, stack);
      } catch (_) {
        // Provider already disposed; the report above is the record.
      }
    }
  }

  Future<void> _updatePlayerState(
    AudioPlayerStateTableCompanion companion,
  ) async {
    final database = ref.read(databaseProvider);

    // Whatever `tracks` is being stored now describes the backend queue at this
    // instant; a later playlist event over the same media objects is therefore
    // an index-only change and must not rewrite the column.
    if (companion.tracks.present) {
      _lastSyncedMedias = backendMedias;
      PerfCounters.note('queue.tracksWrite');
    }

    await (database.update(database.audioPlayerStateTable)
          ..where((tb) => tb.id.equals(0)))
        .write(companion);
  }

  /// Response to one native playlist event: publish the queue and persist it.
  ///
  /// A seam (like the mutation seams above) because media_kit's stream cannot
  /// be fed in a test.
  ///
  /// `setShuffle` arrives here as a list of bare `Media(uri)` — media_kit
  /// rebuilds it from mpv's own playlist — and it still works, because
  /// `Media.new` restores `extras` from media_kit's static uri→payload cache
  /// (`media_native.dart:111`), which stays warm for as long as the playlist
  /// itself holds a `Media` for each uri. `test/queue_persistence_test.dart`
  /// pins that contract; do not "fix" the missing extras without checking it.
  Future<void> onBackendPlaylist(Playlist playlist) async {
    // Skipped inside bulk mutations (see [_bulkMutationDepth]): the
    // native queue is mid-loop and each event would otherwise cause
    // a rebuild + DB write per track. Bulk methods sync once after.
    if (_bulkMutationDepth > 0) return;

    final isSameQueue = _sameMedias(_lastSyncedMedias, playlist.medias);
    PerfCounters.note('queue.playlistEvent');
    if (!isSameQueue) PerfCounters.note('queue.playlistDecode');
    // One state emission per event, as before: publishing `tracks` and
    // `currentIndex` separately would rebuild every queue listener twice.
    state = state.copyWith(
      tracks: isSameQueue
          ? state.tracks
          : playlist.medias.map((e) => SpotubeMedia.media(e).track).toList(),
      currentIndex: playlist.index,
    );

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        currentIndex: Value(state.currentIndex),
        // The column already holds this exact queue; rewriting it would be a
        // full `jsonEncode` of the queue for a change it does not describe.
        tracks: isSameQueue ? const Value.absent() : Value(state.tracks),
      ),
    );
  }

  static bool _sameMedias(List<Media>? previous, List<Media> current) {
    if (previous == null) return false;
    if (identical(previous, current)) return true;
    if (previous.length != current.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (!identical(previous[i], current[i])) return false;
    }
    return true;
  }

  @override
  build() {
    final subscriptions = [
      audioPlayer.playingStream.listen((playing) async {
        try {
          state = state.copyWith(playing: playing);

          _flagPersistDebouncer(
            () => _updatePlayerState(
              AudioPlayerStateTableCompanion(
                playing: Value(playing),
              ),
            ),
          );
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
      audioPlayer.loopModeStream.listen((loopMode) async {
        try {
          state = state.copyWith(loopMode: loopMode);

          _flagPersistDebouncer(
            () => _updatePlayerState(
              AudioPlayerStateTableCompanion(
                loopMode: Value(loopMode),
              ),
            ),
          );
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
      audioPlayer.shuffledStream.listen((shuffled) async {
        try {
          state = state.copyWith(shuffled: shuffled);

          _flagPersistDebouncer(
            () => _updatePlayerState(
              AudioPlayerStateTableCompanion(
                shuffled: Value(shuffled),
              ),
            ),
          );
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
      audioPlayer.playlistStream.listen((playlist) async {
        try {
          await onBackendPlaylist(playlist);
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
    ];

    // Fire-and-forget by design (see syncSavedState docs): restore must
    // not block provider creation, and failures degrade explicitly.
    unawaited(syncSavedState());

    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      // Persist the latest debounced flag value. Dispose is synchronous so
      // this is fire-and-forget; failures route to AppLogger via the
      // debouncer's onError instead of the zone.
      _flagPersistDebouncer.flush();
    });

    return AudioPlayerState(
      loopMode: audioPlayer.loopMode,
      playing: audioPlayer.isPlaying,
      shuffled: audioPlayer.isShuffled,
      tracks: [],
      collections: [],
    );
  }

  // Collection related methods
  Future<void> addCollections(List<String> collectionIds) async {
    state = state.copyWith(collections: [
      ...state.collections,
      ...collectionIds,
    ]);

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        collections: Value(state.collections),
      ),
    );
  }

  Future<void> addCollection(String collectionId) async {
    await addCollections([collectionId]);
  }

  Future<void> removeCollections(List<String> collectionIds) async {
    state = state.copyWith(
      collections: state.collections
          .where((element) => !collectionIds.contains(element))
          .toList(),
    );

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        collections: Value(state.collections),
      ),
    );
  }

  Future<void> removeCollection(String collectionId) async {
    await removeCollections([collectionId]);
  }

  Future<void> addTracksAtFirst(
    Iterable<SpotubeTrackObject> tracks, {
    bool allowDuplicates = false,
  }) async {
    _assertAllowedTracks(tracks);
    if (state.tracks.length == 1) {
      return addTracks(tracks);
    }

    final addableTracks = _blacklist
        .filter(tracks)
        .where(
          (track) =>
              allowDuplicates ||
              !state.tracks.any((element) => _compareTracks(element, track)),
        )
        .toList();
    if (addableTracks.isEmpty) return;

    final previousState = state;
    state = state.copyWith(
      tracks: [...addableTracks, ...state.tracks],
    );

    // Indexes of inserted backend entries, for rollback if a mid-loop
    // insert fails (they are contiguous from insertBase onward, but
    // recording each index keeps the revert straightforward).
    final insertedIndexes = <int>[];
    _bulkMutationDepth++;
    try {
      for (int i = 0; i < addableTracks.length; i++) {
        final track = addableTracks.elementAt(i);
        final insertAt = max(previousState.currentIndex, 0) + i + 1;

        await insertMediaIntoBackend(
          SpotubeMedia(track),
          insertAt,
        );
        insertedIndexes.add(insertAt);
      }
    } catch (_) {
      await _rollbackBulkAdditions(insertedIndexes);
      state = previousState;
      rethrow;
    } finally {
      _bulkMutationDepth--;
    }

    await _persistQueueState();
  }

  /// Removes backend entries that were added by a bulk op before it
  /// failed. Highest index first so earlier removals never shift the
  /// positions of later ones. Individual rollback failures are reported
  /// but never mask the original error.
  Future<void> _rollbackBulkAdditions(List<int> insertedIndexes) async {
    for (var i = insertedIndexes.length - 1; i >= 0; i--) {
      try {
        await removeMediaFromBackend(insertedIndexes[i]);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }
  }

  /// Re-adds backend entries that a bulk removal deleted before it
  /// failed, in ascending order so positions rebuild correctly.
  Future<void> _rollbackBulkRemovals(
    List<({int index, SpotubeTrackObject track})> removed,
  ) async {
    for (final entry in removed..sort((a, b) => a.index.compareTo(b.index))) {
      try {
        await insertMediaIntoBackend(SpotubeMedia(entry.track), entry.index);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }
  }

  Future<void> addTrack(SpotubeTrackObject track) async {
    _assertAllowedTrack(track);

    if (_blacklist.contains(track)) return;
    if (state.tracks.any((element) => _compareTracks(element, track))) return;

    final previousState = state;
    state = state.copyWith(
      tracks: [...state.tracks, track],
    );

    try {
      await audioPlayer.addTrack(SpotubeMedia(track));
    } catch (_) {
      state = previousState;
      rethrow;
    }

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        tracks: Value(state.tracks),
        currentIndex: Value(max(state.currentIndex, 0)),
      ),
    );
  }

  Future<void> addTracks(Iterable<SpotubeTrackObject> tracks) async {
    _assertAllowedTracks(tracks);

    // Note: unlike addTrack/addTracksAtFirst, duplicates are intentionally
    // allowed here (long-standing behavior); only the blacklist filters.
    final addableTracks = _blacklist.filter(tracks).toList();
    if (addableTracks.isEmpty) return;

    final previousState = state;
    state = state.copyWith(
      tracks: [...state.tracks, ...addableTracks],
    );

    // Appends land at the (pre-mutation) tail, growing one slot at a time.
    final baseIndex = previousState.tracks.length;
    final addedIndexes = <int>[];

    _bulkMutationDepth++;
    try {
      for (final track in addableTracks) {
        await addMediaToBackend(SpotubeMedia(track));
        addedIndexes.add(baseIndex + addedIndexes.length);
      }
    } catch (_) {
      await _rollbackBulkAdditions(addedIndexes);
      state = previousState;
      rethrow;
    } finally {
      _bulkMutationDepth--;
    }

    await _persistQueueState();
  }

  Future<void> removeTrack(String trackId) async {
    final index = state.tracks.indexWhere((element) => element.id == trackId);

    if (index == -1) return;

    final previousState = state;
    state = state.copyWith(
      tracks: List.of(state.tracks)..removeAt(index),
    );

    try {
      await audioPlayer.removeTrack(index);
    } catch (_) {
      state = previousState;
      rethrow;
    }

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        tracks: Value(state.tracks),
        currentIndex: Value(max(state.currentIndex, 0)),
      ),
    );
  }

  Future<void> removeTracks(Iterable<String> trackIds) async {
    final ids = trackIds.toSet();
    if (ids.isEmpty) return;

    // Indexes are computed against the FULL pre-mutation queue (the old
    // code indexed the filtered subset, removing the wrong native tracks)
    // and applied highest-first so earlier removals never shift later ones.
    final indexesToRemove = state.tracks.indexed
        .where((entry) => ids.contains(entry.$2.id))
        .map((entry) => entry.$1)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (indexesToRemove.isEmpty) return;

    final previousState = state;
    state = state.copyWith(
      tracks:
          state.tracks.where((element) => !ids.contains(element.id)).toList(),
    );

    // (index, track) pairs of what was actually removed from the backend,
    // so a mid-loop failure can re-insert exactly the same entries.
    final removedFromBackend = <({int index, SpotubeTrackObject track})>[];

    _bulkMutationDepth++;
    try {
      for (final index in indexesToRemove) {
        await removeMediaFromBackend(index);
        removedFromBackend
            .add((index: index, track: previousState.tracks[index]));
      }
    } catch (_) {
      await _rollbackBulkRemovals(removedFromBackend);
      state = previousState;
      rethrow;
    } finally {
      _bulkMutationDepth--;
    }

    await _persistQueueState();
  }

  bool _compareTracks(SpotubeTrackObject a, SpotubeTrackObject b) {
    if (a.runtimeType != b.runtimeType) {
      return false;
    }

    return a is SpotubeLocalTrackObject && b is SpotubeLocalTrackObject
        ? a.path == b.path
        : a.id == b.id;
  }

  Future<void> load(
    List<SpotubeTrackObject> tracks, {
    int initialIndex = 0,
    bool autoPlay = false,
  }) async {
    _assertAllowedTracks(tracks);

    // Keyed dedupe: same first-occurrence result as the nested scan, but
    // O(n) — a 2k-track load did ~n²/2 URI compares here before audio start.
    final medias = _blacklist
        .filter(tracks)
        .toList()
        .asMediaList()
        .uniqueByKey((media) => media.uri);

    if (medias.isEmpty) return;

    // The blacklist filter and dedupe above can shrink the input, so a
    // caller-supplied [initialIndex] may no longer be in range. Clamp
    // before indexing (e.g. the pre-warm below) instead of throwing.
    final safeInitialIndex = initialIndex.clamp(0, medias.length - 1);

    // Giving the initial track a boost so MediaKit won't skip
    // because of timeout
    final intendedActiveTrack = medias[safeInitialIndex];
    if (intendedActiveTrack.track is! SpotubeLocalTrackObject) {
      ref.read(
        sourcedTrackProvider(
          intendedActiveTrack.track as SpotubeFullTrackObject,
        ).future,
      );
    }

    final previousState = state;
    state = state.copyWith(
      // These are filtered tracks as well
      tracks: medias.map((media) => media.track).toList(),
      currentIndex: safeInitialIndex,
      collections: [],
    );

    try {
      await openPlaylistOnBackend(
        medias,
        initialIndex: safeInitialIndex,
        autoPlay: autoPlay,
      );
    } catch (_) {
      // The backend rejected the new queue; the previously loaded
      // playlist (if any) is still what the player holds.
      state = previousState;
      rethrow;
    }

    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        tracks: Value(state.tracks),
        currentIndex: Value(max(state.currentIndex, 0)),
      ),
    );
  }

  Future<void> swapActiveSource() async {
    if (state.tracks.isEmpty || state.activeTrack is! SpotubeFullTrackObject) {
      return;
    }

    final oldState = state;
    await audioPlayer.stop();

    await load(
      oldState.tracks,
      initialIndex: oldState.currentIndex,
      autoPlay: true,
    );
    state = state.copyWith(
      collections: oldState.collections,
      loopMode: oldState.loopMode,
      playing: oldState.playing,
      shuffled: false,
    );
    await audioPlayer.setLoopMode(oldState.loopMode);
    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        tracks: Value(state.tracks),
        currentIndex: Value(state.currentIndex),
        collections: Value(state.collections),
        loopMode: Value(state.loopMode),
        playing: Value(state.playing),
        shuffled: Value(state.shuffled),
      ),
    );
  }

  Future<void> jumpToTrack(SpotubeTrackObject track) async {
    // No defensive copy: indexWhere never mutates, and cloning the whole
    // queue per jump costs O(queue) allocation on every seek.
    final index =
        state.tracks.indexWhere((element) => element.id == track.id);
    if (index == -1) return;
    await audioPlayer.jumpTo(index);
  }

  Future<void> moveTrack(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex ||
        newIndex < 0 ||
        oldIndex < 0 ||
        newIndex > state.tracks.length - 1 ||
        oldIndex > state.tracks.length - 1) {
      return;
    }

    await audioPlayer.moveTrack(oldIndex, newIndex);
  }

  Future<void> stop() async {
    state = state.copyWith(
      tracks: [],
      currentIndex: 0,
      collections: [],
      loopMode: PlaylistMode.none,
      playing: false,
      shuffled: false,
    );
    await audioPlayer.stop();
    await _updatePlayerState(
      AudioPlayerStateTableCompanion(
        tracks: Value(state.tracks),
        currentIndex: const Value(0),
        collections: const Value(<String>[]),
        loopMode: const Value(PlaylistMode.none),
        playing: const Value(false),
        shuffled: const Value(false),
      ),
    );
    ref.read(discordProvider.notifier).clear();
  }
}

final audioPlayerProvider =
    NotifierProvider<AudioPlayerNotifier, AudioPlayerState>(
  () => AudioPlayerNotifier(),
);
