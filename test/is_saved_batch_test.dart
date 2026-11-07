import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/metadata_plugin/library/is_saved_batcher.dart';

/// Every `request` in one event-loop turn flushes as a single plugin call,
/// and the per-id result equals what the walk (contains) would have said.
void main() {
  group('IsSavedBatcher', () {
    test('batches every request made in the same tick into one call', () async {
      final calls = <List<String>>[];
      final batcher = IsSavedBatcher((ids) async {
        calls.add(List.of(ids));
        return ids.map((id) => id.endsWith('*')).toList();
      });

      final results = await Future.wait([
        batcher.request('a'),
        batcher.request('b*'),
        batcher.request('c'),
        batcher.request('d*'),
      ]);

      expect(calls, hasLength(1));
      expect(calls.single, ['a', 'b*', 'c', 'd*']);
      expect(results, [false, true, false, true]);
    });

    test('deduplicates repeated ids within a flush', () async {
      final calls = <List<String>>[];
      final batcher = IsSavedBatcher((ids) async {
        calls.add(List.of(ids));
        return ids.map((_) => true).toList();
      });

      final results = await Future.wait([
        batcher.request('x'),
        batcher.request('x'),
        batcher.request('x'),
      ]);

      expect(results, [true, true, true]);
      expect(calls.single, ['x']);
    });

    test('chunks 51 ids into two calls of 50 + 1 (Spotify limit)', () async {
      final calls = <List<String>>[];
      final batcher = IsSavedBatcher((ids) async {
        calls.add(List.of(ids));
        return List<bool>.filled(ids.length, false);
      });

      final ids = List.generate(51, (i) => 'id$i');
      await Future.wait(ids.map(batcher.request));

      expect(calls.map((c) => c.length).toList(), [50, 1]);
      // Order preserved within each chunk, and every id was fetched exactly once.
      expect(calls.expand((c) => c).toSet(), ids.toSet());
    });

    test('batch result matches walk result (contains == set membership)',
        () async {
      // Ground truth: a set of "saved" ids. The old code walked a saved-list
      // and asked `ids.contains(id)`; the new code asks `isSaved(ids)`.
      final saved = {'s1', 's3', 's5', 's7'};
      final batcher = IsSavedBatcher((ids) async {
        return ids.map(saved.contains).toList();
      });

      final probe = [for (var i = 0; i < 10; i++) 's$i'];
      final batched = await Future.wait(probe.map(batcher.request));
      final walked = probe.map(saved.contains).toList();

      expect(batched, walked);
    });

    test('plugin error propagates to every waiter of the failed chunk',
        () async {
      final batcher = IsSavedBatcher((ids) async {
        throw StateError('rate limited');
      });

      final futures = [batcher.request('a'), batcher.request('b')];
      final results = await Future.wait(
        futures.map((f) => f.then<Object?>((v) => v).catchError((e) => e)),
      );

      expect(results, everyElement(isA<StateError>()));
    });

    test('length-mismatch is surfaced as an error, never silently truncated',
        () async {
      final batcher = IsSavedBatcher((ids) async {
        // Deliberately short: this is plugin misbehavior, not a real result.
        return [true];
      });

      final a = batcher.request('a');
      final b = batcher.request('b');

      await expectLater(a, throwsA(isA<StateError>()));
      await expectLater(b, throwsA(isA<StateError>()));
    });

    test('requests arriving during a flush schedule a separate follow-up call',
        () async {
      final calls = <List<String>>[];
      final gate = Completer<void>();
      final batcher = IsSavedBatcher((ids) async {
        calls.add(List.of(ids));
        await gate.future;
        return List<bool>.filled(ids.length, false);
      });

      final first = batcher.request('a');
      // Yield to the event loop so the zero-delay flush timer fires and _flush
      // starts awaiting [gate] — the batch has been detached from _pending by
      // then, so a fresh request can no longer ride along with it.
      await Future.delayed(Duration.zero);
      final second = batcher.request('b');

      gate.complete();
      await first;
      await second;

      expect(calls.length, 2);
      expect(calls[0], ['a']);
      expect(calls[1], ['b']);
    });

    test('maxBatchSize override is respected', () async {
      final calls = <List<String>>[];
      final batcher = IsSavedBatcher(
        (ids) async {
          calls.add(List.of(ids));
          return List<bool>.filled(ids.length, false);
        },
        maxBatchSize: 3,
      );

      await Future.wait(List.generate(7, (i) => 'id$i').map(batcher.request));
      expect(calls.map((c) => c.length).toList(), [3, 3, 1]);
    });
  });
}
