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
  bool hasStarted = false,
}) {
  return AudioPlayerState(
    playing: playing,
    loopMode: PlaylistMode.none,
    shuffled: shuffled,
    collections: const [],
    currentIndex: currentIndex,
    tracks: tracks,
    hasStarted: hasStarted,
  );
}

/// Pumps the event loop so already-scheduled microtasks and zero-duration
/// timers run to completion. A real regression schedules work; an idle
/// scheduler drains this deterministically without a wall-clock bet.
Future<void> drain([int yields = 200]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Polls [done] until it returns true or the deadline passes, then fails.
Future<void> eventually(
  bool Function() done,
  String what, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (!done()) fail('$what did not happen within $budget');
}

void main() {
  late ProviderContainer container;
  late _FakeAudioPlayerNotifier fakePlayer;

  setUp(() {
    fakePlayer = _FakeAudioPlayerNotifier(_playerState(tracks: const []));
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => fakePlayer),
        sourcedTrackProvider.overrideWith(() => _HangingSourcedTrackNotifier()),
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
    await drain();
    expect(notifications, baseline,
        reason: 'flag change must not notify activeTrack-only consumers');

    // Positive: setting an active track notifies (false -> loading true).
    final track = _testTrack('track-1');
    fakePlayer.emit(_playerState(tracks: [track], playing: true));
    await eventually(
      () => notifications > baseline,
      'active-track change to notify',
    );
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
    await drain();
    expect(notifications, baseline,
        reason: 'flag change must not notify activeTrack-only consumers');

    // Positive: setting an active track notifies (null -> loading).
    final track = _testTrack('track-1');
    fakePlayer.emit(_playerState(tracks: [track], playing: true));
    await eventually(
      () => notifications > baseline,
      'active-track change to notify',
    );
    expect(notifications, greaterThan(baseline),
        reason: 'active-track change must notify');

    // Negative again: flag flip with the SAME active track stays silent.
    final afterTrackChange = notifications;
    fakePlayer.emit(
      _playerState(tracks: [track], playing: false, shuffled: true),
    );
    await drain();
    expect(notifications, afterTrackChange,
        reason: 'flag change with unchanged track must not notify');
  });

  // PR2 (player rebuild scoping): the exact selectors adopted by list
  // rows, cards and lyrics views must stay silent on flag flips and fire
  // only on the slice they consume.
  test('activeTrack-id selector ignores flags, fires on index change',
      () async {
    var notifications = 0;
    container.listen(
      audioPlayerProvider.select((s) => s.activeTrack?.id),
      (_, __) => notifications++,
    );

    final trackA = _testTrack('track-a');
    final trackB = _testTrack('track-b');
    fakePlayer.emit(_playerState(tracks: [trackA, trackB]));
    await drain();
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
    await drain();
    expect(notifications, baseline,
        reason: 'flag flips must not notify id-only consumers');

    // Queue append keeping the same active track must not notify.
    fakePlayer.emit(_playerState(tracks: [trackA, trackB, _testTrack('c')]));
    await drain();
    expect(notifications, baseline,
        reason: 'same active id must not notify despite queue change');

    // Index change notifies.
    fakePlayer.emit(_playerState(tracks: [trackA, trackB], currentIndex: 1));
    await eventually(
      () => notifications > baseline,
      'active-track index change to notify',
    );
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
    await drain();
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
    await drain();
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
    await eventually(
      () => collectionNotifications > collectionBaseline,
      'collection change to notify',
    );
    // Let any spurious tracks-only notification land before the negative
    // check below.
    await drain();
    expect(collectionNotifications, greaterThan(collectionBaseline),
        reason: 'collection change must notify');
    expect(trackNotifications, trackBaseline,
        reason: 'collection change must not notify tracks-only consumers');
  });

  test('isResolvingActiveTrack stops spinning once the track has sounded',
      () async {
    final trackA = _testTrack('track-a');

    expect(container.read(isResolvingActiveTrackProvider), isFalse);

    // First play: the source is resolving and nothing has been audible.
    fakePlayer.emit(_playerState(tracks: [trackA]));
    await eventually(
      () => container.read(queryingTrackInfoProvider),
      'the active source to start resolving',
    );
    expect(container.read(isResolvingActiveTrackProvider), isTrue,
        reason: 'a first resolve with no audio still needs a spinner');

    // Playback begins. The spinner is gone while the source catches up.
    fakePlayer.emit(
      _playerState(tracks: [trackA], playing: true, hasStarted: true),
    );
    await drain();
    expect(container.read(isResolvingActiveTrackProvider), isFalse,
        reason: 'audible playback is controllable even while resolving');

    // Pause the already-loaded track while the source provider is still
    // loading. This is the regression: it must stay a play button.
    fakePlayer.emit(
      _playerState(tracks: [trackA], playing: false, hasStarted: true),
    );
    await drain();
    expect(container.read(isResolvingActiveTrackProvider), isFalse,
        reason: 'a pause after audible playback must not spin');

    // A new track starts silent and resolving, so the spinner is valid again.
    final trackB = _testTrack('track-b');
    fakePlayer.emit(_playerState(tracks: [trackB]));
    await eventually(
      () => container.read(queryingTrackInfoProvider),
      'the new active source to start resolving',
    );
    expect(container.read(isResolvingActiveTrackProvider), isTrue,
        reason: 'a new track must resolve before it can become audible');
  });
}
