// Regression tests for the IsolatedYoutubeExplode lifecycle.
//
// Covered:
//  - concurrent initialize() calls share a single isolate spawn
//    (single-flight; no leaked isolates from the init race).
//  - worker-side failures complete the caller's Future with an error
//    instead of hanging it forever.
//  - dispose clears the singleton so a later initialize respawns
//    cleanly (no use-after-dispose), and disposing an uninitialized
//    engine is a no-op instead of throwing on a null instance.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/youtube_engine/youtube_explode_engine.dart';

void main() {
  tearDown(() {
    if (IsolatedYoutubeExplode.isInitialized) {
      IsolatedYoutubeExplode.instance.dispose();
    }
  });

  test(
    'concurrent initialize calls share a single isolate spawn',
    () async {
      await Future.wait([
        IsolatedYoutubeExplode.initialize(),
        IsolatedYoutubeExplode.initialize(),
        IsolatedYoutubeExplode.initialize(),
      ]).timeout(const Duration(seconds: 60));

      final first = IsolatedYoutubeExplode.instance;

      // A later initialize() must not spawn again for the same instance.
      await IsolatedYoutubeExplode.initialize();
      expect(identical(IsolatedYoutubeExplode.instance, first), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('worker-side errors complete the caller instead of hanging', () async {
    await IsolatedYoutubeExplode.initialize().timeout(
      const Duration(seconds: 60),
    );

    // An empty video id fails inside the worker; the reply must reach
    // the caller as an error. The local timeout guards against the
    // historical failure mode: the Future hanging forever.
    await expectLater(
      IsolatedYoutubeExplode.instance.video('').timeout(
        const Duration(seconds: 30),
      ),
      throwsStateError,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('dispose clears the singleton; next initialize respawns', () async {
    await IsolatedYoutubeExplode.initialize().timeout(
      const Duration(seconds: 60),
    );
    final first = IsolatedYoutubeExplode.instance;

    first.dispose();

    expect(IsolatedYoutubeExplode.isInitialized, isFalse);

    await IsolatedYoutubeExplode.initialize().timeout(
      const Duration(seconds: 60),
    );
    final second = IsolatedYoutubeExplode.instance;
    expect(identical(first, second), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('disposing an uninitialized engine is a no-op', () {
    final engine = YouTubeExplodeEngine();
    // Historically this threw on a null instance.
    engine.dispose();
    expect(IsolatedYoutubeExplode.isInitialized, isFalse);
  });
}
