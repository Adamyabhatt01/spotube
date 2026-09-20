// PR4: queue bulk-mutation contract for AudioPlayerNotifier.
//
// Covered: addTracks (1/100/500, duplicates, locals, shuffled queue),
// addTracksAtFirst (ordering, inserts, dedupe), removeTracks (middle/end,
// descending native order, unknown ids, empty input).
//
// Hermetic: backend calls go through the notifier's backend seam,
// overridden here by a recording fake (no media_kit); Drift runs on an
// in-memory database; blacklist is stubbed empty. Each bulk op must
// produce exactly one state emission and one persisted queue row, with
// backend calls sequential and in order.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

class _RecordingBackendNotifier extends AudioPlayerNotifier {
  final List<String> backendCalls = [];
  final List<SpotubeTrackObject> backendQueue = [];

  /// The media list the native backend holds. Kept in step with
  /// [backendQueue] and replaced wholesale on every membership change, the way
  /// media_kit does, so `backendMedias` stays a faithful mirror.
  List<Media> medias = const [];
  int fakeIndex = 0;

  @override
  AudioPlayerState build() => _playerState(tracks: const []);

  @override
  List<Media> get backendMedias => medias;

  void backendAdd(SpotubeMedia media) {
    backendQueue.add(media.track);
    medias = [...medias, media];
  }

  void backendInsert(SpotubeMedia media, int index) {
    final at = index.clamp(0, backendQueue.length);
    backendQueue.insert(at, media.track);
    medias = [...medias]..insert(at, media);
  }

  void backendRemove(int index) {
    backendQueue.removeAt(index);
    medias = [...medias]..removeAt(index);
  }

  void backendOpen(List<SpotubeMedia> opened) {
    backendQueue
      ..clear()
      ..addAll(opened.map((m) => m.track));
    medias = List<Media>.of(opened);
  }

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {
    backendCalls.add('add:${media.track.id}');
    backendAdd(media);
  }

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {
    backendCalls.add('insert:$index:${media.track.id}');
    backendInsert(media, index);
  }

  @override
  Future<void> removeMediaFromBackend(int index) async {
    backendCalls.add('remove:$index');
    backendRemove(index);
  }

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {
    backendCalls.add('open:$initialIndex:${medias.length}');
    backendOpen(medias);
  }

  @override
  int get backendCurrentIndex => fakeIndex;
}

/// Recording backend where one designated call (matched by its recorded
/// string, e.g. 'add:t3') throws before mutating, so failure-path
/// rollback behavior can be exercised.
class _FailingBackendNotifier extends _RecordingBackendNotifier {
  String? failOnCall;
  bool throwOnOpen = false;

  bool _failIf(String record) {
    backendCalls.add(record);
    if (record == failOnCall) {
      failOnCall = null;
      throw StateError('simulated backend failure');
    }
    return false;
  }

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {
    if (_failIf('add:${media.track.id}')) return;
    backendAdd(media);
  }

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {
    if (_failIf('insert:$index:${media.track.id}')) return;
    backendInsert(media, index);
  }

  @override
  Future<void> removeMediaFromBackend(int index) async {
    if (_failIf('remove:$index')) return;
    backendRemove(index);
  }

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {
    if (throwOnOpen) {
      backendCalls.add('open:$initialIndex:${medias.length}');
      throw StateError('simulated open failure');
    }
    await super.openPlaylistOnBackend(
      medias,
      initialIndex: initialIndex,
      autoPlay: autoPlay,
    );
  }
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

/// Blacklist whose contents tests can flip at runtime.
class _StubBlacklistNotifier extends BlackListNotifier {
  final Set<String> blockedIds = {};

  @override
  Future<List<BlacklistTableData>> build() async => [];

