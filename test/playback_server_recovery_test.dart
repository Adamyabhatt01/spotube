// A failed playback-server bind must not disable playback for the session.
//
// Every remote `SpotubeMedia` URI embeds the local playback server's port, so
// `AudioPlayerNotifier.load` (and the queue-mutation paths) await
// `playbackServerPortProvider` before building media. A bind failure used to
// leave that provider cached in `AsyncError` forever: every later play path
// threw at the await before touching the queue, so the previous song kept
// playing and tapping another one looked dead. The notifier now drops the
// cached failure and rebuilds once; these tests pin both the retry and the
// next-tap recovery.

import 'dart:async';
import 'dart:io';

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
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

import 'support/common_fakes.dart';

/// Records the backend queue without media_kit. Mirrors the fake used by the
/// queue contract tests.
class _RecordingPlayerNotifier extends AudioPlayerNotifier {
  final List<String> backendCalls = [];
  List<Media> medias = const [];

  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        tracks: const [],
      );

  @override
  List<Media> get backendMedias => medias;

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
    backendCalls.add('open:$initialIndex:${medias.length}');
    this.medias = medias.map((m) => m.toMedia).toList();
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
  late HttpServer fakeServer;
  late int attempts;

  setUp(() async {
    SpotubeMedia.serverPort = 0;
    attempts = 0;
    fakeServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
  });

  tearDown(() async {
    await database.close();
    await fakeServer.close(force: true);
    SpotubeMedia.serverPort = 0;
  });

  ProviderContainer makeContainer({required int failFirst}) {
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWith(() => player),
        databaseProvider.overrideWithValue(database),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        sourcedTrackProvider.overrideWith(() => _HangingSourcedTrackNotifier()),
        userPreferencesProvider
            .overrideWith(() => StubPrefsNotifier(PreferencesTable.defaults())),
        // Fail the first [failFirst] binds, then answer with a real loopback
        // server so the success path is exercised end to end.
        serverProvider.overrideWith((ref) async {
          attempts++;
          if (attempts <= failFirst) {
            throw StateError('simulated bind failure');
          }
          SpotubeMedia.serverPort = fakeServer.port;
          return (server: fakeServer, port: fakeServer.port);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(audioPlayerProvider);
    return container;
  }

  test('one failed bind is retried and the queue still opens', () async {
    makeContainer(failFirst: 1);

    await player.load([_track('a')], autoPlay: true);

    expect(attempts, 2, reason: 'the cached failure must not be final');
    expect(player.backendCalls, ['open:0:1']);
    expect(player.state.tracks.map((t) => t.id), ['a']);
  });

  test('a failed load does not poison the next tap', () async {
    makeContainer(failFirst: 2);

    await expectLater(
      player.load([_track('a')], autoPlay: true),
      throwsStateError,
    );
    expect(player.backendCalls, isEmpty);
    expect(player.state.tracks, isEmpty);

    // The first tap exhausted its retry; a later tap must rebuild instead of
    // rethrowing the cached AsyncError forever.
    await player.load([_track('a')], autoPlay: true);

    expect(attempts, 3);
    expect(player.backendCalls, ['open:0:1']);
    expect(player.state.tracks.map((t) => t.id), ['a']);
  });
}
