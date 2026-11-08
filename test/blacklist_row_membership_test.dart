// Every visible TrackTile asked "am I blacklisted?" through a per-track provider
// whose body watched the whole blacklist table and scanned all of it — so a
// screenful of rows meant a table-length scan per row, each owning its own
// provider element, all of them re-running on any change to the table. Rows now
// read one shared id set, which is why the set is built once per change however
// many rows ask, and why the per-row answer costs one lookup per artist.
// `_naive` is the implementation that was there, kept as the oracle.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/blacklist_provider.dart';

SpotubeSimpleAlbumObject _album(String id) => SpotubeSimpleAlbumObject(
      id: id,
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    );

SpotubeSimpleArtistObject _artist(String id) => SpotubeSimpleArtistObject(
      id: id,
      name: 'Artist $id',
      externalUri: 'https://example.test/artist/$id',
    );

SpotubeFullTrackObject _track(String id, {List<String> artistIds = const []}) =>
    SpotubeFullTrackObject(
      id: id,
      name: 'Track $id',
      externalUri: 'https://example.test/track/$id',
      artists: (artistIds.isEmpty ? [id] : artistIds).map(_artist).toList(),
      album: _album(id),
      durationMs: 180000,
      isrc: 'ISRC$id',
      explicit: false,
    );

BlacklistTableData _entry(String id) => BlacklistTableData(
      id: 0,
      name: 'Blocked $id',
      elementType: BlacklistedType.artist,
      elementId: id,
    );

/// The pre-change predicate, verbatim: a list scan per question, per artist.
bool _naive(
  List<BlacklistTableData> entries,
  SpotubeTrackObject track,
) {
  if (entries.isEmpty) return false;
  return entries.any((element) => element.elementId == track.id) ||
      track.artists
          .any((artist) => entries.any((el) => el.elementId == artist.id));
}

/// The table provider, driven by the test instead of by drift.
class _StubBlacklistNotifier extends BlackListNotifier {
  _StubBlacklistNotifier(this.entries);

  List<BlacklistTableData> entries;
  int builds = 0;

  @override
  Future<List<BlacklistTableData>> build() async {
    builds++;
    return entries;
  }

  void replace(List<BlacklistTableData> next) {
    entries = next;
    state = AsyncData(next);
  }
}

