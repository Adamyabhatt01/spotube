/// Runs [tasks] in bounded sequential waves, collecting results in
/// original order.
///
/// Unlike an unbounded `Future.wait` over all tasks, at most [waveSize]
/// task closures run at once, bounding peak CPU/RAM/bridge contention
/// for large inputs (e.g. a 1,000-file library scan). Unlike fully serial
/// execution, independent tasks within a wave still overlap, so elapsed
/// time stays near `ceil(n / waveSize)` wave durations.
///
/// A throwing task aborts the whole collection (partial results are
/// discarded, the first error is rethrown) — callers that need
/// per-item resilience must catch inside their own closures.
/// [onWaveDone] observes completed wave indexes (e.g. for cancellation
/// checks between waves).
Future<List<T>> collectInWaves<T>(
  List<Future<T> Function()> tasks, {
  int waveSize = 32,
  void Function(int waveIndex)? onWaveDone,
}) async {
  assert(waveSize > 0, 'waveSize must be positive');

  final results = <T>[];
  var waveIndex = 0;
  for (var start = 0; start < tasks.length; start += waveSize) {
    final end = (start + waveSize).clamp(0, tasks.length);
    // Future.wait preserves input order, so chunk results append back
    // in original index order trivially.
    results.addAll(
      await Future.wait([
        for (var i = start; i < end; i++) tasks[i](),
      ]),
    );
    onWaveDone?.call(waveIndex);
    waveIndex++;
  }
  return results;
}
