// Efficiency rules for the lyrics fetch path:
// the User-Agent is read once per process, misses suppress refetching,
// concurrent resolutions of one track share a single fetch, and large
// documents parse off the calling isolate.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/lyrics/better_lyrics_provider.dart';
import 'package:spotube/services/lyrics/lrclib_provider.dart';
import 'package:spotube/services/lyrics/lyrics_provider.dart';

class _CountingProvider implements LyricsProvider {
  _CountingProvider(this.id, this.result, [this.delay = Duration.zero]);

  @override
  final String id;
  final List<LyricSlice>? result;
  final Duration delay;
  int calls = 0;

  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    calls++;
    await Future<void>.delayed(delay);
    if (result == null) throw StateError('broken: $id');
    return SubtitleSimple(
      uri: Uri.parse('http://example.test'),
      name: track.name,
      lyrics: result!,
      rating: 100,
      provider: id,
    );
  }
}

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test $id',
    externalUri: 'http://example.test/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a1',
        name: 'Artist',
        externalUri: 'http://example.test/a1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'al1',
      name: 'Album',
      externalUri: 'http://example.test/al1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'ISRC$id',
    explicit: false,
  );
}

/// Drives one resolution to completion, rethrowing the notifier error.
Future<SubtitleSimple> _resolve(
  ProviderContainer container,
  SpotubeFullTrackObject track,
) async {
  final sub = container.listen(syncedLyricsProvider(track), (_, __) {});
  try {
    for (var i = 0; i < 500 && sub.read().isLoading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return sub.read().requireValue;
  } finally {
    sub.close();
  }
}

late List<LyricsProvider> testProviders;

void main() {
  AppLogger.initialize(false);

  late AppDatabase database;

  setUp(() async {
    testProviders = [];
    clearLyricsFetchState();
    debugOverrideLyricsUserAgent(null);
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    clearLyricsFetchState();
    debugOverrideLyricsUserAgent(null);
    await database.close();
  });

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        lyricsProvidersProvider.overrideWithValue(testProviders),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('user agent', () {
    test('read once per process, shared by every fetch', () async {
      var reads = 0;
      debugOverrideLyricsUserAgent(() async {
        reads++;
        return 'test-agent';
      });

      expect(await lyricsUserAgent(), 'test-agent');
      expect(await lyricsUserAgent(), 'test-agent');
      expect(await lyricsUserAgent(), 'test-agent');
      expect(reads, 1, reason: 'one platform read per process, not per track');
    });
  });

  group('miss cache', () {
    test('a repeated miss costs zero provider calls', () async {
      final broken = _CountingProvider('broken', null);
      final empty = _CountingProvider('empty', const []);
      testProviders.addAll([broken, empty]);
      final track = _track('miss-1');

      await expectLater(_resolve(newContainer(), track), throwsException);
      expect(broken.calls, 1);
      expect(empty.calls, 1);

      // Fresh container, same track: the recorded miss short-circuits the
      // whole chain before any provider runs.
      await expectLater(_resolve(newContainer(), track), throwsException);
      expect(broken.calls, 1, reason: 'miss must suppress refetching');
      expect(empty.calls, 1, reason: 'miss must suppress refetching');
    });

    test('a miss for one track does not suppress another', () async {
      testProviders.add(_CountingProvider('broken', null));

      await expectLater(
        _resolve(newContainer(), _track('miss-a')),
        throwsException,
      );

      final ok = _CountingProvider(
        'ok',
        [LyricSlice(text: 'hello', time: Duration.zero)],
      );
      testProviders.add(ok);
      final state = await _resolve(newContainer(), _track('miss-b'));
      expect(state.provider, 'ok');
      expect(ok.calls, 1);
    });
  });

  group('single-flight', () {
    test('two concurrent resolutions share one fetch', () async {
      final slow = _CountingProvider(
        'slow',
        [LyricSlice(text: 'hello', time: Duration.zero)],
        const Duration(milliseconds: 50),
      );
      testProviders.add(slow);
      final track = _track('shared-1');

      final first = newContainer();
      final second = newContainer();
      final sub1 = first.listen(syncedLyricsProvider(track), (_, __) {});
      final sub2 = second.listen(syncedLyricsProvider(track), (_, __) {});
      try {
        for (var i = 0;
            i < 200 && (sub1.read().isLoading || sub2.read().isLoading);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(sub1.read().requireValue.provider, 'slow');
        expect(sub2.read().requireValue.provider, 'slow');
      } finally {
        sub1.close();
        sub2.close();
      }
      expect(slow.calls, 1,
          reason: 'concurrent resolutions of one track share the fetch');
    });
  });

  group('isolate parsing', () {
    test('large LRC document parses identically off the main isolate',
        () async {
      const line = '[00:01.00] hello world, this is a lyric line\n';
      const repeats = 20000 ~/ line.length + 1;
      final raw = List.filled(repeats, line).join();
      // Must exceed the isolate-parse threshold (16 KiB) to exercise the
      // compute() path rather than the inline one.
      expect(raw.length, greaterThan(16384));

      final parsed = await parseLrcDocument(raw);
      expect(parsed, isNotNull);
      expect(parsed!.length, repeats);
      expect(parsed.first.text, 'hello world, this is a lyric line');
    });

    test('small documents keep the inline result', () async {
      const raw = '[00:01.00] hello\n[00:05.00] world\n';
      final parsed = await parseLrcDocument(raw);
      expect(parsed?.map((s) => s.text).toList(), ['hello', 'world']);
    });

    test('large TTML document parses identically off the main isolate',
        () async {
      const line =
          '<p begin="00:01.000">hello world, this is a lyric line</p>\n';
      const repeats = 20000 ~/ line.length + 1;
      final raw = List.filled(repeats, line).join();

      final parsed = await parseTtmlDocument(raw);
      expect(parsed.length, repeats);
      expect(parsed.first.text, 'hello world, this is a lyric line');
    });
  });
}
