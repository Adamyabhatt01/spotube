import 'package:spotube/provider/download_manager/download_tasks.dart';

/// Keeps up to [maxConcurrent] workers draining a queue of download tasks.
///
/// Late arrivals are picked up as well, since workers claim whatever is
/// queued when they become free. The caller supplies the claim/run operations
/// so the pool never touches provider state directly.
class DownloadWorkerPool {
  final int maxConcurrent;
  final bool Function() canStart;
  final bool Function() hasQueued;
  final DownloadTask? Function() claim;
  final Future<void> Function(DownloadTask task) run;

  int _activeWorkers = 0;

  DownloadWorkerPool({
    required this.maxConcurrent,
    required this.canStart,
    required this.hasQueued,
    required this.claim,
    required this.run,
  });

  void pump() {
    // Queued work waits for the plugin's presets; the presets listener pumps
    // it once a destination extension exists.
    if (!canStart()) return;
    while (_activeWorkers < maxConcurrent) {
      if (!hasQueued()) return;
      _activeWorkers++;
      _worker().whenComplete(() {
        _activeWorkers--;
        pump();
      });
    }
  }

  Future<void> _worker() async {
    while (true) {
      final task = claim();
      if (task == null) return;
      try {
        await run(task);
      } catch (_) {
        // The run callback reports its own failures via status updates.
        // Never let a worker die loudly and stall the pool.
      }
    }
  }
}
