// A resolved track carries which candidate produced it, so the playback
// fallback cascade can skip re-trying the engine that just failed.
//
// Regression this guards: `SourceResolver` stamps `sourceCandidateKey` on every
// track it resolves, but the three rebuild paths — sibling fetch, sibling swap
// and stream refresh — each hand-assembled a new `SourcedTrack` and dropped it.
// `playbackFallbackUrls` reads `primary.sourceCandidateKey ?? ''` and skips the
// matching candidate, so a dropped key matched nothing: after any URL refresh it
// re-searched the candidate that had just failed and burned one of its three
// fallback slots doing it.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/audio_source.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

const kTestCandidateKey = 'youtube-audio@1.0.0:YtDlpEngine';

class _StubPrefsNotifier extends UserPreferencesNotifier {
  _StubPrefsNotifier();

  @override
  PreferencesTableData build() => PreferencesTable.defaults();
}

class _StubPluginNotifier extends MetadataPluginNotifier {
  _StubPluginNotifier(this.stubState);

  final MetadataPluginState stubState;

  @override
  Future<MetadataPluginState> build() async => stubState;
}

class _StubPresetsNotifier extends AudioSourceAvailableQualityPresetsNotifier {
  @override
  AudioSourcePresetsState build() => AudioSourcePresetsState();
}

class _StubAudioSource implements MetadataPluginAudioSourceEndpoint {
  _StubAudioSource(
      {this.matchesResult = const [], this.streamsResult = const []});

  final List<SpotubeAudioSourceMatchObject> matchesResult;
  final List<SpotubeAudioSourceStreamObject> streamsResult;

  @override
  Future<List<SpotubeAudioSourceMatchObject>> matches(
    SpotubeFullTrackObject track,
  ) async {
    return matchesResult;
  }

  @override
  Future<List<SpotubeAudioSourceStreamObject>> streams(
    SpotubeAudioSourceMatchObject match,
  ) async {
    return streamsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubPlugin implements MetadataPlugin {
  _StubPlugin(this.audioSource);

  @override
  final MetadataPluginAudioSourceEndpoint audioSource;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

PluginConfiguration _plugin() {
  return PluginConfiguration(
    name: 'YouTube Audio',
    description: 'test',
    version: '1.0.0',
    author: 'test',
    entryPoint: 'plugin.out',
    pluginApiVersion: '2.0.0',
    abilities: [PluginAbilities.audioSource],
  );
}

SpotubeFullTrackObject _track() {
  return SpotubeFullTrackObject(
    id: 't1',
    name: 'Wassup',
    externalUri: 'https://open.spotify.com/track/t1',
    artists: [
      SpotubeSimpleArtistObject(id: 'a1', name: 'Flawed', externalUri: ''),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'al1',
      name: 'Singles',
      externalUri: '',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 274000,
    isrc: '',
    explicit: false,
  );
}

SpotubeAudioSourceMatchObject _match(String id) {
  return SpotubeAudioSourceMatchObject(
    id: id,
    title: 'Wassup',
    artists: const ['Flawed'],
    duration: const Duration(seconds: 274),
    externalUri: 'https://www.youtube.com/watch?v=$id',
  );
}

void main() {
  late AppDatabase database;
  late HttpServer server;

  setUpAll(() async {
    AppLogger.initialize(false);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // `refreshStream` validates every candidate URL with a HEAD before it
    // returns; answer locally so no test reaches the network.
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close();
    await database.close();
  });

  SourcedTrack sourced(
    Ref ref, {
    required List<SpotubeAudioSourceStreamObject> sources,
    List<SpotubeAudioSourceMatchObject> siblings = const [],
    String id = 'orig123',
  }) {
    return SourcedTrack(
      deps: ref.sourceDeps,
      info: _match(id),
      query: _track(),
      source: 'youtube-audio',
      sources: sources,
      siblings: siblings,
      sourceCandidateKey: kTestCandidateKey,
    );
  }

  ProviderContainer containerWith(MetadataPlugin plugin) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        userPreferencesProvider.overrideWith(() => _StubPrefsNotifier()),
        audioSourcePluginProvider.overrideWith((ref) async => plugin),
        audioSourcePresetsProvider.overrideWith(() => _StubPresetsNotifier()),
        metadataPluginsProvider.overrideWith(
          () => _StubPluginNotifier(
            MetadataPluginState(
              plugins: [_plugin()],
              defaultAudioSourcePlugin: 0,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  SpotubeAudioSourceStreamObject streamAt(String path) {
    return SpotubeAudioSourceStreamObject(
      url: 'http://127.0.0.1:${server.port}$path',
      container: 'webm',
      type: SpotubeMediaCompressionType.lossy,
    );
  }

  group('sourceCandidateKey survives rebuild', () {
    test('copyWithSibling keeps the key of the candidate it came from',
        () async {
      final plugin = _StubPlugin(
        _StubAudioSource(
            matchesResult: [_match('orig123'), _match('other456')]),
      );
      final container = containerWith(plugin);
      final ref = container.read(_refProbe);

      final result =
          await sourced(ref, sources: [streamAt('/a')]).copyWithSibling();

      expect(result.sourceCandidateKey, kTestCandidateKey);
    });

    test('swapWithSibling keeps the key across the manifest re-fetch',
        () async {
      final plugin = _StubPlugin(
        _StubAudioSource(streamsResult: [streamAt('/b')]),
      );
      final container = containerWith(plugin);
      final ref = container.read(_refProbe);

      final result = await sourced(
        ref,
        sources: [streamAt('/a')],
        siblings: [_match('other456')],
      ).swapWithSibling(_match('other456'));

      expect(result?.sourceCandidateKey, kTestCandidateKey);
    });

    test('refreshStream keeps the key after re-validating the URLs', () async {
      final plugin = _StubPlugin(
        _StubAudioSource(streamsResult: [streamAt('/c')]),
      );
      final container = containerWith(plugin);
      final ref = container.read(_refProbe);

      final result = await sourced(
        ref,
        sources: [streamAt('/a')],
      ).refreshStream();

      expect(result.sourceCandidateKey, kTestCandidateKey);
    });
  });
}

final _refProbe = Provider<Ref>((ref) => ref);
