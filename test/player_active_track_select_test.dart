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
}
