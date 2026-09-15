// Regression test for Phase 2 W.4: `trackOptionsStateProvider` subscribes
// to the consumed audio-player slices (`activeTrack`, `tracks`) instead of
// the full player state.
//
// Expectations mirror W.2: flag flips stay silent; active-track changes and
// queue mutations notify; `containsTrack` behavior is identical; download
// and blacklist behavior is untouched (their watches remain).
//
// Hermetic: the player is a scripted fake (no media_kit), the blacklist is
// stubbed empty (no DB), metadata plugins fail fast (no hetu), and the
// download manager runs for real (pure in-memory default state).

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/track_options/track_options_provider.dart';

class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  _FakeAudioPlayerNotifier(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

class _FailingMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() {
    throw StateError('no metadata plugins in unit tests');
  }
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

AudioPlayerState _playerState({
  required List<SpotubeTrackObject> tracks,
  int currentIndex = 0,
  bool playing = false,
  bool shuffled = false,
}) {
  return AudioPlayerState(
    playing: playing,
    loopMode: PlaylistMode.none,
    shuffled: shuffled,
    collections: const [],
    currentIndex: currentIndex,
    tracks: tracks,
  );
}

// Note on what this file proves: Riverpod suppresses notifications AND
// observer updates for rebuilds whose value is ==-equal, and freezed
// re-wraps list fields on every state construction (so state-object identity
// never holds across emits). Hence rebuild-skipping itself is not observable
// through public APIs. What IS locked here:
//  1. the value contract (flag flips never surface; real changes notify);
//  2. behavioral identity of the inlined queue-membership predicate against
//     the AudioPlayerState.containsTrack oracle across a case matrix — this
//     guards the predicate duplication introduced by subscribing to `tracks`
//     instead of the full player state.
void main() {
  late ProviderContainer container;
  late _FakeAudioPlayerNotifier fakePlayer;

  setUp(() {
    fakePlayer = _FakeAudioPlayerNotifier(_playerState(tracks: const []));
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => fakePlayer),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        metadataPluginsProvider
            .overrideWith(() => _FailingMetadataPluginNotifier()),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('flag flips stay silent; track and queue changes notify', () async {
    final track = _testTrack('track-1');
    // Same list instance across emits: real flag flips preserve the queue
    // reference via copyWith, and select compares list identity.
    final queue = <SpotubeTrackObject>[track];
    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(track),
      (_, __) => notifications++,
    );

    final initial = container.read(trackOptionsStateProvider(track));
    expect(initial.isInQueue, isFalse);
    expect(initial.isActiveTrack, isFalse);
    expect(initial.isBlacklisted, isFalse);
    expect(initial.isInDownloadQueue, isFalse);
    final baseline = notifications;

    // Negative: playing/shuffle flips with the same (empty) queue.
    fakePlayer.emit(
      _playerState(tracks: const [], playing: true, shuffled: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, baseline,
        reason: 'flag change must not rebuild menu state');

    // Positive: queue mutation carrying the track notifies.
    fakePlayer.emit(_playerState(tracks: queue, playing: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, greaterThan(baseline),
        reason: 'queue mutation must rebuild menu state');

    // containsTrack behavior identical: track now in queue and active.
    final updated = container.read(trackOptionsStateProvider(track));
    expect(updated.isInQueue, isTrue);
    expect(updated.isActiveTrack, isTrue);
    expect(updated.isBlacklisted, isFalse);
    expect(updated.isInDownloadQueue, isFalse);

    // Negative again: flag flip with the same queue stays silent.
    final afterQueueChange = notifications;
    fakePlayer.emit(
      _playerState(tracks: queue, playing: false, shuffled: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, afterQueueChange,
        reason: 'flag change with unchanged queue must not rebuild');
  });

  test('active-track switch notifies without queue mutation', () async {
    final trackA = _testTrack('track-a');
    final trackB = _testTrack('track-b');
    // Same list instance: only the index changes, mirroring a track
    // advance that reuses the queue reference.
    final queue = <SpotubeTrackObject>[trackA, trackB];

    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(trackB),
      (_, __) => notifications++,
    );

    // Mount with the first track active (initial read settles the baseline).
    fakePlayer.emit(_playerState(tracks: queue));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(trackOptionsStateProvider(trackB)).isActiveTrack,
      isFalse,
    );
    final baseline = notifications;

    // Same queue instance content, different index -> active track changes.
    fakePlayer.emit(
      _playerState(tracks: queue, currentIndex: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, greaterThan(baseline),
        reason: 'active-track switch must rebuild menu state');
    expect(
      container.read(trackOptionsStateProvider(trackB)).isActiveTrack,
      isTrue,
    );
  });

  test('isInQueue matches AudioPlayerState.containsTrack oracle', () async {
    SpotubeLocalTrackObject local(String id, String path) {
      return SpotubeLocalTrackObject(
        id: id,
        name: 'Local $id',
        externalUri: 'file://$path',
        album: SpotubeSimpleAlbumObject(
          id: 'test-album-1',
          name: 'Test Album',
          externalUri: 'https://example.test/album/1',
          artists: const [],
          albumType: SpotubeAlbumType.album,
        ),
        durationMs: 180000,
        path: path,
      );
    }

    final fullA = _testTrack('a');
    final fullB = _testTrack('b');
    final localX1 = local('x', '/music/x.mp3');
    final localX2 = local('x', '/music/x.mp3');
    final localY = local('x', '/music/y.mp3');

    final cases = <String, (List<SpotubeTrackObject>, SpotubeTrackObject)>{
      'empty queue': (const [], fullA),
      'track present': ([fullA], fullA),
      'track absent': ([fullA], fullB),
      'local same path': ([localX1], localX2),
      'local different path': ([localX1], localY),
      // Predicate falls back to id comparison unless BOTH sides are local.
      'full queue, local menu, same id': ([fullA], local('a', '/other.mp3')),
      'local queue, full menu, same id': (
        [local('a', '/music/a.mp3')],
        _testTrack('a')
      ),
    };

    // Mount the player before emitting (unmounted notifiers reject state).
    container.read(trackOptionsStateProvider(fullA));

    for (final entry in cases.entries) {
      final (queue, menuTrack) = entry.value;
      fakePlayer.emit(_playerState(tracks: queue));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final oracle = AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        tracks: queue,
      ).containsTrack(menuTrack);
      final actual =
          container.read(trackOptionsStateProvider(menuTrack)).isInQueue;

      expect(actual, oracle, reason: 'case: ${entry.key}');
    }
  });
}
