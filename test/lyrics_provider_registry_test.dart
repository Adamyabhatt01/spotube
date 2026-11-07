// Tests the production lyrics resolution loop in SyncedLyricsNotifier
// (lib/provider/lyrics/synced.dart): priority between providers, the rule that
// timestamps beat plain text and whitespace beats nothing, failure isolation,
// and the database cache. Fakes are injected through the `lyricsProvidersProvider`
// override; the real notifier and a real in-memory database do the work.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/lyrics/lyrics_provider.dart';

class _RecordingProvider implements LyricsProvider {
  _RecordingProvider(this.id, this.result);

  @override
  final String id;

  /// null = throw, empty list = empty result, non-empty = hit.
  final List<LyricSlice>? result;

  int calls = 0;

  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    calls++;
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

final _hit = [LyricSlice(text: 'hello', time: Duration.zero)];
final _syncedHit = [
  LyricSlice(text: 'hello', time: const Duration(seconds: 4)),
];
final _blankHit = [LyricSlice(text: '   ', time: Duration.zero)];
final _track = SpotubeFullTrackObject(
  id: 't1',
  name: 'Test',
  externalUri: 'http://example.test/t1',
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
  isrc: 'ISRC',
  explicit: false,
);

/// Kick the notifier and wait for it to settle, rethrowing its error so
/// `throwsA` can match against it.
Future<SubtitleSimple> _resolve(ProviderContainer container) async {
  final sub = container.listen(syncedLyricsProvider(_track), (_, __) {});
  addTearDown(sub.close);

  for (var i = 0; i < 200 && sub.read().isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return sub.read().requireValue;
}

late List<LyricsProvider> testProviders;

Future<ProviderContainer> pumpContainer(AppDatabase database) {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      lyricsProvidersProvider.overrideWithValue(testProviders),
    ],
  );
  addTearDown(container.dispose);
  return Future.value(container);
}

/// Writes a cache row straight to the table, the way an earlier version of the
/// app would have.
Future<void> seedRow(
  AppDatabase database,
  List<LyricSlice> lyrics,
  String provider,
) {
  return database.into(database.lyricsTable).insert(
        LyricsTableCompanion.insert(
          trackId: _track.id,
          data: SubtitleSimple(
            uri: Uri.parse('http://example.test'),
            name: _track.name,
            lyrics: lyrics,
            rating: 0,
            provider: provider,
          ),
        ),
      );
}

void main() {
  AppLogger.initialize(false);

  late AppDatabase database;

  setUp(() async {
    testProviders = [];
    // Static fetch state (miss cache, in-flight map) would otherwise leak
    // between cases in this file.
    clearLyricsFetchState();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    clearLyricsFetchState();
    await database.close();
  });

  test('a synced provider wins and the loop stops there', () async {
    final first = _RecordingProvider('first', _syncedHit);
    final second = _RecordingProvider('second', _hit);
    testProviders.addAll([first, second]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'first');
    expect(first.calls, 1);
    expect(second.calls, 0, reason: 'timestamps are the best answer possible');
  });

  test('a blank answer is a miss, not a hit', () async {
    final blank = _RecordingProvider('blank', _blankHit);
    final ok = _RecordingProvider('ok', _hit);
    testProviders.addAll([blank, ok]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'ok',
        reason: 'a list of whitespace is what an empty plainLyrics answer '
            'looks like after split("\\n"), and it used to be cached forever');
    expect(ok.calls, 1);
  });

  test('an unsynced answer yields to a later synced one', () async {
    final plain = _RecordingProvider('plain-first', _hit);
    final synced = _RecordingProvider('better-synced', _syncedHit);
    testProviders.addAll([plain, synced]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'better-synced');
    expect(state.lyrics.single.time, const Duration(seconds: 4));
  });

  test('an unsynced answer still beats nothing', () async {
    final plain = _RecordingProvider('plain-first', _hit);
    testProviders.addAll([plain, _RecordingProvider('empty', [])]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'plain-first');
  });

  test('duplicate cached rows resolve instead of throwing', () async {
    // trackId has no unique index, so two rows for one track are reachable.
    // The read used to be getSingleOrNull(), which threw on the second one.
    await seedRow(database, _blankHit, 'stale-blank');
    await seedRow(database, _syncedHit, 'stale-synced');
    testProviders.add(_RecordingProvider('never', _hit));

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'stale-synced');
    expect(state.lyrics.single.time, const Duration(seconds: 4));
  });

  test('a blank cached row is refetched and collapsed to one row', () async {
    await seedRow(database, _blankHit, 'stale-blank');
    final ok = _RecordingProvider('ok', _syncedHit);
    testProviders.add(ok);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'ok');
    expect(ok.calls, 1, reason: 'an empty cache entry must not be trusted');
    final rows = await database.select(database.lyricsTable).get();
    expect(rows, hasLength(1), reason: 'the stale row is replaced, not added to');
  });

  test('empty provider does not win over a later non-empty one', () async {
    final empty = _RecordingProvider('empty', []);
    final ok = _RecordingProvider('ok', _hit);
    testProviders.addAll([empty, ok]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'ok');
    expect(empty.calls, 1);
    expect(ok.calls, 1);
  });

  test('a failing provider is isolated and does not block later ones',
      () async {
    final broken = _RecordingProvider('broken', null);
    final ok = _RecordingProvider('ok', _hit);
    testProviders.addAll([broken, ok]);

    final state = await _resolve(await pumpContainer(database));

    expect(state.provider, 'ok');
    expect(broken.calls, 1, reason: 'the loop must continue past a throw');
  });

  test('all-empty/all-failing surfaces the notifier error', () async {
    testProviders.addAll([
      _RecordingProvider('broken', null),
      _RecordingProvider('empty', []),
    ]);

    await expectLater(
      _resolve(await pumpContainer(database)),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('Unable to find lyrics'),
      )),
    );
  });

  test('resolved lyrics are cached; a cache hit skips all providers',
      () async {
    final ok = _RecordingProvider('ok', _hit);
    testProviders.add(ok);

    final first = await _resolve(await pumpContainer(database));
    expect(first.provider, 'ok');
    expect(ok.calls, 1);

    // A fresh container must serve from the database, not the providers.
    final second = await _resolve(await pumpContainer(database));
    expect(second.provider, 'ok');
    expect(ok.calls, 1, reason: 'cache hit must not re-query providers');

    final rows = await database.select(database.lyricsTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.trackId, _track.id);
  });
}
