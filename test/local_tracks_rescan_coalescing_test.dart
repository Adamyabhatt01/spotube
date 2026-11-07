// Guard for audit item C5 ("rescan count per N local-library invalidations").
//
// The scan behind `localTracksProvider` is a full walk of the download + cache
// directories, so the question was whether a burst of invalidations costs one
// walk or one per call. It costs one: Riverpod marks the element dirty and
// flushes once per turn, so no coalescer is needed in the app. The scans here
// are counted through an overridden body because only the invalidation
// semantics are under test — the walk itself is unchanged.
//
// Run: fvm flutter test test/local_tracks_rescan_coalescing_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';

/// A container whose local-library provider counts how often it re-scans.
(ProviderContainer, int Function()) _containerCountingScans() {
  var scans = 0;
  final container = ProviderContainer(
    overrides: [
      localTracksProvider.overrideWith((ref) async {
        scans++;
        return {};
      }),
    ],
  );
  addTearDown(container.dispose);
  // A listener, the way the library page has one: without it there would be
  // nothing to flush and the count would measure laziness instead.
  container.listen(localTracksProvider, (_, __) {});
  return (container, () => scans);
}

void main() {
  test('a same-turn burst of invalidations rescans once', () async {
    final (container, scans) = _containerCountingScans();
    container.read(localTracksProvider);
    await pumpEventQueue();
    expect(scans(), 1);

    for (var i = 0; i < 3; i++) {
      container.invalidate(localTracksProvider);
    }
    container.read(localTracksProvider);
    await pumpEventQueue();
    expect(scans(), 2, reason: 'three invalidations in one turn walked twice');
  });

  test('one delete costs exactly one walk, not two', () async {
    final (container, scans) = _containerCountingScans();
    container.read(localTracksProvider);
    await pumpEventQueue();
    expect(scans(), 1);

    for (var i = 0; i < 3; i++) {
      container.invalidate(localTracksProvider);
      container.read(localTracksProvider);
      await pumpEventQueue();
    }
    expect(
      scans(),
      4,
      reason: 'separate user actions must not queue up extra walks each',
    );
  });
}
