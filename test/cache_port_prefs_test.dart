// PR C: cache bound, server rebind and preference-diffing contracts.
//
// Covered:
//  - retainedSourcedTracks: active + next-up selection (empty, edges,
//    local tracks skipped, out-of-range safe).
//  - Family lifecycle on the real autoDispose family (hetu-free: the
//    audio-source stub throws, so instances sit in error state —
//    retention mechanics are state-agnostic):
//      one-shot resolution is transient (evicted);
//      retention holds active + next;
//      releasing retention evicts;
//      re-resolution works after eviction (fetch re-attempted).
//  - Server close-before-rebind over real loopback sockets: normal port
//    change, rapid double change, old port refused, no bind race.
//  - preferencesSideEffects: each flag independently, neither on
//    unrelated writes.
//
// Hermetic except loopback sockets (VM tests have dart:io).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';

SpotubeFullTrackObject _testTrack(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: const [],
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

SpotubeLocalTrackObject _localTrack(String id) {
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Local $id',
    externalUri: 'file:///music/$id.mp3',
    album: SpotubeSimpleAlbumObject(
      id: 'album-local',
      name: 'Local Album',
      externalUri: 'https://example.test/album/local',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    artists: const [],
    durationMs: 1000,
    path: '/music/$id.mp3',
  );
}

class _StubAudioPlayerNotifier extends AudioPlayerNotifier {
  AudioPlayerState stub;

  _StubAudioPlayerNotifier(this.stub);

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

AudioPlayerState _playerState(
  List<SpotubeTrackObject> tracks, {
  int currentIndex = 0,
}) {
  return AudioPlayerState(
    playing: false,
    loopMode: PlaylistMode.none,
    shuffled: false,
    collections: const [],
    currentIndex: currentIndex,
    tracks: tracks,
  );
}

class _StubPrefsNotifier extends UserPreferencesNotifier {
  PreferencesTableData stub;

  _StubPrefsNotifier(this.stub);

  @override
  PreferencesTableData build() => stub;

  void setPort(int port) {
    stub = stub.copyWith(connectPort: port);
    state = stub;
  }
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _portOpen(int port) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 2),
    );
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('retainedSourcedTracks', () {
    test('empty and out-of-range queues retain nothing', () {
      expect(retainedSourcedTracks(tracks: const [], currentIndex: 0),
          isEmpty);
      expect(
        retainedSourcedTracks(
          tracks: [_testTrack('a')],
          currentIndex: 5,
        ),
        isEmpty,
      );
    });

    test('middle keeps active + next', () {
      final tracks = [_testTrack('a'), _testTrack('b'), _testTrack('c')];
      expect(
        retainedSourcedTracks(tracks: tracks, currentIndex: 1)
            .map((t) => t.id),
        ['b', 'c'],
      );
    });

    test('last track keeps only itself', () {
      final tracks = [_testTrack('a'), _testTrack('b')];
      expect(
        retainedSourcedTracks(tracks: tracks, currentIndex: 1)
            .map((t) => t.id),
        ['b'],
      );
    });

    test('local tracks never retained (family is Full-only)', () {
      final tracks = <SpotubeTrackObject>[
        _localTrack('l1'),
        _testTrack('a'),
        _localTrack('l2'),
      ];
      // Active is local, next is full: only the full one is retained.
      expect(
        retainedSourcedTracks(tracks: tracks, currentIndex: 0)
            .map((t) => t.id),
        ['a'],
      );
      // Active full at end: only itself.
      expect(
        retainedSourcedTracks(tracks: tracks, currentIndex: 1)
            .map((t) => t.id),
        ['a'],
      );
    });
  });

  group('sourcedTrack family lifecycle', () {
    late ProviderContainer container;
    late _StubAudioPlayerNotifier audioStub;
    late int fetchAttempts;

    setUp(() {
      fetchAttempts = 0;
      audioStub = _StubAudioPlayerNotifier(
        _playerState([_testTrack('a'), _testTrack('b'), _testTrack('c')]),
      );
      container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWith(() => audioStub),
          audioSourcePluginProvider.overrideWith((ref) async {
            fetchAttempts++;
            throw StateError('no backend headless');
          }),
        ],
      );
    });

    tearDown(() => container.dispose());

    bool hasInstance(SpotubeFullTrackObject track) {
      return container.getAllProviderElements().any(
            (e) => e.provider == sourcedTrackProvider(track),
          );
    }

    Future<void> settle() async {
      // Lets autoDispose process unlistened instances (framework
      // quiescence, not code timing).
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    test('transient resolves evict; retention holds active+next; re-resolves',
        () async {
      final trackA = _testTrack('a');
      final trackB = _testTrack('b');
      final trackC = _testTrack('c');

      // One-shot resolution with no listeners: transient, evicted after.
      await expectLater(
        container.read(sourcedTrackProvider(trackA).future),
        throwsStateError,
      );
      expect(fetchAttempts, 1);
      await settle();
      expect(hasInstance(trackA), isFalse);

      // Retention holds active (a) + next (b). A one-shot read of c
      // resolves transiently and is evicted again: the bound holds.
      final retentionSub =
          container.listen(sourcedTrackRetentionProvider, (_, __) {});
      await expectLater(
        container.read(sourcedTrackProvider(trackC).future),
        throwsStateError,
      );
      await settle();
      expect(hasInstance(trackA), isTrue);
      expect(hasInstance(trackB), isTrue);
      expect(hasInstance(trackC), isFalse);

      // Advancing the queue releases a, retains b + c (c resolves now).
      audioStub.emit(_playerState([trackA, trackB, trackC], currentIndex: 1));
      await settle();
      expect(hasInstance(trackA), isFalse);
      expect(hasInstance(trackB), isTrue);
      expect(hasInstance(trackC), isTrue);

      // Releasing retention evicts everything; re-resolution works after
      // (the fetch body re-executes instead of serving a stale instance).
      retentionSub.close();
      await settle();
      expect(hasInstance(trackB), isFalse);
      await expectLater(
        container.read(sourcedTrackProvider(trackB).future),
        throwsStateError,
      );
      // Transient again: evicted once unlistened.
      await settle();
      expect(hasInstance(trackB), isFalse);
    });
  });

  group('server close-before-rebind', () {
    late ProviderContainer container;
    late _StubPrefsNotifier prefs;

    setUp(() {
      prefs = _StubPrefsNotifier(
        PreferencesTable.defaults()
            .copyWith(enableConnect: false, connectPort: 0),
      );
      container = ProviderContainer(
        overrides: [
          userPreferencesProvider.overrideWith(() => prefs),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      SpotubeMedia.serverPort = 0;
    });

    test('port change rebinds, old port refused', () async {
      final portA = await _freePort();
      prefs.stub = prefs.stub.copyWith(connectPort: portA);
      container.read(userPreferencesProvider);
      final first = await container.read(serverProvider.future);
      expect(await _portOpen(first.port), isTrue);

      final portB = await _freePort();
      prefs.setPort(portB);
      final second = await container.read(serverProvider.future);
      expect(second.port, portB);
      expect(await _portOpen(portB), isTrue);
      // Old socket fully closed before the rebind: refused, not lingering.
      expect(await _portOpen(portA), isFalse);
    });

    test('rapid double change binds exactly once, no race', () async {
      prefs.stub = prefs.stub.copyWith(connectPort: await _freePort());
      container.read(userPreferencesProvider);
      final first = await container.read(serverProvider.future);

      prefs.setPort(await _freePort());
      prefs.setPort(await _freePort());
      final last = await container.read(serverProvider.future);

      expect(await _portOpen(last.port), isTrue);
      expect(await _portOpen(first.port), isFalse);
    });
  });

  group('preferencesSideEffects', () {
    PreferencesTableData base() => PreferencesTable.defaults();

    test('unrelated writes trigger neither native call', () {
      expect(
        preferencesSideEffects(
          previous: base(),
          next: base().copyWith(downloadLocation: 'elsewhere'),
        ),
        (titleBarStyle: false, audioNormalization: false),
      );
      expect(
        preferencesSideEffects(previous: base(), next: base()),
        (titleBarStyle: false, audioNormalization: false),
      );
    });

    test('each flag independently', () {
      expect(
        preferencesSideEffects(
          previous: base(),
          next: base().copyWith(systemTitleBar: !base().systemTitleBar),
        ),
        (titleBarStyle: true, audioNormalization: false),
      );
      expect(
        preferencesSideEffects(
          previous: base(),
          next: base().copyWith(normalizeAudio: !base().normalizeAudio),
        ),
        (titleBarStyle: false, audioNormalization: true),
      );
      expect(
        preferencesSideEffects(
          previous: base(),
          next: base().copyWith(
            systemTitleBar: !base().systemTitleBar,
            normalizeAudio: !base().normalizeAudio,
          ),
        ),
        (titleBarStyle: true, audioNormalization: true),
      );
    });
  });
}
