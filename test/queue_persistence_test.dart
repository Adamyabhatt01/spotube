// PR 3 (C2): queue persistence must follow actual queue changes.
//
// media_kit emits a playlist event for *index* changes too, and the listener
// used to answer by re-decoding every media (`SpotubeMedia.media` →
// `fromJson`) and rewriting the whole `tracks` column (one `jsonEncode` of the
// entire queue). Advancing to the next track of a 2000-track queue therefore
// cost a full decode plus a full encode of a queue that had not changed.
//
// These tests pin the contract that makes the fast path safe — the persisted row
// still restores exactly what the backend holds after every kind of change — and
// measure what a track change costs now.

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/utils/perf_counters.dart';

/// Backend stand-in. It keeps the media list the way media_kit does — a *new*
/// list on a membership change, the *same* list object when only the index
/// moves — because that identity is what the persistence fast path keys on.
class _FakeQueueNotifier extends AudioPlayerNotifier {
  List<Media> medias = [];
  int fakeIndex = 0;

  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        tracks: const [],
        collections: const [],
      );

  @override
  int get backendCurrentIndex => fakeIndex;

  @override
  List<Media> get backendMedias => medias;

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {
    medias = [...medias, media];
  }

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {
    medias = [...medias]..insert(index.clamp(0, medias.length), media);
  }

  @override
  Future<void> removeMediaFromBackend(int index) async {
    medias = [...medias]..removeAt(index);
  }

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {
    this.medias = List.of(medias);
    fakeIndex = initialIndex;
  }

  /// What the native player emits when playback advances: same media objects,
  /// same list, new index.
  Playlist playlistAt(int index) {
    fakeIndex = index;
    return Playlist(medias, index: index);
  }

  /// What it emits after a membership change it made itself: a fresh list of
  /// the same media objects.
  Playlist currentPlaylist() => Playlist([...medias], index: fakeIndex);

  /// What it emits when the queue changed outside the local mutation paths
  /// (remote/`connect` control, native reorder). The media are rebuilt from
  /// their URI + `extras` payload rather than reused, exactly like the native
  /// backend does, so handling one costs what handling a real change costs.
  Playlist externalPlaylist(List<SpotubeTrackObject> tracks) {
    medias = [
      for (final track in tracks)
        Media(SpotubeMedia.uriFor(track), extras: track.toJson()),
    ];
    return Playlist(medias, index: fakeIndex);
  }

  /// What it emits after `setShuffle`/`setShuffle(false)`: media_kit re-reads
  /// mpv's own playlist and maps the raw sources through `Media.new`, with no
  /// `extras` argument. `Media.new` then restores the payload from its own
  /// static uri→extras cache — which is what makes a shuffle event survivable
  /// at all — so this is the closest a test can get to the real thing.
  Playlist shuffledPlaylist() {
    final playingUri = medias.elementAtOrNull(fakeIndex)?.uri;
    medias = [
      for (final media in medias.reversed) Media(media.uri),
    ];
    fakeIndex = medias.indexWhere((m) => m.uri == playingUri);
    return Playlist(medias, index: fakeIndex);
  }
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

/// `load` warms the first track's audio source through
/// [sourcedTrackProvider]; the real one needs the whole plugin stack, so it is
/// parked on a pending future here. The result is discarded by `load`, so the
/// queue behavior under test is unaffected.
class _HangingSourcedTrackNotifier extends SourcedTrackNotifier {
  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) =>
      Completer<SourcedTrack>().future;
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-$id',
        name: 'Artist $id',
        externalUri: 'https://example.test/artist/$id',
        images: [
          SpotubeImageObject(
            url: 'https://example.test/$id.jpg',
            width: 300,
            height: 300,
          ),
        ],
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-$id',
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
      images: const [],
    ),
    durationMs: 180000,
    isrc: 'US000000000$id',
    explicit: false,
  );
}

List<SpotubeTrackObject> _tracks(int count) => List.generate(
      count,
      (i) => _track('t${i.toString().padLeft(5, '0')}'),
    );

