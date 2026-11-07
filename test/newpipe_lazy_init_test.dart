import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';

/// The extractor used to initialize eagerly on every start (first deferred
/// step), so every launch paid `NewPipe.init` whether or not any NewPipe
/// call followed. Now the first actual engine call pays it, single-flight.
/// Locked here: no init before first use, one init for concurrent first
/// calls, and a failed init retries instead of poisoning the engine.
void main() {
  Future<List<SearchResultItem>> emptySearch(
    String query,
    List<SearchContentFilters> filters,
  ) async =>
      const <SearchResultItem>[];

  test('no init before first use', () async {
    var inits = 0;
    NewPipeEngine(
      search: emptySearch,
      init: () async => inits++,
    );
    // Allow the event loop to turn in case construction kicked anything off.
    await Future<void>.delayed(Duration.zero);
    expect(inits, 0);
  });

  test('concurrent first calls share one init', () async {
    var inits = 0;
    final engine = NewPipeEngine(
      search: emptySearch,
      init: () async {
        inits++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );
    final results = await Future.wait([
      engine.searchVideos('hello'),
      engine.searchVideos('hello'),
      engine.searchVideos('hello'),
    ]);
    expect(inits, 1);
    for (final r in results) {
      expect(r, isEmpty);
    }
  });

  test('failed init retries on the next call', () async {
    var inits = 0;
    final engine = NewPipeEngine(
      search: emptySearch,
      init: () async {
        inits++;
        if (inits == 1) throw StateError('init blew up');
      },
    );
    await expectLater(engine.searchVideos('hello'), throwsStateError);
    expect(inits, 1);
    expect(await engine.searchVideos('hello'), isEmpty);
    expect(inits, 2);
  });
}
