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
  int fakeIndex = 0;

  @override
  AudioPlayerState build() => _playerState(tracks: const []);

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {
    backendCalls.add('add:${media.track.id}');
    backendQueue.add(media.track);
  }

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {
    backendCalls.add('insert:$index:${media.track.id}');
    backendQueue.insert(index.clamp(0, backendQueue.length), media.track);
  }

  @override
  Future<void> removeMediaFromBackend(int index) async {
    backendCalls.add('remove:$index');
    backendQueue.removeAt(index);
  }

  @override
  int get backendCurrentIndex => fakeIndex;
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
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
}
