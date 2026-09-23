import 'dart:async';

/// Coalesces per-id "is this saved?" lookups into plugin calls of at most
/// [maxBatchSize] ids, mirroring Spotify's `GET /me/tracks/contains?ids=`
/// (which caps at 50 ids and answers with a positional bool array). The
/// metadata plugin exposes the same shape via `isSavedTracks/Albums/Artists`.
///
/// Multiple family instances created in the same build tick each enqueue
/// synchronously; one event-loop turn later the queue flushes as one (or a
/// few, if more than 50 piled up) plugin call(s). Callers see the per-id
/// `Future<bool>` surface they already expect.
///
/// Not thread-safe by design: Riverpod runs in a single isolate, and all
/// `request` calls come from a widget build or a provider body.
class IsSavedBatcher {
  IsSavedBatcher(this._query, {this.maxBatchSize = 50});

  final Future<List<bool>> Function(List<String>) _query;
  final int maxBatchSize;

  final _pending = <String, Completer<bool>>{};
  Timer? _scheduled;

  Future<bool> request(String id) {
    final existing = _pending[id];
    if (existing != null) return existing.future;

    final completer = Completer<bool>();
    _pending[id] = completer;
    _scheduled ??= Timer(Duration.zero, _flush);
    return completer.future;
  }

  Future<void> _flush() async {
    _scheduled = null;
    if (_pending.isEmpty) return;

    // Detach the batch before awaiting so that requests arriving during the
    // plugin call schedule a fresh flush instead of colliding with it.
    final batch = Map<String, Completer<bool>>.of(_pending);
    _pending.clear();

    final ids = batch.keys.toList();
    for (var i = 0; i < ids.length; i += maxBatchSize) {
      final end = i + maxBatchSize;
      final chunk = ids.sublist(i, end > ids.length ? ids.length : end);
      try {
        final saved = await _query(chunk);
        if (saved.length != chunk.length) {
          // A plugin that returns a short/long list would silently corrupt
          // per-track hearts, so fail every waiter in the chunk instead.
          final error = StateError(
            'isSaved returned ${saved.length} values for ${chunk.length} ids',
          );
          for (final id in chunk) {
            batch[id]!.completeError(error);
          }
          continue;
        }
        for (var j = 0; j < chunk.length; j++) {
          batch[chunk[j]]!.complete(saved[j]);
        }
      } catch (e, st) {
        for (final id in chunk) {
          batch[id]!.completeError(e, st);
        }
      }
    }
  }
}
