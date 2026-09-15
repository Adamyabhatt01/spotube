// Tests for Phase 2.4 bounded HEAD validation
// (lib/services/sourced_track/validation.dart).
//
// The validator is exercised with fake status functions so concurrency cap,
// ordering, filtering, abort semantics, timeout, and latency are all
// observable without network access.

import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/sourced_track/validation.dart';

void main() {
  test('concurrency cap: 8 candidates peak at 4 simultaneous', () {
    fakeAsync((async) {
      var inFlight = 0;
      var maxObserved = 0;

      List<int>? result;
      filterValidBounded(
        List.generate(8, (i) => i),
        (candidate) async {
          inFlight++;
          maxObserved = max(maxObserved, inFlight);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          inFlight--;
          return 200;
        },
      ).then((value) => result = value);
      async.elapse(const Duration(seconds: 5));

      expect(result, List.generate(8, (i) => i));
      expect(maxObserved, lessThanOrEqualTo(4));
      expect(maxObserved, greaterThan(1));
    });
  });

  test('order preserved when candidates complete out of order', () {
    fakeAsync((async) {
      List<String>? result;
      filterValidBounded(
        List.generate(6, (i) => 'candidate-$i'),
        (candidate) async {
          final index = int.parse(candidate.split('-').last);
          // Later candidates finish first.
          await Future<void>.delayed(
            Duration(milliseconds: 10 * (6 - index)),
          );
          return 200;
        },
      ).then((value) => result = value);
      async.elapse(const Duration(seconds: 5));

      expect(result, List.generate(6, (i) => 'candidate-$i'));
    });
  });

  test('all-valid matches serial result', () async {
    final candidates = ['a', 'b', 'c'];
    final result = await filterValidBounded(
      candidates,
      (_) async => 200,
    );

    expect(result, candidates);
  });

  test('4xx responses remain filtered', () async {
    final statuses = [200, 404, 206, 403, 301];
    final result = await filterValidBounded(
      List.generate(statuses.length, (i) => 'c$i'),
      (candidate) async => statuses[int.parse(candidate.substring(1))],
    );

    expect(result, ['c0', 'c2', 'c4']);
  });

  test('throw aborts without partial results', () {
    fakeAsync((async) {
      Object? caught;
      filterValidBounded(
        ['ok-1', 'boom', 'ok-2'],
        (candidate) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (candidate == 'boom') throw StateError('sick mirror');
          return 200;
        },
      ).then<void>((_) {}, onError: (Object e) {
        caught = e;
      });
      async.elapse(const Duration(seconds: 5));

      expect(caught, isStateError);
    });
  });

  test('hung candidate terminates at the timeout ceiling', () {
    fakeAsync((async) {
      Object? caught;
      filterValidBounded(
        ['hung'],
        (_) => Completer<int?>().future,
        timeout: const Duration(milliseconds: 100),
      ).then<void>((_) {}, onError: (Object e) {
        caught = e;
      });
      async.elapse(const Duration(milliseconds: 100));

      expect(caught, isA<TimeoutException>());
    });
  });

  test('empty and all-invalid inputs preserve existing behavior', () async {
    expect(
      await filterValidBounded<String>([], (_) async => 200),
      isEmpty,
    );
    expect(
      await filterValidBounded(
        ['a', 'b'],
        (_) async => 404,
      ),
      isEmpty,
    );
  });

  test('latency is wave-bound, not serial', () {
    fakeAsync((async) {
      const perRequest = Duration(milliseconds: 100);
      List<int>? result;
      filterValidBounded(
        List.generate(8, (i) => i),
        (_) async {
          await Future<void>.delayed(perRequest);
          return 200;
        },
      ).then((value) => result = value);

      // Two waves of 4 complete at exactly t=200ms; serial would need
      // 800ms. Virtual time makes this exact instead of ceiling-based.
      async.elapse(const Duration(milliseconds: 199));
      expect(result, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(result, hasLength(8));
    });
  });
}
