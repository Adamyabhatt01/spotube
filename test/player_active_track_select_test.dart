// Regression test for Phase 2 W.2: providers that only consume
// `AudioPlayerState.activeTrack` must not rebuild on playing/loop/shuffle
// changes, while still notifying on genuine active-track changes.
//
// Hermetic: `audioPlayerProvider` is overridden with a scripted fake (no
// media_kit), and the sourcedTrack family hangs (loading) so no hetu/DB is
// touched.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/server/active_track_sources.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  _FakeAudioPlayerNotifier(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

class _HangingSourcedTrackNotifier extends SourcedTrackNotifier {
  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) {
    return Completer<SourcedTrack>().future;
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

void main() {
  late ProviderContainer container;
  late _FakeAudioPlayerNotifier fakePlayer;

  setUp(() {
    fakePlayer = _FakeAudioPlayerNotifier(_playerState(tracks: const []));
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => fakePlayer),
        sourcedTrackProvider
            .overrideWith(() => _HangingSourcedTrackNotifier()),
      ],
    );
  });

  tearDown(() => container.dispose());

  // Note on what each half proves (verified by reverting W.2): the
  // activeTrackSources half is the mechanism proof — with a full watch,
  // every flag flip re-emits (async loading transitions) and the test
  // fails. The queryingTrackInfo negative case locks the value contract
  // instead (bool equality already suppresses its notifications); it guards
  // against future edits that would make flag state leak into its return
  // value, while the select skips the rebuild work itself.
  test('queryingTrackInfo ignores flag changes, fires on track change',
      () async {
    var notifications = 0;
    container.listen(
      queryingTrackInfoProvider,
      (_, __) => notifications++,
    );

    expect(container.read(queryingTrackInfoProvider), isFalse);
    final baseline = notifications;

    // Negative: playing/loop/shuffle flips with the same (empty) queue.
    fakePlayer.emit(
      _playerState(tracks: const [], playing: true, shuffled: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, baseline,
        reason: 'flag change must not notify activeTrack-only consumers');

    // Positive: setting an active track notifies (false -> loading true).
    final track = _testTrack('track-1');
    fakePlayer.emit(_playerState(tracks: [track], playing: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, greaterThan(baseline),
        reason: 'active-track change must notify');
    expect(container.read(queryingTrackInfoProvider), isTrue);
  });

  test('activeTrackSources ignores flag changes, fires on track change',
      () async {
    var notifications = 0;
    container.listen(
      activeTrackSourcesProvider,
      (_, __) => notifications++,
    );

    expect(await container.read(activeTrackSourcesProvider.future), isNull);
    final baseline = notifications;

    // Negative: flag flips with no active track.
    fakePlayer.emit(
      _playerState(tracks: const [], playing: true, shuffled: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, baseline,
        reason: 'flag change must not notify activeTrack-only consumers');

    // Positive: setting an active track notifies (null -> loading).
    final track = _testTrack('track-1');
    fakePlayer.emit(_playerState(tracks: [track], playing: true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, greaterThan(baseline),
        reason: 'active-track change must notify');

    // Negative again: flag flip with the SAME active track stays silent.
    final afterTrackChange = notifications;
    fakePlayer.emit(
      _playerState(tracks: [track], playing: false, shuffled: true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, afterTrackChange,
        reason: 'flag change with unchanged track must not notify');
  });

  // PR2 (player rebuild scoping): the exact selectors adopted by list
  // rows, cards and lyrics views must stay silent on flag flips and fire
  // only on the slice they consume.
  test('activeTrack-id selector ignores flags, fires on index change', () async {
    var notifications = 0;
    container.listen(
      audioPlayerProvider.select((s) => s.activeTrack?.id),
      (_, __) => notifications++,
    );

    final trackA = _testTrack('track-a');
    final trackB = _testTrack('track-b');
    fakePlayer.emit(_playerState(tracks: [trackA, trackB]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final baseline = notifications;

    // Flag flips (playing/shuffled/loopMode) must not notify.
    fakePlayer.emit(
      AudioPlayerState(
        playing: true,
        loopMode: PlaylistMode.loop,
        shuffled: true,
        collections: const [],
        currentIndex: 0,
        tracks: [trackA, trackB],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, baseline,
        reason: 'flag flips must not notify id-only consumers');

    // Queue append keeping the same active track must not notify.
    fakePlayer.emit(_playerState(tracks: [trackA, trackB, _testTrack('c')]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, baseline,
        reason: 'same active id must not notify despite queue change');

    // Index change notifies.
    fakePlayer.emit(_playerState(tracks: [trackA, trackB], currentIndex: 1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifications, greaterThan(baseline),
        reason: 'active-track change must notify');
    expect(container.read(audioPlayerProvider.select((s) => s.activeTrack?.id)),
        'track-b');
  });

  test('tracks/collections selectors ignore flags, fire on own slice',
      () async {
    var trackNotifications = 0;
    var collectionNotifications = 0;
    container.listen(
      audioPlayerProvider.select((s) => s.tracks),
      (_, __) => trackNotifications++,
    );
    container.listen(
      audioPlayerProvider.select((s) => s.collections),
      (_, __) => collectionNotifications++,
    );

    final track = _testTrack('track-1');
    // Same list instance across emits, mirroring copyWith carrying the
    // unchanged queue reference (List == is identity).
    final queue = [track];
    fakePlayer.emit(_playerState(tracks: queue));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final trackBaseline = trackNotifications;
    final collectionBaseline = collectionNotifications;

    fakePlayer.emit(
      AudioPlayerState(
        playing: true,
        loopMode: PlaylistMode.loop,
        shuffled: true,
        collections: const [],
        currentIndex: 0,
        tracks: queue,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(trackNotifications, trackBaseline,
        reason: 'flag flips must not notify tracks-only consumers');
    expect(collectionNotifications, collectionBaseline,
        reason: 'flag flips must not notify collections-only consumers');

    // Collection slice fires only when collections change.
    fakePlayer.emit(
      AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const ['collection-1'],
        currentIndex: 0,
        tracks: queue,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(collectionNotifications, greaterThan(collectionBaseline),
        reason: 'collection change must notify');
    expect(trackNotifications, trackBaseline,
        reason: 'collection change must not notify tracks-only consumers');
  });

  test('listContains helpers match instance-method semantics', () {
    final full = _testTrack('full-1');
    final other = _testTrack('other-1');
    final localA = SpotubeLocalTrackObject(
      id: 'local-1',
      name: 'Local',
      externalUri: 'file:///music/a.mp3',
      album: SpotubeSimpleAlbumObject(
        id: 'album-local',
        name: 'Local Album',
        externalUri: 'https://example.test/album/local',
        artists: const [],
        albumType: SpotubeAlbumType.album,
      ),
      artists: const [],
      durationMs: 1000,
      path: '/music/a.mp3',
    );
    final localSamePath = SpotubeLocalTrackObject(
      id: 'local-2',
      name: 'Local copy',
      externalUri: 'file:///music/a.mp3',
      album: localA.album,
      artists: const [],
      durationMs: 1000,
      path: '/music/a.mp3',
    );

    final state = _playerState(tracks: [full, localA]);
    expect(AudioPlayerState.listContainsTrack(state.tracks, full),
        state.containsTrack(full));
    expect(AudioPlayerState.listContainsTrack(state.tracks, other),
        state.containsTrack(other));
    // Local tracks match by path, not id.
    expect(AudioPlayerState.listContainsTrack(state.tracks, localSamePath),
        isTrue);
    expect(
      AudioPlayerState.listContainsTracks(state.tracks, [full, localSamePath]),
      state.containsTracks([full, localSamePath]),
    );
    expect(
      AudioPlayerState.listContainsTracks(state.tracks, [full, other]),
      isFalse,
    );
  });
}