Future<void> drain([int yields = 50]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('BlackListNotifier.matches', () {
    test('hits on the track itself', () {
      expect(
        BlackListNotifier.matches({'t1'}, _track('t1', artistIds: ['a1'])),
        isTrue,
      );
    });

    test('hits through one of the artists, as the table scan did', () {
      expect(
        BlackListNotifier.matches(
            {'a2'}, _track('t1', artistIds: ['a1', 'a2'])),
        isTrue,
      );
    });

    test('misses an unrelated track', () {
      expect(
        BlackListNotifier.matches({'a9'}, _track('t1', artistIds: ['a1'])),
        isFalse,
      );
    });

    test('an empty table short-circuits', () {
      expect(BlackListNotifier.matches(const {}, _track('t1')), isFalse);
    });

    test('agrees with the scan it replaced, on random pools', () {
      final random = Random(7);
      for (var pool = 0; pool < 200; pool++) {
        final ids = [
          for (var i = 0; i < 1 + random.nextInt(12); i++) 'x$pool-$i',
        ];
        final entries = ids.map(_entry).toList();
        final needle = _track(
          't$pool',
          artistIds: [
            for (final i in ids.take(random.nextInt(ids.length))) i,
            'own-$pool',
          ],
        );
        expect(
          BlackListNotifier.matches(BlackListNotifier.idsOf(entries), needle),
          _naive(entries, needle),
          reason: 'pool $pool / ${needle.artists.map((a) => a.id)}',
        );
      }
    });
  });

  group('blacklistedIdsProvider', () {
    test('builds once per change, however many rows ask', () async {
      final notifier = _StubBlacklistNotifier([_entry('a1')]);
      final container = ProviderContainer(
        overrides: [blacklistProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);

      var setBuilds = 0;
      final probe = Provider<int>((ref) {
        ref.watch(blacklistedIdsProvider);
        return ++setBuilds;
      });
      // A screenful of tiles, each with the select a row uses.
      final subs = [
        for (var i = 0; i < 200; i++)
          container.listen(
            blacklistedIdsProvider.select(
              (ids) => BlackListNotifier.matches(ids, _track('t$i')),
            ),
            (_, __) {},
          ),
        container.listen(probe, (_, __) {}),
      ];
      await container.read(blacklistProvider.future);

      // The table resolves once from AsyncLoading, so the set is already warm
      // here; what matters is that nothing after this rebuilds per watching row.
      final warm = container.read(probe);
      expect(notifier.builds, 1);

      notifier.replace([_entry('a1'), _entry('a2')]);
      await drain();

      // One rebuild for one change, not one per watching row.
      expect(setBuilds, warm + 1);
      expect(notifier.builds, 1);

      notifier.replace([_entry('a2')]);
      await drain();
      expect(setBuilds, warm + 2);

      for (final sub in subs) {
        sub.close();
      }
    });

    test('a change to the table reaches a row that asked about it', () async {
      final notifier = _StubBlacklistNotifier(const []);
      final container = ProviderContainer(
        overrides: [blacklistProvider.overrideWith(() => notifier)],
      );
      addTearDown(container.dispose);

      final track = _track('t1', artistIds: ['a1']);
      var blocked = false;
      final sub = container.listen<bool>(
        blacklistedIdsProvider.select(
          (ids) => BlackListNotifier.matches(ids, track),
        ),
        (_, next) => blocked = next,
      );
      // The first build is asynchronous, like the drift query it stands in for:
      // state set before it completes would be overwritten by its result.
      await container.read(blacklistProvider.future);
      expect(sub.read(), isFalse);

      notifier.replace([_entry('a1')]);
      await drain();
      expect(
        blocked,
        isTrue,
        reason: 'blacklisting the artist must reach the row',
      );

      notifier.replace(const []);
      await drain();
      expect(blocked, isFalse);
      sub.close();
    });
  });

  test('the set removes the table-length scan from a screenful of rows', () {
    // 5,000 entries × 200 mounted rows was the shape of a blacklisted library
    // with a full playlist open; five rounds stands in for five rebuilds.
    const entries = 5000;
    const rows = 200;
    const rounds = 5;

    final table = [
      for (var i = 0; i < entries; i++) _entry('block-$i'),
    ];
    final ids = BlackListNotifier.idsOf(table);
    final needles = [
      for (var i = 0; i < rows; i++)
        _track('t$i', artistIds: ['untouched-$i', 'also-$i']),
    ];

    final naive = Stopwatch()..start();
    for (var round = 0; round < rounds; round++) {
      for (final needle in needles) {
        expect(_naive(table, needle), isFalse);
      }
    }
    naive.stop();

    final indexed = Stopwatch()..start();
    for (var round = 0; round < rounds; round++) {
      for (final needle in needles) {
        expect(BlackListNotifier.matches(ids, needle), isFalse);
      }
    }
    indexed.stop();

    // Generous: the point is that per-row cost no longer tracks table size,
    // not a precise ratio on a shared machine.
    // ignore: avoid_print
    print(
      '[blacklist ${entries}x$rows] naive=${naive.elapsedMicroseconds}us '
      'indexed=${indexed.elapsedMicroseconds}us '
      'speedup=${(naive.elapsedMicroseconds / indexed.elapsedMicroseconds).toStringAsFixed(1)}x',
    );
    expect(
      naive.elapsedMicroseconds,
      greaterThan(indexed.elapsedMicroseconds * 5),
      reason: 'naive ${naive.elapsedMicroseconds}µs vs indexed '
          '${indexed.elapsedMicroseconds}µs',
    );
  });
}