  @override
  bool contains(SpotubeTrackObject track) =>
      blockedIds.contains(track.id) ||
      track.artists.any((a) => blockedIds.contains(a.id));
}

SpotubeFullTrackObject _testTrack(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'test-artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

SpotubeLocalTrackObject _localTrack(String id, String path) {
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Local $id',
    externalUri: 'file://$path',
    album: SpotubeSimpleAlbumObject(
      id: 'album-local',
      name: 'Local Album',
      externalUri: 'https://example.test/album/local',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    artists: const [],
    durationMs: 1000,
    path: path,
  );
}

AudioPlayerState _playerState({
  required List<SpotubeTrackObject> tracks,
  int currentIndex = 0,
  bool playing = false,
  bool shuffled = false,
  PlaylistMode loopMode = PlaylistMode.none,
}) {
  return AudioPlayerState(
    playing: playing,
    loopMode: loopMode,
    shuffled: shuffled,
    collections: const [],
    currentIndex: currentIndex,
    tracks: tracks,
  );
}

void main() {
  late ProviderContainer container;
  late _RecordingBackendNotifier player;
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    // Seed the singleton resume row so the final sync UPDATE persists.
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
    player = _RecordingBackendNotifier();
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => player),
        databaseProvider.overrideWithValue(database),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
      ],
    );
    // Attach the notifier to the container (builds initial state).
    container.read(audioPlayerProvider);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<List<String>> persistedIds() async {
    final row = await database.select(database.audioPlayerStateTable).getSingle();
    return [for (final t in row.tracks) t.id];
  }

  test('add single track: one emission, one backend call, persisted', () async {
    var emissions = 0;
    container.listen(audioPlayerProvider, (_, __) => emissions++);

    await player.addTracks([_testTrack('a')]);

    expect(player.state.tracks.map((t) => t.id), ['a']);
    expect(player.backendCalls, ['add:a']);
    expect(player.backendQueue.map((t) => t.id), ['a']);
    expect(emissions, 1);
    expect(await persistedIds(), ['a']);
  });

  for (final n in [100, 500]) {
    test('add $n tracks preserves order end-to-end', () async {
      var emissions = 0;
      container.listen(audioPlayerProvider, (_, __) => emissions++);

      final tracks = [for (var i = 0; i < n; i++) _testTrack('t$i')];
      await player.addTracks(tracks);

      final ids = [for (var i = 0; i < n; i++) 't$i'];
      expect(player.state.tracks.map((t) => t.id), ids);
      expect(player.backendQueue.map((t) => t.id), ids);
      expect(player.backendCalls, [for (final id in ids) 'add:$id']);
      expect(emissions, 1);
      expect(await persistedIds(), ids);
    });
  }

  test('addTracks allows duplicates (documented behavior)', () async {
    final a = _testTrack('a');
    await player.addTracks([a, a, _testTrack('b')]);

    expect(player.state.tracks.map((t) => t.id), ['a', 'a', 'b']);
    expect(player.backendCalls, ['add:a', 'add:a', 'add:b']);
    expect(await persistedIds(), ['a', 'a', 'b']);
  });

  test('local tracks mix with remote tracks in order', () async {
    final tracks = [
      _testTrack('remote-1'),
      _localTrack('local-1', '/music/a.mp3'),
      _testTrack('remote-2'),
    ];
    await player.addTracks(tracks);

    expect(player.state.tracks.map((t) => t.id),
        ['remote-1', 'local-1', 'remote-2']);
    expect(player.backendQueue.map((t) => t.id),
        ['remote-1', 'local-1', 'remote-2']);
    expect(player.backendQueue[1], isA<SpotubeLocalTrackObject>());
    expect(await persistedIds(), ['remote-1', 'local-1', 'remote-2']);
  });

  test('shuffled queue keeps flags and appends in order', () async {
    player.state = _playerState(
      tracks: [_testTrack('x')],
      shuffled: true,
      loopMode: PlaylistMode.loop,
    );

    await player.addTracks([_testTrack('a'), _testTrack('b')]);

    expect(player.state.tracks.map((t) => t.id), ['x', 'a', 'b']);
    expect(player.state.shuffled, isTrue);
    expect(player.state.loopMode, PlaylistMode.loop);
    expect(player.backendCalls, ['add:a', 'add:b']);
  });

  test('remove middle/end tracks: state, native order, persistence', () async {
    final tracks = [for (var i = 1; i <= 5; i++) _testTrack('t$i')];
    await player.addTracks(tracks);
    player.backendCalls.clear();

    var emissions = 0;
    container.listen(audioPlayerProvider, (_, __) => emissions++);

    await player.removeTracks(['t2', 't4']);

    // State, backend queue and DB agree.
    expect(player.state.tracks.map((t) => t.id), ['t1', 't3', 't5']);
    expect(player.backendQueue.map((t) => t.id), ['t1', 't3', 't5']);
    // Descending native removal: index 3 first, then 1.
    expect(player.backendCalls, ['remove:3', 'remove:1']);
    expect(emissions, 1);
    expect(await persistedIds(), ['t1', 't3', 't5']);
  });

  test('remove unknown ids and empty input are no-ops', () async {
    await player.addTracks([_testTrack('a')]);
    player.backendCalls.clear();

    var emissions = 0;
    container.listen(audioPlayerProvider, (_, __) => emissions++);

    await player.removeTracks(['nope']);
    await player.removeTracks([]);
    await player.addTracks([]);

    expect(player.backendCalls, isEmpty);
    expect(emissions, 0);
    expect(player.state.tracks.map((t) => t.id), ['a']);
    expect(await persistedIds(), ['a']);
  });

  test('addTracksAtFirst inserts after cursor in order', () async {
    // NOTE: a 1-track queue takes the addTracks (append) path by design;
    // seed two tracks so the insert path runs.
    await player.addTracks([_testTrack('x'), _testTrack('y')]);
    player.backendCalls.clear();

    await player.addTracksAtFirst([_testTrack('a'), _testTrack('b')]);

    expect(player.state.tracks.map((t) => t.id), ['a', 'b', 'x', 'y']);
    expect(player.backendCalls, ['insert:1:a', 'insert:2:b']);
    expect(await persistedIds(), ['a', 'b', 'x', 'y']);
  });

  test('addTracksAtFirst dedupes against the queue', () async {
    await player.addTracks([_testTrack('a'), _testTrack('x')]);
    player.backendCalls.clear();

    await player.addTracksAtFirst([_testTrack('a'), _testTrack('b')]);

    expect(player.state.tracks.map((t) => t.id), ['b', 'a', 'x']);
    expect(player.backendCalls, ['insert:1:b']);
    expect(await persistedIds(), ['b', 'a', 'x']);
  });

  group('backend failure rollback', () {
    /// Builds a second container backed by the same in-memory database,
    /// driving [notifier] instead of the default recording one.
    Future<T> withNotifier<T extends AudioPlayerNotifier>(T notifier) async {
      final secondary = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWith(() => notifier),
          databaseProvider.overrideWithValue(database),
          blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        ],
      );
      secondary.read(audioPlayerProvider);
      addTearDown(secondary.dispose);
      return notifier;
    }

    test('addTracks mid-failure rolls back backend, state and persistence',
        () async {
      final flaky = await withNotifier(_FailingBackendNotifier()
        ..failOnCall = 'add:c');

      await expectLater(
        flaky.addTracks([_testTrack('a'), _testTrack('b'), _testTrack('c')]),
        throwsStateError,
      );

      expect(flaky.state.tracks, isEmpty);
      expect(flaky.backendQueue, isEmpty);
      expect(await persistedIds(), isEmpty);
      // add:a, add:b landed; add:c threw; rollback removed b then a.
      expect(
        flaky.backendCalls,
        ['add:a', 'add:b', 'add:c', 'remove:1', 'remove:0'],
      );
    });

    test('removeTracks mid-failure re-inserts the removed slice', () async {
      final flaky = await withNotifier(_FailingBackendNotifier());
      await flaky.addTracks([
        _testTrack('a'),
        _testTrack('b'),
        _testTrack('c'),
        _testTrack('d'),
      ]);
      flaky.backendCalls.clear();
      flaky.failOnCall = 'remove:1';

      await expectLater(flaky.removeTracks(['b', 'd']), throwsStateError);

      // First removal (index 3, track d) was rolled back; queue intact.
      expect(flaky.state.tracks.map((t) => t.id), ['a', 'b', 'c', 'd']);
      expect(flaky.backendQueue.map((t) => t.id), ['a', 'b', 'c', 'd']);
      expect(await persistedIds(), ['a', 'b', 'c', 'd']);
      expect(flaky.backendCalls, ['remove:3', 'remove:1', 'insert:3:d']);
    });

    test('addTracksAtFirst mid-failure removes the inserted prefix slice',
        () async {
      final flaky = await withNotifier(_FailingBackendNotifier());
      await flaky.addTracks([_testTrack('x'), _testTrack('y')]);
      flaky.backendCalls.clear();
      flaky.failOnCall = 'insert:2:b';

      await expectLater(
        flaky.addTracksAtFirst([_testTrack('a'), _testTrack('b')]),
        throwsStateError,
      );

      expect(flaky.state.tracks.map((t) => t.id), ['x', 'y']);
      expect(flaky.backendQueue.map((t) => t.id), ['x', 'y']);
      expect(await persistedIds(), ['x', 'y']);
      expect(flaky.backendCalls, ['insert:1:a', 'insert:2:b', 'remove:1']);
    });

    test('load open failure restores the previous queue', () async {
      final flaky = await withNotifier(_FailingBackendNotifier());
      await flaky.addTracks([_testTrack('x')]);
      flaky
        ..backendCalls.clear()
        ..throwOnOpen = true;

      await expectLater(flaky.load([_testTrack('a')]), throwsStateError);

      expect(flaky.state.tracks.map((t) => t.id), ['x']);
      expect(await persistedIds(), ['x']);
      expect(flaky.backendCalls, ['open:0:1']);
    });

    test('load clamps an out-of-range initial index', () async {
      final notifier = await withNotifier(_RecordingBackendNotifier());

      await notifier.load(
        [
          _localTrack('local-a', '/music/a.mp3'),
          _localTrack('local-b', '/music/b.mp3'),
        ],
        initialIndex: 5,
      );

      expect(notifier.state.currentIndex, 1);
      expect(notifier.backendCalls, ['open:1:2']);
      expect(await persistedIds(), ['local-a', 'local-b']);
    });
  });

  group('load input validation', () {
    test('empty input is a no-op', () async {
      await player.load([]);
      expect(player.state.tracks, isEmpty);
      expect(player.backendCalls, isEmpty);
    });

    test('fully blacklisted input is a no-op, no throw', () async {
      final recording = _RecordingBackendNotifier();
      final blacklist = _StubBlacklistNotifier()..blockedIds.addAll(['a', 'b']);
      final secondary = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWith(() => recording),
          databaseProvider.overrideWithValue(database),
          blacklistProvider.overrideWith(() => blacklist),
        ],
      );
      secondary.read(audioPlayerProvider);
      addTearDown(secondary.dispose);

      // Previously threw RangeError via elementAt before the empty check.
      await recording.load(
        [_testTrack('a'), _testTrack('b')],
        initialIndex: 1,
      );

      expect(recording.state.tracks, isEmpty);
      expect(recording.backendCalls, isEmpty);
      expect(await persistedIds(), isEmpty);
    });
  });
}
