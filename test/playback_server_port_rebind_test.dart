// Queue URIs embed the playback-server port at `SpotubeMedia` construction
// (`uriFor` reads the static). A rebind that moves the port — a connectPort
// edit, or the remembered random port losing to another process — used to
// leave every remote track in the backend playlist pointing at a dead
// socket until the user reloaded the queue.
// `playbackServerPortRebindProvider` now watches for a *changed* port
// report and calls `rebindQueueMedia()`, which re-opens the playlist with
// fresh URIs, preserving order, index and play state.
//
// The subscription lives in `playbackServerPortRebindProvider`, outside the
// notifier's build graph — subscribing inside `build` closed a provider
// cycle through the server routes (see the provider's doc comment). The
// test activates that provider on the same container.

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart' as port;
import 'package:spotube/services/sourced_track/sourced_track.dart';

import 'support/common_fakes.dart';

/// Records backend playlist opens; the port-change rebuild goes through
/// [openPlaylistOnBackend], so each call is one queue (re)build.
class _RecordingPlayerNotifier extends AudioPlayerNotifier {
  final List<SpotubeMedia> openedMedias = [];
  final List<int> openedIndexes = [];
  int openCount = 0;

  void seedQueue(List<SpotubeTrackObject> tracks, int index) {
    state = state.copyWith(tracks: tracks, currentIndex: index);
  }

  @override
  AudioPlayerState build() {
    return AudioPlayerState(
      playing: true,
      loopMode: PlaylistMode.none,
      shuffled: false,
      collections: const [],
      tracks: const [],
    );
  }

  @override
  List<Media> get backendMedias => const [];

  @override
  int get backendCurrentIndex => 0;

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {}

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {}

  @override
  Future<void> removeMediaFromBackend(int index) async {}

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {
    openCount++;
    openedMedias
      ..clear()
      ..addAll(medias);
    openedIndexes.add(initialIndex);
  }
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

/// `load` warms the intended track's source without awaiting it; park it.
class _HangingSourcedTrackNotifier extends SourcedTrackNotifier {
  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) =>
      Completer<SourcedTrack>().future;
}

/// The rebind path asks the port for position/seek; everything else falls
/// through [noSuchMethod] like the other port fakes.
class _StubBackendPort implements port.AudioPlayerPort {
  final Duration _position = const Duration(seconds: 42);
  final List<Duration> seeks = <Duration>[];

  @override
  Duration get position => _position;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: const [],
    album: SpotubeSimpleAlbumObject(
      id: 'album-$id',
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST$id',
    explicit: false,
  );
}

void main() {
  late AppDatabase database;
  late _RecordingPlayerNotifier player;
  late _StubBackendPort backendPort;
  late ProviderContainer container;
  late StateController<int> portSignal;

  const firstPort = 41001;
  const secondPort = 42002;

  setUp(() async {
    SpotubeMedia.serverPort = firstPort;
    database = AppDatabase.forTesting(NativeDatabase.memory());
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
    player = _RecordingPlayerNotifier();
    backendPort = _StubBackendPort();
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    SpotubeMedia.serverPort = 0;
  });

  void makeContainer() {
    final portState = StateProvider<int>((ref) => firstPort);
    container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => player),
        audioPlayerPortProvider.overrideWithValue(backendPort),
        databaseProvider.overrideWithValue(database),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        sourcedTrackProvider.overrideWith(() => _HangingSourcedTrackNotifier()),
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(PreferencesTable.defaults()),
        ),
        // The port report the listener consumes. Driven by a state
        // provider so the test can publish a *changed* port the way a
        // real rebind does.
        playbackServerPortProvider.overrideWith((ref) async {
          return ref.watch(portState);
        }),
      ],
    );
    portSignal = container.read(portState.notifier);
    container.read(audioPlayerProvider);
    // Activate the rebind watcher: it subscribes to the (overridden) port
    // provider and calls back into the notifier on a changed port.
    container.read(playbackServerPortRebindProvider);
  }

  test('a changed server port rebuilds queue URIs and restores position',
      () async {
    makeContainer();

    await player.load([_track('a'), _track('b')], autoPlay: true);
    expect(player.openCount, 1);
    expect(
      player.openedMedias.first.uri,
      contains(':$firstPort/stream/a'),
    );

    // The server rebinds on a different port: the static the URI builder
    // reads moves first, then the provider reports the new port — the same
    // order serverProvider produces in production.
    SpotubeMedia.serverPort = secondPort;
    portSignal.state = secondPort;
    await pumpEventQueue(times: 10);

    expect(player.openCount, 2, reason: 'the queue must be re-opened');
    expect(
      player.openedMedias.first.uri,
      contains(':$secondPort/stream/a'),
      reason: 'rebuilt URIs must embed the new port',
    );
    expect(
      player.openedMedias.map((m) => m.uri),
      everyElement(contains(':$secondPort/')),
    );
    expect(
      backendPort.seeks,
      [const Duration(seconds: 42)],
      reason: 'playback position is restored after the rebuild',
    );
  });

  test('a duplicate-URI queue keeps every entry and its current index',
      () async {
    makeContainer();
    await pumpEventQueue(times: 10);

    final a = _track('a');
    final b = _track('b');
    player.seedQueue([a, b, a], 2);

    SpotubeMedia.serverPort = secondPort;
    portSignal.state = secondPort;
    await pumpEventQueue(times: 10);

    expect(player.openCount, 1);
    expect(
      player.openedMedias,
      hasLength(3),
      reason: 'the duplicate queue entry must survive a transparent rebind',
    );
    expect(player.openedMedias[0].uri, contains(':$secondPort/stream/a'));
    expect(player.openedMedias[1].uri, contains(':$secondPort/stream/b'));
    expect(player.openedMedias[2].uri, contains(':$secondPort/stream/a'));
    expect(
      player.openedIndexes.single,
      2,
      reason: 'the current entry is still the second A, not the first B',
    );
  });

  test('an unchanged port report does not rebuild the queue', () async {
    makeContainer();

    await player.load([_track('a')], autoPlay: true);
    expect(player.openCount, 1);

    // A same-port re-emit (in-place rebuild keeps continuity) must not
    // touch the backend playlist.
    portSignal.state = firstPort;
    await pumpEventQueue(times: 10);

    expect(player.openCount, 1);
    expect(backendPort.seeks, isEmpty);
  });

  test('a local-only queue is not rebuilt on a port change', () async {
    makeContainer();

    final local = SpotubeLocalTrackObject(
      id: 'local-1',
      name: 'Local',
      externalUri: 'file:///music/local.mp3',
      album: SpotubeSimpleAlbumObject(
        id: 'album-local',
        name: 'Album',
        externalUri: 'https://example.test/album/local',
        artists: const [],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: 60000,
      path: '/music/local.mp3',
    );
    await player.load([local], autoPlay: true);
    expect(player.openCount, 1);

    SpotubeMedia.serverPort = secondPort;
    portSignal.state = secondPort;
    await pumpEventQueue(times: 10);

    expect(player.openCount, 1, reason: 'local files embed no port');
  });
}
