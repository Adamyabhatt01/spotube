import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';
import 'support/perf_fixtures.dart';

void main() {
  setUpAll(() => AppLogger.initialize(false));

  SpotubeFullTrackObject track(String id) => PerfFixtures.track(id);

  group('appendCollectionTail', () {
    test('appends the pages that came after alreadyLoaded', () async {
      final page1 = [track('t1'), track('t2')];
      final tail = [track('t3'), track('t4')];
      final appended = <SpotubeFullTrackObject>[];

      await appendCollectionTail(
        appendTail: (chunk) async => appended.addAll(chunk),
        readCollections: () => ['col-1'],
        collectionId: 'col-1',
        alreadyLoaded: page1,
        fetchAll: () async => [...page1, ...tail],
      );

      expect(appended.map((t) => t.id), ['t3', 't4']);
    });

    test('does nothing when the walk returned only the already-loaded page',
        () async {
      final page1 = [track('t1')];
      var addTracksCalled = 0;

      await appendCollectionTail(
        appendTail: (_) async => addTracksCalled++,
        readCollections: () => ['col-1'],
        collectionId: 'col-1',
        alreadyLoaded: page1,
        fetchAll: () async => page1,
      );

      expect(addTracksCalled, 0);
    });

    test('skips the append when the queue no longer holds this collection',
        () async {
      final page1 = [track('t1')];
      var appendCalled = 0;

      await appendCollectionTail(
        appendTail: (_) async => appendCalled++,
        // The user tapped another card, or cleared the queue, mid-walk.
        readCollections: () => ['other'],
        collectionId: 'col-1',
        alreadyLoaded: page1,
        fetchAll: () async => [...page1, track('t2')],
      );

      expect(appendCalled, 0);
    });

    test(
        'walk errors are swallowed and never rethrown to the fire-and-forget caller',
        () async {
      var appendCalled = 0;

      await expectLater(
        appendCollectionTail(
          appendTail: (_) async => appendCalled++,
          readCollections: () => ['col-1'],
          collectionId: 'col-1',
          alreadyLoaded: [track('t1')],
          fetchAll: () async => throw StateError('plugin exploded'),
        ),
        completes,
      );
      expect(appendCalled, 0);
    });

    test('a disposed-widget readCollections is swallowed too', () async {
      var appendCalled = 0;
      await appendCollectionTail(
        appendTail: (_) async => appendCalled++,
        readCollections: () => throw StateError('ref disposed'),
        collectionId: 'col-1',
        alreadyLoaded: [track('t1')],
        fetchAll: () async => [track('t1'), track('t2')],
      );
      expect(appendCalled, 0);
    });

    test('the tap returns while the walk is still in flight', () async {
      // Models the actual UI contract: the play callback awaits
      // `playlistNotifier.load(page1, autoPlay: true)` and
      // `unawaited(appendCollectionTail(...))`, then the spinner clears
      // without ever waiting on the fetch. The tail lands later.
      final walk = Completer<List<SpotubeFullTrackObject>>();
      final appended = <String>[];

      unawaited(appendCollectionTail(
        appendTail: (tail) async => appended.addAll(tail.map((t) => t.id)),
        readCollections: () => ['col-1'],
        collectionId: 'col-1',
        alreadyLoaded: [track('t1')],
        fetchAll: () => walk.future,
      ));

      // Nothing landed yet: the caller has already moved on.
      expect(appended, isEmpty);

      walk.complete([track('t1'), track('t2'), track('t3')]);
      await pumpEventQueue();

      expect(appended, ['t2', 't3']);
    });
  });
}
