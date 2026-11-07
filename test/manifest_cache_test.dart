// The manifest extraction cache: second serves of the same (track, source,
// match) skip re-extraction while every URL is unexpired, and nothing else.
// Misses (unknown key, expired horizon, unknown expiry, eviction) fall back
// to today's re-extract behavior.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/audio_source.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/manifest_cache.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/utils/stream_url_expiry.dart';

import 'support/common_fakes.dart';

const _track = 't1';
const _slug = 'youtube-audio';
const _match = 'v1';

String _url(int expireSeconds, String tag) =>
    'https://rr1.googlevideo.com/videoplayback?expire=$expireSeconds&id=$tag&itag=251';

List<SpotubeAudioSourceStreamObject> _sources(List<int> expires) {
  return [
    for (var i = 0; i < expires.length; i++)
      SpotubeAudioSourceStreamObject(
        url: _url(expires[i], 's$i'),
        container: 'webm',
        type: SpotubeMediaCompressionType.lossy,
        bitrate: 128000.0,
      ),
  ];
}

int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  setUpAll(() => AppLogger.initialize(false));

  late ManifestCache cache;
  late DateTime now;

  setUp(() {
    cache = ManifestCache(maxEntries: 4);
    now = DateTime.now();
  });

  List<SpotubeAudioSourceStreamObject>? lookup() => cache.lookup(
        trackId: _track,
        sourceSlug: _slug,
        matchId: _match,
        now: now,
      );

  void store(List<SpotubeAudioSourceStreamObject> sources) {
    // The production freshness rule, shared with the serving boundary:
    // unknown expiry never reaches the cache.
    final min = manifestMinExpireSeconds([for (final s in sources) s.url]);
    expect(min, isNotNull);
    cache.store(
      trackId: _track,
      sourceSlug: _slug,
      matchId: _match,
      sources: sources,
      minExpireSeconds: min!,
    );
  }

  test('unknown key misses', () {
    expect(lookup(), isNull);
  });

  test('freshly stored manifest hits with identical sources', () {
    final sources = _sources([_nowSeconds() + 3600, _nowSeconds() + 7200]);
    store(sources);

    final hit = lookup();
    expect(hit, isNotNull);
    expect(
      [for (final s in hit!) s.url],
      [for (final s in sources) s.url],
    );
  });

  test('expired horizon misses', () {
    final sources = _sources([_nowSeconds() + 3600]);
    store(sources);

    now = DateTime.now().add(const Duration(hours: 2));
    expect(lookup(), isNull,
        reason: 'strict expiry: at-or-past horizon is a miss');
  });

  test('expiry exactly at now misses (strictly-past semantics)', () {
    final at = _nowSeconds() + 5;
    store(_sources([at]));

    now = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    expect(lookup(), isNull);
  });

  test('key separates track, source and match', () {
    final sources = _sources([_nowSeconds() + 3600]);
    store(sources);

    List<SpotubeAudioSourceStreamObject>? other({
      String trackId = _track,
      String sourceSlug = _slug,
      String matchId = _match,
    }) =>
        cache.lookup(
          trackId: trackId,
          sourceSlug: sourceSlug,
          matchId: matchId,
          now: now,
        );

    expect(lookup(), isNotNull);
    expect(other(trackId: 't2'), isNull,
        reason: 'entries must not leak across tracks');
    expect(other(sourceSlug: 'other-engine'), isNull,
        reason: 'entries must not leak across engines');
    expect(other(matchId: 'v2'), isNull,
        reason: 'entries must not leak across matches');
  });

  test('empty source lists are never served', () {
    cache.store(
      trackId: _track,
      sourceSlug: _slug,
      matchId: _match,
      sources: const [],
      minExpireSeconds: _nowSeconds() + 3600,
    );
    expect(lookup(), isNull);
  });

  test('entries evict oldest-first at the cap', () {
    int exp() => _nowSeconds() + 3600;
    for (var i = 0; i < 4; i++) {
      cache.store(
        trackId: 't$i',
        sourceSlug: _slug,
        matchId: _match,
        sources: _sources([exp()]),
        minExpireSeconds: exp(),
      );
    }
    expect(cache.length, 4);

    cache.store(
      trackId: 't-new',
      sourceSlug: _slug,
      matchId: _match,
      sources: _sources([exp()]),
      minExpireSeconds: exp(),
    );
    expect(cache.length, 4);

    List<SpotubeAudioSourceStreamObject>? byTrack(String trackId) =>
        cache.lookup(
          trackId: trackId,
          sourceSlug: _slug,
          matchId: _match,
          now: now,
        );
    expect(byTrack('t0'), isNull, reason: 'oldest evicted');
    expect(byTrack('t-new'), isNotNull);
    expect(byTrack('t3'), isNotNull);
  });

  test('a hit refreshes LRU position', () {
    int exp() => _nowSeconds() + 3600;
    for (var i = 0; i < 4; i++) {
      cache.store(
        trackId: 't$i',
        sourceSlug: _slug,
        matchId: _match,
        sources: _sources([exp()]),
        minExpireSeconds: exp(),
      );
    }
    // Touch t0 so t1 becomes the eviction candidate.
    expect(
      cache.lookup(trackId: 't0', sourceSlug: _slug, matchId: _match, now: now),
      isNotNull,
    );

    cache.store(
      trackId: 't-new',
      sourceSlug: _slug,
      matchId: _match,
      sources: _sources([exp()]),
      minExpireSeconds: exp(),
    );

    List<SpotubeAudioSourceStreamObject>? byTrack(String trackId) =>
        cache.lookup(
          trackId: trackId,
          sourceSlug: _slug,
          matchId: _match,
          now: now,
        );
    expect(byTrack('t1'), isNull);
    expect(byTrack('t0'), isNotNull);
  });

  /// End-to-end proof through the real `fetchFromTrack` cache-hit path: with a
  /// seeded source-match row, two resolutions pay exactly one manifest
  /// extraction while URLs are unexpired, and unknown-expiry manifests keep
  /// re-extracting (today's behavior, preserved on purpose).
  group('fetchFromTrack extraction', () {
    late AppDatabase db;
    late ProviderContainer container;
    late _CountingAudioSource audioSource;
    late _StubConfigsNotifier configs;
    late SpotubeFullTrackObject track;

    const slug = 'test-audio';

    SpotubeFullTrackObject fullTrack(String id) {
      return SpotubeFullTrackObject(
        id: id,
        name: 'Track $id',
        externalUri: 'https://example.test/track/$id',
        artists: [
          SpotubeSimpleArtistObject(
            id: 'a1',
            name: 'Artist',
            externalUri: 'https://example.test/artist/a1',
          ),
        ],
        album: SpotubeSimpleAlbumObject(
          id: 'al1',
          name: 'Album',
          externalUri: 'https://example.test/album/al1',
          artists: const [],
          albumType: SpotubeAlbumType.album,
        ),
        durationMs: 180000,
        isrc: 'ISRC$id',
        explicit: false,
      );
    }

    SpotubeAudioSourceMatchObject matchOf(String id) {
      return SpotubeAudioSourceMatchObject(
        id: id,
        title: 'Track',
        artists: const ['Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/$id',
      );
    }

    List<SpotubeAudioSourceStreamObject> streamsWithExpire(int expire) {
      return [
        SpotubeAudioSourceStreamObject(
          url: _url(expire, 's0'),
          container: 'webm',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ];
    }

    Future<void> seedMatch(String trackId, String matchId) async {
      await db.into(db.sourceMatchTable).insert(
            SourceMatchTableCompanion.insert(
              trackId: trackId,
              sourceInfo: Value(jsonEncode(matchOf(matchId).toJson())),
              sourceType: slug,
            ),
          );
    }

    /// Drives one full resolution through the real provider and waits for it.
    Future<SourcedTrack> resolve(SpotubeFullTrackObject query) async {
      // `sourcedTrackProvider` watches the plugin provider. Resolving while it
      // is still loading restarts the build once the plugin arrives, which adds
      // an extraction unrelated to what these tests count. Warm it first.
      await container.read(audioSourcePluginProvider.future);
      final sub = container.listen(sourcedTrackProvider(query), (_, __) {});
      try {
        for (var i = 0; i < 500 && sub.read().isLoading; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        return sub.read().requireValue;
      } finally {
        sub.close();
      }
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      audioSource = _CountingAudioSource();
      configs = _StubConfigsNotifier();
      track = fullTrack('t1');
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userPreferencesProvider.overrideWith(
            () => StubPrefsNotifier(
              PreferencesTable.defaults().copyWith(downloadLocation: ''),
            ),
          ),
          audioSourcePluginProvider.overrideWith(
            (ref) async => _StubManifestPlugin(audioSource),
          ),
          metadataPluginsProvider.overrideWith(() => configs),
          audioSourcePresetsProvider.overrideWith(
            () => FixedPresetsNotifier(
              AudioSourcePresetsState(
                presets: [
                  SpotubeAudioSourceContainerPreset.lossy(
                    type: SpotubeMediaCompressionType.lossy,
                    name: 'webm',
                    qualities: [
                      SpotubeAudioLossyContainerQuality(bitrate: 128000)
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('second serve of an unexpired match skips re-extraction', () async {
      audioSource.streamsResult = streamsWithExpire(_nowSeconds() + 3600);
      await seedMatch(track.id, 'v1');

      final first = await resolve(track);
      expect(first.sources, hasLength(1));
      expect(audioSource.streamsCalls, 1);

      // Auto-dispose lags listener removal, so force the rebuild: only a
      // fresh fetchFromTrack can prove the manifest cache served.
      container.invalidate(sourcedTrackProvider(track));
      final second = await resolve(track);
      expect(
        [for (final s in second.sources) s.url],
        [for (final s in first.sources) s.url],
      );
      expect(audioSource.streamsCalls, 1,
          reason: 'the cached manifest serves while unexpired');
    });

    test('unknown-expiry manifests keep re-extracting', () async {
      audioSource.streamsResult = [
        SpotubeAudioSourceStreamObject(
          url: 'https://example.test/stream/no-expire',
          container: 'webm',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ];
      await seedMatch(track.id, 'v1');

      await resolve(track);
      expect(audioSource.streamsCalls, 1);
      container.invalidate(sourcedTrackProvider(track));
      await resolve(track);
      expect(audioSource.streamsCalls, 2,
          reason: 'unreasoned-about URLs must not be cached');
    });
  });
}

class _CountingAudioSource implements MetadataPluginAudioSourceEndpoint {
  List<SpotubeAudioSourceStreamObject> streamsResult = const [];

  int streamsCalls = 0;

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

class _StubManifestPlugin implements MetadataPlugin {
  _StubManifestPlugin(this.audioSource);

  @override
  final MetadataPluginAudioSourceEndpoint audioSource;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _StubConfigsNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() async {
    return MetadataPluginState(
      plugins: [
        PluginConfiguration(
          name: 'Test Audio',
          description: 'test',
          version: '1.0.0',
          author: 'test',
          entryPoint: 'plugin.out',
          pluginApiVersion: '2.0.0',
          abilities: const [PluginAbilities.audioSource],
        ),
      ],
      defaultAudioSourcePlugin: 0,
    );
  }
}
