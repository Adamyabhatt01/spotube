// The HEAD preflight and the stream GET both walk the source cascade when the
// primary URL is dead, seconds apart and for the same track. Before the memo,
// "one track failed" meant two full cascades — two searches per candidate and
// two manifest fetches. These tests count cascade work, which is the only way
// to see the second one is gone.
//
// Hermetic: every candidate is served one fake audio-source plugin, so no Hetu
// VM, no CLI and no network. `matchesCalls` is the cascade's unit of work.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/routes/playback.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/audio_source.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

import 'support/common_fakes.dart';

final _refProbe = Provider<Ref>((ref) => ref);

class _StubPluginNotifier extends MetadataPluginNotifier {
  _StubPluginNotifier(this.stubState);

  final MetadataPluginState stubState;

  @override
  Future<MetadataPluginState> build() async => stubState;
}

/// Counts how many searches the cascade ran. Answers one match every time, so
/// each candidate reached costs exactly one counted search.
class _StubAudioSource implements MetadataPluginAudioSourceEndpoint {
  int matchesCalls = 0;

  @override
  List<SpotubeAudioSourceContainerPreset> get supportedPresets => const [];

  @override
  Future<List<SpotubeAudioSourceMatchObject>> matches(
    SpotubeFullTrackObject track,
  ) async {
    matchesCalls++;
    return [
      SpotubeAudioSourceMatchObject(
        id: 'KENf509XTjI',
        title: 'Wassup',
        artists: const ['Flawed'],
        duration: const Duration(seconds: 274),
        externalUri: 'https://www.youtube.com/watch?v=KENf509XTjI',
      ),
    ];
  }

  @override
  Future<List<SpotubeAudioSourceStreamObject>> streams(
    SpotubeAudioSourceMatchObject match,
  ) async {
    return const [];
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

/// Hands every candidate the one fake plugin, so no candidate builds a VM.
class _StubPluginCache extends PluginVmCache<MetadataPlugin> {
  _StubPluginCache(this.plugin);

  final MetadataPlugin plugin;

  @override
  Future<MetadataPlugin> getOrCreate(
    String key,
    Future<MetadataPlugin> Function() factory,
  ) async =>
      plugin;
}

PluginConfiguration _plugin(String name) {
  return PluginConfiguration(
    name: name,
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

SpotubeAudioSourceStreamObject _stream(String url) {
  return SpotubeAudioSourceStreamObject(
    url: url,
    container: 'webm',
    type: SpotubeMediaCompressionType.lossy,
    bitrate: 128000.0,
  );
}

void main() {
  setUpAll(() {
    AppLogger.initialize(false);
    // The presets notifier reads SharedPreferences as soon as it sees a plugin.
    SharedPreferences.setMockInitialValues({});
  });

  late ProviderContainer container;
  late Ref ref;
  late _StubAudioSource source;
  late PluginConfiguration audioSource;

  setUp(() async {
    audioSource = _plugin('YouTube Audio');
    source = _StubAudioSource();
    container = ProviderContainer(
      overrides: [
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(
            PreferencesTable.defaults().copyWith(
              youtubeClientEngine: YoutubeClientEngine.newPipe,
            ),
          ),
        ),
        metadataPluginsProvider.overrideWith(
          () => _StubPluginNotifier(
            MetadataPluginState(
              plugins: [audioSource],
              defaultAudioSourcePlugin: 0,
            ),
          ),
        ),
        // The default candidate reuses this instance instead of building a VM,
        // and it is what `audioSourcePresetsProvider` reads on startup - null
        // here would make that initialization throw.
        audioSourcePluginProvider.overrideWith(
          (ref) async => _StubPlugin(source),
        ),
        pluginCacheProvider.overrideWithValue(_StubPluginCache(
          _StubPlugin(source),
        )),
        _refProbe,
      ],
    );
    addTearDown(container.dispose);

    ref = container.read(_refProbe);
  });

  /// A track whose primary URL is the given one; the cascade's candidates are
  /// resolved separately and never reach the network here.
  SourcedTrack trackWithUrl(String url) {
    return SourcedTrack(
      deps: ref.sourceDeps,
      info: SpotubeAudioSourceMatchObject(
        id: 'KENf509XTjI',
        title: 'Wassup',
        artists: const ['Flawed'],
        duration: const Duration(seconds: 274),
        externalUri: 'https://www.youtube.com/watch?v=KENf509XTjI',
      ),
      query: _track(),
      source: audioSource.slug,
      siblings: const [],
      sources: [_stream(url)],
      sourceCandidateKey: null,
    );
  }

  test('one cascade per track start, not one per handler', () async {
    final routes = ServerPlaybackRoutes(ref);
    final track = trackWithUrl('https://example.test/dead.webm');

    final first = await routes.fallbackUrlsFor(track);
    final afterHead = source.matchesCalls;
    expect(afterHead, greaterThan(0), reason: 'the first walk must do work');

    final second = await routes.fallbackUrlsFor(track);

    expect(source.matchesCalls, afterHead, reason: 'no second cascade');
    expect(second, same(first));
  });

  test('a re-signed primary URL misses the memo', () async {
    final routes = ServerPlaybackRoutes(ref);

    await routes.fallbackUrlsFor(trackWithUrl('https://example.test/a.webm'));
    final afterFirst = source.matchesCalls;
    await routes.fallbackUrlsFor(trackWithUrl('https://example.test/b.webm'));

    expect(
      source.matchesCalls,
      greaterThan(afterFirst),
      reason:
          'a list resolved against a dead URL must not answer for a new one',
    );
  });

  test('the memo does not outlive its window', () async {
    final routes = ServerPlaybackRoutes(ref);
    final track = trackWithUrl('https://example.test/dead.webm');

    await routes.fallbackUrlsFor(track);
    final afterFirst = source.matchesCalls;

    // Real time, because `DateTime.now()` is what decides expiry here. Costs
    // the window plus a second and nothing more.
    await Future.delayed(
      ServerPlaybackRoutes.fallbackUrlsReuseWindow + const Duration(seconds: 1),
    );
    await routes.fallbackUrlsFor(track);

    expect(
      source.matchesCalls,
      greaterThan(afterFirst),
      reason: 'a stale list is re-resolved, not served forever',
    );
  });
}
