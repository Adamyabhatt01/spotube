// The transport verbs a theme (and, from now on, a spoken command) asks for:
// play/pause, next, previous, seek, volume, like. None of these had a test that
// actually reached the dispatcher — the phase-7 file covers the effects chain,
// and the schema tests only pin the action names. This pins the behaviour, so
// the extraction into PlayerActionsService can be proven to change nothing.
//
// Hermetic: the player is a fake port, the queue state a stubbed notifier, the
// library a recorder. No media_kit, no metadata plugin, no database.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart' as port;
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';

/// Records the transport calls and answers the state the guards read.
class _FakePort implements port.AudioPlayerPort {
  _FakePort(
      {this.playing = false, this.duration = const Duration(seconds: 200)});

  bool playing;
  @override
  final Duration duration;

  final calls = <String>[];
  Duration? lastSeek;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> resume() async {
    calls.add('resume');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> skipToNext() async => calls.add('next');

  @override
  Future<void> skipToPrevious() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    lastSeek = position;
  }

  @override
  Future<void> setVolume(double volume) async =>
      calls.add('volume ${volume.toStringAsFixed(3)}');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubPlayer extends AudioPlayerNotifier {
  _StubPlayer(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;
}

/// Captures the like instead of asking a metadata plugin to write to Spotify.
class _RecordingSavedTracks extends MetadataPluginSavedTracksNotifier {
  final toggled = <String>[];

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build() async => SpotubePaginationResponseObject<SpotubeFullTrackObject>(
            items: const [],
            total: 0,
            nextOffset: null,
            limit: 0,
            hasMore: false,
          );

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
    int offset,
    int limit,
  ) =>
      build();

  @override
  Future<void> toggleFavorite(SpotubeTrackObject track) async =>
      toggled.add(track.id);
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-1',
        name: 'Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 200000,
    isrc: 'TEST$id',
    explicit: false,
  );
}

typedef _Harness = ({
  ProviderContainer container,
  BuildContext context,
});

/// The six verbs under test never read the context, so a bare builder is enough
/// — the point is the container wiring, not a rendered app.
Future<_Harness> _harness(
  WidgetTester tester,
  List<Override> overrides,
) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  late BuildContext context;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return (container: container, context: context);
}

Future<void> _run(
  _Harness h,
  String type, [
  Map<String, dynamic> args = const {},
]) =>
    dispatchThemeUiAction(
      h.context,
      h.container,
      ThemeUiAction(type, args),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  group('playPause', () {
    testWidgets('resumes a paused queue', (tester) async {
      final player = _FakePort(playing: false);
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: false,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'playPause');
      expect(player.calls, ['resume']);
    });

    testWidgets('pauses a playing queue', (tester) async {
      final player = _FakePort(playing: true);
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'playPause');
      expect(player.calls, ['pause']);
    });

    testWidgets('an empty queue is left alone', (tester) async {
      final player = _FakePort();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: false,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
          )),
        ),
      ]);

      await _run(h, 'playPause');
      await _run(h, 'next');
      await _run(h, 'previous');
      expect(player.calls, isEmpty,
          reason: 'nothing is loaded, so a command must not start playback');
    });
  });

  group('next and previous', () {
    testWidgets('reach the player', (tester) async {
      final player = _FakePort();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a'), _track('b')],
          )),
        ),
      ]);

      await _run(h, 'next');
      await _run(h, 'previous');
      expect(player.calls, ['next', 'previous']);
    });
  });

  group('seek', () {
    testWidgets('an absolute position is clamped to the duration',
        (tester) async {
      final player = _FakePort(duration: const Duration(seconds: 200));
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'seek', {'position': 30.0});
      expect(player.lastSeek, const Duration(seconds: 30));

      await _run(h, 'seek', {'position': 9999.0});
      expect(player.lastSeek, const Duration(seconds: 200),
          reason: 'a theme cannot seek past the end of the track');

      await _run(h, 'seek', {'position': -5.0});
      expect(player.lastSeek, Duration.zero);
    });

    testWidgets('a fraction is taken of the current duration', (tester) async {
      final player = _FakePort(duration: const Duration(seconds: 200));
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'seek', {'fraction': 0.25});
      expect(player.lastSeek, const Duration(seconds: 50));

      player.calls.clear();
      await _run(h, 'seek', {'fraction': 'half'});
      expect(player.calls, isEmpty, reason: 'a non-number must be ignored');
    });
  });

  group('setVolume', () {
    testWidgets('an absolute value clamps and persists', (tester) async {
      final player = _FakePort();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'setVolume', {'volume': 0.4});
      expect(h.container.read(volumeProvider), 0.4);
      expect(KVStoreService.volume, 0.4,
          reason: 'the level the app restarts at is the user level');

      await _run(h, 'setVolume', {'volume': 7});
      expect(h.container.read(volumeProvider), 1.0);
    });

    testWidgets('a delta moves from the current level', (tester) async {
      final player = _FakePort();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'setVolume', {'volume': 0.5});
      await _run(h, 'setVolume', {'delta': 0.1});
      expect(h.container.read(volumeProvider), closeTo(0.6, 0.0001));

      await _run(h, 'setVolume', {'delta': double.nan});
      expect(h.container.read(volumeProvider), closeTo(0.6, 0.0001),
          reason: 'a non-finite value must not move the level');
    });
  });

  group('like', () {
    testWidgets('toggles the active track', (tester) async {
      final saved = _RecordingSavedTracks();
      final player = _FakePort();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(player),
        metadataPluginSavedTracksProvider.overrideWith(() => saved),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: true,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: [_track('a')],
          )),
        ),
      ]);

      await _run(h, 'like');
      expect(saved.toggled, ['a']);
    });

    testWidgets('an empty queue likes nothing', (tester) async {
      final saved = _RecordingSavedTracks();
      final h = await _harness(tester, [
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
        metadataPluginSavedTracksProvider.overrideWith(() => saved),
        audioPlayerProvider.overrideWith(
          () => _StubPlayer(AudioPlayerState(
            playing: false,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
          )),
        ),
      ]);

      await _run(h, 'like');
      expect(saved.toggled, isEmpty);
    });
  });
}
