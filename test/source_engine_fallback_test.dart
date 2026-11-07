// The source cascade behind a "not found": which candidates get tried, and
// what a failure means.
//
// Regression this guards: playback used to resolve on the configured engine
// only. `playbackFallbackUrls` widens across engines and plugins, but it can
// only reroute a URL that already exists, and only the download worker walked
// the cascade — so a track visible to some other backend was simply not
// playable. `resolveFirstAvailable` is now that widening, and its failure
// taxonomy matters as much as its ordering: an engine that could not answer
// must never be recorded as "this track does not exist".
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/metadata/endpoints/audio_source.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/exceptions.dart';
import 'package:spotube/services/sourced_track/source_dependencies.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_explode_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';

class _StubPrefsNotifier extends UserPreferencesNotifier {
  _StubPrefsNotifier(this.stub);

  final PreferencesTableData stub;

  @override
  PreferencesTableData build() => stub;
}

class _StubPluginNotifier extends MetadataPluginNotifier {
  _StubPluginNotifier(this.stubState);

  final MetadataPluginState stubState;

  @override
  Future<MetadataPluginState> build() async => stubState;
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

SourcedTrack _resolved(
  SourceDependencies deps,
  SpotubeAudioSourceMatchObject match,
) {
  return SourcedTrack(
    deps: deps,
    info: match,
    query: _track(),
    source: 'youtube-audio',
    siblings: const [],
    sources: const [],
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

SourceCandidate _candidate(PluginConfiguration config, YouTubeEngine engine) {
  return SourceCandidate(config, engine);
}

/// Stands in for the Hetu-backed audio source so `resolve` can be driven
/// without a VM. Counts calls so a test can assert a candidate was reached.
class _StubAudioSource implements MetadataPluginAudioSourceEndpoint {
  final List<SpotubeAudioSourceMatchObject> matchesResult;
  final List<SpotubeAudioSourceStreamObject> streamsResult = const [];

  int matchesCalls = 0;
  int streamsCalls = 0;

  _StubAudioSource({this.matchesResult = const []});

  @override
  Future<List<SpotubeAudioSourceMatchObject>> matches(
    SpotubeFullTrackObject track,
  ) async {
    matchesCalls++;
    return matchesResult;
  }

  @override
  Future<List<SpotubeAudioSourceStreamObject>> streams(
    SpotubeAudioSourceMatchObject match,
  ) async {
    streamsCalls++;
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

/// Hands every candidate the one fake plugin, so `_pluginFor` never builds a VM.
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

ProviderContainer _container({
  required YoutubeClientEngine engine,
  List<String> sourcePriority = const [],
  List<PluginConfiguration> plugins = const [],
  int defaultAudioSourcePlugin = -1,
  MetadataPlugin? audioSourcePlugin,
}) {
  return ProviderContainer(
    overrides: [
      userPreferencesProvider.overrideWith(
        () => _StubPrefsNotifier(
          PreferencesTable.defaults().copyWith(
            youtubeClientEngine: engine,
            sourcePriority: sourcePriority,
          ),
        ),
      ),
      metadataPluginsProvider.overrideWith(
        () => _StubPluginNotifier(
          MetadataPluginState(
            plugins: plugins,
            defaultAudioSourcePlugin: defaultAudioSourcePlugin,
          ),
        ),
      ),
      if (audioSourcePlugin != null)
        pluginCacheProvider
            .overrideWithValue(_StubPluginCache(audioSourcePlugin)),
    ],
  );
}

void main() {
  final audioSource = _plugin('YouTube Audio');

  group('engineFallbackCandidates', () {
    test('widens to the other engines and keeps the plugin fixed', () async {
      final container = _container(
        engine: YoutubeClientEngine.newPipe,
        plugins: [audioSource],
        defaultAudioSourcePlugin: 0,
      );
      addTearDown(container.dispose);

      final candidates =
          await SourceResolver(container.read(sourceDependenciesProvider))
              .engineFallbackCandidates(
        pluginSlug: audioSource.slug,
        skipEngine: YoutubeClientEngine.newPipe,
      );

      final engines = candidates.map((c) => c.engine.runtimeType).toList();

      // ytdlpFlutter is excluded: its manifest is always empty, so it can
      // never resolve a source (see SourceResolver._orderedEngineModes).
      expect(engines, [YtDlpEngine, YouTubeExplodeEngine]);
      expect(
        candidates.map((candidate) => candidate.config.slug).toSet(),
        {audioSource.slug},
      );
    });

    test('follows the configured source priority', () async {
      final container = _container(
        engine: YoutubeClientEngine.newPipe,
        sourcePriority: ['YouTubeExplode', 'yt-dlp'],
        plugins: [audioSource],
        defaultAudioSourcePlugin: 0,
      );
      addTearDown(container.dispose);

      final candidates =
          await SourceResolver(container.read(sourceDependenciesProvider))
              .engineFallbackCandidates(
        pluginSlug: audioSource.slug,
        skipEngine: YoutubeClientEngine.newPipe,
      );

      expect(
        candidates.map((candidate) => candidate.engine.runtimeType),
        [YouTubeExplodeEngine, YtDlpEngine],
      );
    });

    test('offers nothing when the plugin is not installed', () async {
      final container = _container(engine: YoutubeClientEngine.newPipe);
      addTearDown(container.dispose);

      final candidates =
          await SourceResolver(container.read(sourceDependenciesProvider))
              .engineFallbackCandidates(
        pluginSlug: audioSource.slug,
        skipEngine: YoutubeClientEngine.newPipe,
      );

      expect(candidates, isEmpty);
    });
  });

  group('resolveFirstAvailable', () {
    late SourceDependencies deps;
    late SourceResolver resolver;
    final track = _track();

    setUp(() {
      final container = _container(engine: YoutubeClientEngine.newPipe);
      addTearDown(container.dispose);
      deps = container.read(sourceDependenciesProvider);
      resolver = SourceResolver(deps);
    });

    Future<SourcedTrack> run(
      List<SourceCandidate> candidates,
      Future<SourcedTrack> Function(
        SourceCandidate,
        SpotubeFullTrackObject,
      ) attempt,
    ) {
      return resolver.resolveFirstAvailable(
        track,
        candidates: candidates,
        attempt: attempt,
      );
    }

    test('takes the first engine that finds the track and stops there',
        () async {
      final tried = <String>[];
      final candidates = [
        _candidate(audioSource, NewPipeEngine()),
        _candidate(audioSource, YtDlpEngine()),
        _candidate(audioSource, YouTubeExplodeEngine()),
      ];

      final resolved = await run(candidates, (candidate, _) async {
        tried.add(candidate.engine.runtimeType.toString());
        if (candidate.engine is YtDlpEngine) {
          return _resolved(deps, _match('KENf509XTjI'));
        }
        throw TrackNotFoundError(track);
      });

      expect(tried, ['NewPipeEngine', 'YtDlpEngine']);
      expect(resolved.info.id, 'KENf509XTjI');
    });

    test('an engine that cannot answer is not a miss', () async {
      final blocked = Exception('429 rate limited');

      await expectLater(
        run(
          [_candidate(audioSource, NewPipeEngine())],
          (_, __) async => throw blocked,
        ),
        throwsA(same(blocked)),
      );
    });

    test('a broken engine cannot become a tombstone for the whole cascade',
        () async {
      final blocked = Exception('NewPipeCLI crashed');

      await expectLater(
        run(
          [
            _candidate(audioSource, NewPipeEngine()),
            _candidate(audioSource, YtDlpEngine()),
          ],
          (candidate, _) async {
            if (candidate.engine is NewPipeEngine) throw blocked;
            throw TrackNotFoundError(track);
          },
        ),
        throwsA(same(blocked)),
      );
    });

    test('recovers when a later engine answers after one broke', () async {
      final resolved = await run(
        [
          _candidate(audioSource, NewPipeEngine()),
          _candidate(audioSource, YtDlpEngine()),
        ],
        (candidate, _) async {
          if (candidate.engine is NewPipeEngine) {
            throw Exception('transient');
          }
          return _resolved(deps, _match('sKHv6S1y_j0'));
        },
      );

      expect(resolved.info.id, 'sKHv6S1y_j0');
    });

    test('every engine answering empty is the real miss', () async {
      await expectLater(
        run(
          [
            _candidate(audioSource, NewPipeEngine()),
            _candidate(audioSource, YtDlpEngine()),
          ],
          (_, __) async => throw TrackNotFoundError(track),
        ),
        throwsA(isA<TrackNotFoundError>()),
      );
    });

    // yt-dlp is offered on Android too (the app may exec a binary it can
    // reach), so a candidate whose binary is simply not there has to be a
    // skip: it must not become the reported reason, and it must not stop
    // the next candidate from answering.
    test('an engine whose binary is missing is skipped, not reported',
        () async {
      await expectLater(
        run(
          [
            _candidate(audioSource, YtDlpEngine()),
            _candidate(audioSource, NewPipeEngine()),
          ],
          (candidate, _) async {
            if (candidate.engine is YtDlpEngine) {
              throw YtDlpNotInstalledError();
            }
            throw TrackNotFoundError(track);
          },
        ),
        throwsA(isA<TrackNotFoundError>()),
      );
    });

    test('a later engine still answers after one had no binary', () async {
      final resolved = await run(
        [
          _candidate(audioSource, YtDlpEngine()),
          _candidate(audioSource, NewPipeEngine()),
        ],
        (candidate, _) async {
          if (candidate.engine is YtDlpEngine) {
            throw YtDlpNotInstalledError();
          }
          return _resolved(deps, _match('sKHv6S1y_j0'));
        },
      );

      expect(resolved.info.id, 'sKHv6S1y_j0');
    });

    test('nothing to try is reported as a miss, not a crash', () async {
      await expectLater(
        run(const [], (_, __) async => _resolved(deps, _match('x'))),
        throwsA(isA<TrackNotFoundError>()),
      );
    });

    // Timing is virtual (fake_async), so these assert against
    // [sourceCandidateBudget] itself rather than a shortened copy of it.
    test('a hung candidate is timed out and the next candidate is tried', () {
      fakeAsync((async) {
        final tried = <String>[];
        SourcedTrack? resolved;
        Object? error;

        resolver.resolveFirstAvailable(
          track,
          candidates: [
            _candidate(audioSource, NewPipeEngine()),
            _candidate(audioSource, YtDlpEngine()),
          ],
          attempt: (candidate, _) async {
            tried.add(candidate.engine.runtimeType.toString());
            if (candidate.engine is NewPipeEngine) {
              // A CLI that started and never answered: no exception, no
              // completion. This is what an untimed `Process.run` looks
              // like.
              return Completer<SourcedTrack>().future;
            }
            return _resolved(deps, _match('sKHv6S1y_j0'));
          },
        ).then<void>(
          (value) => resolved = value,
          onError: (Object e) => error = e,
        );

        async.elapse(sourceCandidateBudget + const Duration(seconds: 1));

        expect(error, isNull);
        expect(resolved?.info.id, 'sKHv6S1y_j0');
        expect(tried, ['NewPipeEngine', 'YtDlpEngine']);
      });
    });

    test('a timeout is never cached as a miss', () {
      fakeAsync((async) {
        Object? error;

        // One candidate hangs, the next truthfully answers "no such track".
        resolver.resolveFirstAvailable(
          track,
          candidates: [
            _candidate(audioSource, NewPipeEngine()),
            _candidate(audioSource, YtDlpEngine()),
          ],
          attempt: (candidate, _) async {
            if (candidate.engine is NewPipeEngine) {
              return Completer<SourcedTrack>().future;
            }
            throw TrackNotFoundError(track);
          },
        ).then<void>(
          (_) => null,
          onError: (Object e) => error = e,
        );

        async.elapse(sourceCandidateBudget + const Duration(seconds: 1));

        // A caller writes a 6h tombstone only on TrackNotFoundError, so the
        // type of this failure is the whole assertion: a stalled backend must
        // not be reported as an absence.
        expect(error, isA<TimeoutException>());
        expect(
          error.toString(),
          contains('NewPipeEngine'),
          reason: 'the hung candidate should be named',
        );
      });
    });
  });

  // The shape production actually uses. Every other test in this group passes
  // `attempt`, which is why a crash on the `attempt == null` path — the only
  // path `SourcedTrack.fetchFromTrack` takes — survived 451 green tests.
  group('resolveFirstAvailable without attempt (production shape)', () {
    // A candidate that is not the primary, so `_pluginFor` goes through the
    // provider cache instead of `audioSourcePluginProvider`.
    final nonPrimary = _candidate(audioSource, YtDlpEngine());

    test('a plugin that finds nothing yields TrackNotFoundError, not a crash',
        () async {
      final source = _StubAudioSource();
      final container = _container(
        engine: YoutubeClientEngine.newPipe,
        plugins: [audioSource],
        defaultAudioSourcePlugin: 0,
        audioSourcePlugin: _StubPlugin(source),
      );
      addTearDown(container.dispose);

      await expectLater(
        SourceResolver(container.read(sourceDependenciesProvider))
            .resolveFirstAvailable(_track(), candidates: [nonPrimary]),
        throwsA(isA<TrackNotFoundError>()),
      );

      expect(
        source.matchesCalls,
        1,
        reason: 'the candidate was never reached: the call itself blew up',
      );
    });

    test('a plugin that matches resolves to a SourcedTrack', () async {
      final source = _StubAudioSource(matchesResult: [_match('KENf509XTjI')]);
      final container = _container(
        engine: YoutubeClientEngine.newPipe,
        plugins: [audioSource],
        defaultAudioSourcePlugin: 0,
        audioSourcePlugin: _StubPlugin(source),
      );
      addTearDown(container.dispose);

      final resolved =
          await SourceResolver(container.read(sourceDependenciesProvider))
              .resolveFirstAvailable(_track(), candidates: [nonPrimary]);

      expect(resolved.info.id, 'KENf509XTjI');
      expect(source.matchesCalls, greaterThan(0));
      expect(source.streamsCalls, 1);
    });

    test('resolve still satisfies the attempt signature', () {
      // Pins the contract the crash violated: if `resolve` and
      // `SourceResolutionAttempt` ever drift on arity again, passing the
      // tear-off below stops compiling instead of degrading into a dynamic
      // call that only fails at runtime.
      final container = _container(engine: YoutubeClientEngine.newPipe);
      addTearDown(container.dispose);

      _acceptsSourceResolutionAttempt(
        SourceResolver(container.read(sourceDependenciesProvider)).resolve,
      );
    });
  });
}

/// Compile-time check only; the body never runs in the test that calls it.
void _acceptsSourceResolutionAttempt(SourceResolutionAttempt _) {}
