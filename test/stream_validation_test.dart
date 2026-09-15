// Tests for Phase 2.4 bounded HEAD validation
// (lib/services/sourced_track/validation.dart).
//
// The validator is exercised with fake status functions so concurrency cap,
// ordering, filtering, abort semantics, timeout, and latency are all
// observable without network access.

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/sourced_track/validation.dart';

void main() {
  test('concurrency cap: 8 candidates peak at 4 simultaneous', () async {
    var inFlight = 0;
    var maxObserved = 0;

    final result = await filterValidBounded(
      List.generate(8, (i) => i),
      (candidate) async {
        inFlight++;
        maxObserved = max(maxObserved, inFlight);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        inFlight--;
        return 200;
      },
    );

    expect(result, List.generate(8, (i) => i));
    expect(maxObserved, lessThanOrEqualTo(4));
    expect(maxObserved, greaterThan(1));
  });

  test('order preserved when candidates complete out of order', () async {
    final result = await filterValidBounded(
      List.generate(6, (i) => 'candidate-$i'),
      (candidate) async {
        final index = int.parse(candidate.split('-').last);
        // Later candidates finish first.
        await Future<void>.delayed(
          Duration(milliseconds: 10 * (6 - index)),
        );
        return 200;
      },
    );

    expect(result, List.generate(6, (i) => 'candidate-$i'));
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

  test('throw aborts without partial results', () async {
    Object? caught;
    try {
      await filterValidBounded(
        ['ok-1', 'boom', 'ok-2'],
        (candidate) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (candidate == 'boom') throw StateError('sick mirror');
          return 200;
        },
      );
    } catch (e) {
      caught = e;
    }

    expect(caught, isStateError);
  });

  test('hung candidate terminates at the timeout ceiling', () async {
    final stopwatch = Stopwatch()..start();
    Object? caught;
    try {
      await filterValidBounded(
        ['hung'],
        (_) => Completer<int?>().future,
        timeout: const Duration(milliseconds: 100),
      );
    } catch (e) {
      caught = e;
    } finally {
      stopwatch.stop();
    }

    expect(caught, isA<TimeoutException>());
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
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

  test('latency is wave-bound, not serial', () async {
    const perRequest = Duration(milliseconds: 100);
    final stopwatch = Stopwatch()..start();
    final result = await filterValidBounded(
      List.generate(8, (i) => i),
      (_) async {
        await Future<void>.delayed(perRequest);
        return 200;
      },
    );
    stopwatch.stop();

    expect(result, hasLength(8));
    // Serial would take ~800ms; 2 waves of 4 take ~200ms. Generous ceiling
    // keeps this robust on loaded CI while still refuting serial behavior.
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 700)));
  });
}