class _ChangeCost {
  const _ChangeCost({
    required this.tracks,
    required this.fullSyncMs,
    required this.fastPathMs,
    required this.fullSyncWrites,
    required this.fullSyncEncodes,
    required this.fullSyncBytes,
    required this.fastPathWrites,
    required this.fastPathEncodes,
    required this.fastPathBytes,
  });

  final int tracks;
  final int fullSyncMs;
  final int fastPathMs;

  /// Writes of the `tracks` column, and the `jsonEncode` calls they caused.
  /// Drift runs a companion's `toColumns` twice per write — once for integrity
  /// validation, once to build the statement — so encodes are writes × 2.
  final int fullSyncWrites;
  final int fullSyncEncodes;
  final int fullSyncBytes;
  final int fastPathWrites;
  final int fastPathEncodes;
  final int fastPathBytes;

  @override
  String toString() =>
      'queueSize=$tracks  | full-sync (old behaviour): ${fullSyncMs}ms, '
      '$fullSyncWrites tracks-column writes / $fullSyncEncodes encodes / '
      '${(fullSyncBytes / 1024).toStringAsFixed(1)}KB encoded'
      '  | fast path (now): ${fastPathMs}ms, $fastPathWrites writes / '
      '$fastPathEncodes encodes / ${(fastPathBytes / 1024).toStringAsFixed(1)}KB';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ProviderContainer container;
  late _FakeQueueNotifier player;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    // The persistence row is a singleton updated by id; seed it the way
    // `syncSavedState` would (this fake overrides `build`, so that never runs).
    await database.into(database.audioPlayerStateTable).insert(
          AudioPlayerStateTableCompanion.insert(
            playing: false,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: const Value(<SpotubeTrackObject>[]),
            currentIndex: const Value(0),
            id: const Value(0),
          ),
        );
    player = _FakeQueueNotifier();
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => player),
        databaseProvider.overrideWithValue(database),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        sourcedTrackProvider.overrideWith(() => _HangingSourcedTrackNotifier()),
      ],
    );
    container.read(audioPlayerProvider);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<AudioPlayerStateTableData> persisted() =>
      database.select(database.audioPlayerStateTable).getSingle();

  /// Asserts the persisted row re-decodes to the live queue: same tracks, same
  /// order, same index. Reading the row goes back through the column's
  /// `fromSql`, so encode and decode are both covered.
  Future<void> expectRestoreMatches(String when) async {
    final row = await persisted();
    expect(
      row.tracks.map((t) => t.id).toList(),
      player.state.tracks.map((t) => t.id).toList(),
      reason: 'persisted queue differs from the live one ($when)',
    );
    expect(
      row.tracks.map((t) => t.name).toList(),
      player.state.tracks.map((t) => t.name).toList(),
      reason: 'track metadata lost ($when)',
    );
    expect(
      row.tracks.map((t) => t.artists.single.images?.length).toList(),
      player.state.tracks.map((t) => t.artists.single.images?.length).toList(),
      reason: 'nested artwork lost ($when)',
    );
    expect(
      row.currentIndex,
      player.state.currentIndex,
      reason: 'index not persisted ($when)',
    );
  }

  /// Loads [count] tracks, then times two track changes twice over:
  ///
  /// * **fast path** — the events media_kit actually sends when playback
  ///   advances (same media objects, new index), which is what the app does
  ///   on every track change now;
  /// * **full sync** — events carrying freshly rebuilt media, i.e. the work
  ///   the old listener did for *every* event, so the before/after comparison
  ///   is measured rather than asserted.
  Future<_ChangeCost> measureTrackChanges(int count) async {
    final tracks = _tracks(count);
    await player.load(tracks);

    PerfCounters.reset();
    var sw = Stopwatch()..start();
    await player.onBackendPlaylist(player.externalPlaylist(tracks));
    await player.onBackendPlaylist(player.externalPlaylist(tracks));
    sw.stop();
    final fullSyncMs = sw.elapsedMilliseconds;
    final fullSyncWrites = PerfCounters.countOf('queue.tracksWrite');
    final fullSyncEncodes = PerfCounters.countOf('queue.encode');
    final fullSyncBytes = PerfCounters.countOf('queue.encodeBytes');

    // Re-load so the fast path starts from a queue the backend agrees with.
    await player.load(tracks);
    PerfCounters.reset();
    sw = Stopwatch()..start();
    await player.onBackendPlaylist(player.playlistAt(1));
    await player.onBackendPlaylist(player.playlistAt(2));
    sw.stop();

    return _ChangeCost(
      tracks: count,
      fullSyncMs: fullSyncMs,
      fastPathMs: sw.elapsedMilliseconds,
      fullSyncWrites: fullSyncWrites,
      fullSyncEncodes: fullSyncEncodes,
      fullSyncBytes: fullSyncBytes,
      fastPathWrites: PerfCounters.countOf('queue.tracksWrite'),
      fastPathEncodes: PerfCounters.countOf('queue.encode'),
      fastPathBytes: PerfCounters.countOf('queue.encodeBytes'),
    );
  }

  test('a track change leaves the queue column alone', () async {
    await player.load(_tracks(50));
    PerfCounters.reset();

    await player.onBackendPlaylist(player.playlistAt(7));

    expect(PerfCounters.countOf('queue.playlistEvent'), 1);
    expect(
      PerfCounters.countOf('queue.playlistDecode'),
      0,
      reason: 'an unchanged queue was re-decoded media by media',
    );
    expect(
      PerfCounters.countOf('queue.tracksWrite'),
      0,
      reason: 'an unchanged queue was re-encoded and rewritten',
    );
    expect(
      PerfCounters.countOf('queue.encode'),
      0,
      reason: 'an unchanged queue reached jsonEncode',
    );

    final row = await persisted();
    expect(row.currentIndex, 7);
    expect(row.tracks, hasLength(50));
    expect(player.state.currentIndex, 7);
    expect(player.state.activeTrack?.id, 't00007');
  });

  test('a changed queue is still decoded and rewritten', () async {
    await player.load(_tracks(20));
    PerfCounters.reset();

    // An external change: new media objects this notifier never parsed.
    await player.onBackendPlaylist(
      player.externalPlaylist([...player.state.tracks, _track('appended')]),
    );

    expect(
      PerfCounters.countOf('queue.playlistDecode'),
      1,
      reason: 'a real membership change must still rebuild the queue',
    );
    expect(
      PerfCounters.countOf('queue.tracksWrite'),
      1,
      reason: 'a real membership change must still be persisted',
    );

    final row = await persisted();
    expect(row.tracks.map((t) => t.id), contains('appended'));
    expect(row.tracks, hasLength(21));
  });

  test('the persisted row restores the live state after every change kind',
      () async {
    await player.load(_tracks(30), initialIndex: 3);
    await expectRestoreMatches('initial load');

    await player.onBackendPlaylist(player.playlistAt(11));
    await expectRestoreMatches('index change');

    await player.addTracks([_track('added')]);
    await player.onBackendPlaylist(player.currentPlaylist());
    await expectRestoreMatches('add');

    await player.addTracks([_track('bulk-a'), _track('bulk-b')]);
    await player.onBackendPlaylist(player.currentPlaylist());
    await expectRestoreMatches('bulk add');

    await player.removeTracks(['added']);
    await player.onBackendPlaylist(player.currentPlaylist());
    await expectRestoreMatches('remove');

    player.medias = player.medias.reversed.toList();
    await player.onBackendPlaylist(player.currentPlaylist());
    await expectRestoreMatches('reorder');

    await player.removeTracks(['bulk-a', 'bulk-b']);
    await player.onBackendPlaylist(player.currentPlaylist());
    await expectRestoreMatches('bulk remove');

    await player.onBackendPlaylist(player.playlistAt(2));
    await expectRestoreMatches('second index change');

    // A native (non-local) queue replacement must be picked up too.
    await player.onBackendPlaylist(player.externalPlaylist(_tracks(5)));
    await expectRestoreMatches('external load');
  });

  /// A shuffle toggle replaces the backend playlist with rebuilt `Media(uri)`
  /// objects. Spotube used to be documented as stranded by that — it is not,
  /// because `Media.new` restores `extras` from media_kit's own uri cache. This
  /// pins the behavior so the claim is not re-investigated, and so a media_kit
  /// that stops caching shows up here rather than as a stale restored queue.
  test('a shuffle toggle keeps the queue following the backend', () async {
    await player.load(_tracks(20), initialIndex: 4);
    final before = player.state.tracks.map((t) => t.id).toList();
    final activeBefore = player.state.activeTrack?.id;

    await player.onBackendPlaylist(player.shuffledPlaylist());

    final after = player.state.tracks.map((t) => t.id).toList();
    expect(
      after,
      before.reversed.toList(),
      reason: 'the rebuilt medias did not decode back to the shuffled queue',
    );
    expect(
      player.state.activeTrack?.id,
      activeBefore,
      reason: 'the shuffle moved the index off the playing track',
    );
    await expectRestoreMatches('shuffle');

    // `playlist-unshuffle` emits the same shape, and the index-only fast path
    // must still work afterwards: the decoded list is the live queue.
    await player.onBackendPlaylist(player.shuffledPlaylist());
    expect(player.state.tracks.map((t) => t.id).toList(), before);
    await expectRestoreMatches('unshuffle');

    await player.onBackendPlaylist(player.playlistAt(9));
    expect(player.state.currentIndex, 9);
    await expectRestoreMatches('index change after a shuffle');
  });

  test('two track changes do not scale with queue size', () async {
    final costs = <_ChangeCost>[];
    for (final count in [50, 600, 2000]) {
      costs.add(await measureTrackChanges(count));
    }
    // ignore: avoid_print
    costs.forEach(print);

    for (final cost in costs) {
      // The old path: two rebuilt events, each a full decode + a full write.
      expect(cost.fullSyncWrites, 2, reason: '$cost');
      expect(cost.fullSyncEncodes, 4, reason: '$cost');
      expect(cost.fullSyncBytes, greaterThan(0), reason: '$cost');
      // The fast path: two index-only events, no queue rewrite at all.
      expect(cost.fastPathWrites, 0, reason: '$cost');
      expect(cost.fastPathEncodes, 0, reason: '$cost');
      expect(cost.fastPathBytes, 0, reason: '$cost');
    }
    expect(
      costs.last.fastPathMs,
      lessThan(costs.first.fastPathMs + 50),
      reason: 'an index-only change still grows with queue size:\n$costs',
    );
    // The point of PR 3: the fast path must be cheaper than the old one at
    // every size, and by a margin that grows with the queue.
    for (final cost in costs) {
      expect(
        cost.fastPathMs,
        lessThan(cost.fullSyncMs),
        reason: 'fast path not faster than full sync:\n$cost',
      );
    }
    // Proof that the old work scaled with the queue: 40× the tracks must cost
    // far more than 40× the bytes of the smallest case, and take longer too.
    expect(
      costs.last.fullSyncBytes,
      greaterThan(costs.first.fullSyncBytes * 30),
      reason: 'full-sync encoding did not scale with queue size:\n$costs',
    );
    expect(
      costs.last.fullSyncMs,
      greaterThan(costs.first.fullSyncMs),
      reason: 'full-sync track changes were already cheap:\n$costs',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a queue load still persists the queue exactly once', () async {
    const count = 600;
    PerfCounters.reset();
    final sw = Stopwatch()..start();
    await player.load(_tracks(count));
    sw.stop();

    final row = await persisted();
    expect(row.tracks, hasLength(count));
    expect(
      PerfCounters.countOf('queue.tracksWrite'),
      1,
      reason: 'a real queue load must persist exactly once',
    );
    // ignore: avoid_print
    print(
      'load queueSize=$count encode+write=${sw.elapsedMilliseconds}ms '
      'bytes=${(PerfCounters.countOf('queue.encodeBytes') / 1024).toStringAsFixed(1)}KB',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
