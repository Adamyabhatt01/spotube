import 'dart:async';

/// Validates [candidates] concurrently in bounded waves and returns the
/// valid ones in original index order.
///
/// Each wave runs at most [maxConcurrency] validations at once (never an
/// unbounded `Future.wait` over all candidates). Results are re-associated
/// by index, so out-of-order completions cannot change selection semantics.
///
/// Error contract mirrors the previous serial loop: a throwing validator
/// aborts the whole operation (partial results are discarded, the first
/// error is rethrown) — failures are never silently converted into skips.
/// [timeout] bounds each individual validation; previously a hung request
/// stalled the entire sequence with no ceiling at all (30s default matches
/// the plugin-download `receiveTimeout` precedent).
///
/// [validateOne] returns the observed status code, or null when no response
/// was observed. A candidate is valid when its status is below 400.
/// [onValidated] observes each outcome in original order (e.g. for logging).
Future<List<T>> filterValidBounded<T>(
  List<T> candidates,
  Future<int?> Function(T candidate) validateOne, {
  int maxConcurrency = 4,
  Duration timeout = const Duration(seconds: 30),
  void Function(T candidate, int? statusCode)? onValidated,
}) async {
  final statuses = await _mapBounded(
    [for (final candidate in candidates) () => validateOne(candidate)],
    maxConcurrency: maxConcurrency,
    timeout: timeout,
  );

  final valid = <T>[];
  for (var i = 0; i < candidates.length; i++) {
    onValidated?.call(candidates[i], statuses[i]);
    if (statuses[i] != null && statuses[i]! < 400) {
      valid.add(candidates[i]);
    }
  }
  return valid;
}

Future<List<R>> _mapBounded<R>(
  List<Future<R> Function()> tasks, {
  required int maxConcurrency,
  required Duration timeout,
}) async {
  assert(maxConcurrency > 0, 'maxConcurrency must be positive');

  final results = <R>[];
  for (var start = 0; start < tasks.length; start += maxConcurrency) {
    final end = (start + maxConcurrency).clamp(0, tasks.length);
    // Future.wait preserves input order, so chunk results map back to
    // candidate indices trivially. A throw here aborts with partial
    // results discarded (see contract above).
    results.addAll(
      await Future.wait([
        for (var i = start; i < end; i++) tasks[i]().timeout(timeout),
      ]),
    );
  }
  return results;
}
