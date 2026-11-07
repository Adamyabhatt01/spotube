// Regression test for the preference-write → full-library-rescan storm.
//
// The drift-generated PreferencesTableData == compares List<String> fields
// by identity, so EVERY preference write (any field) surfaced
// `localLibraryLocation` as "changed" and rebuilt localTracksProvider —
// rescanning the whole music library. The provider now watches a joined
// string key so equal lists no longer trigger rebuilds.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

/// Pumps the event loop so already-scheduled microtasks and zero-duration
/// timers run to completion. A real regression schedules work; an idle
/// scheduler drains this deterministically without a wall-clock bet.
Future<void> drain([int yields = 200]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Polls [done] until it returns true or the deadline passes, then fails.
Future<void> eventually(
  bool Function() done,
  String what, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (!done()) fail('$what did not happen within $budget');
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('local_rescan_');
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  test('an unrelated preference write does not rescan the local library',
      () async {
    final initial = PreferencesTable.defaults().copyWith(
      downloadLocation: tempRoot.path,
      localLibraryLocation: [tempRoot.path],
    );
    final prefs = StubPrefsNotifier(initial);
    final container = ProviderContainer(
      overrides: [userPreferencesProvider.overrideWith(() => prefs)],
    );
    addTearDown(container.dispose);

    var rebuilds = 0;
    container.listen(localTracksProvider, (previous, next) {
      if (next is AsyncData && !next.isLoading) rebuilds++;
    });

    await container.read(localTracksProvider.future);
    // Wait for the initial scan to land instead of betting on 50ms.
    await eventually(() => rebuilds >= 1, 'initial scan to complete');
    expect(rebuilds, 1, reason: 'initial scan must complete');

    // Simulate a drift re-emission: brand-new row instance, a genuinely
    // changed scalar field, and a NEW (but content-equal) list instance —
    // exactly what any unrelated preference write produces today.
    prefs.state = initial.copyWith(
      normalizeAudio: !initial.normalizeAudio,
      localLibraryLocation: List.of(initial.localLibraryLocation),
    );
    // A spurious rescan schedules work; an equal library location must not.
    await drain();

    expect(
      rebuilds,
      1,
      reason: 'equal library locations must not re-trigger the scan',
    );

    // Sanity: an ACTUAL library change must still rebuild.
    prefs.state = initial.copyWith(
      localLibraryLocation: [tempRoot.path, '${tempRoot.path}/second'],
    );
    await container.read(localTracksProvider.future);
    await eventually(() => rebuilds >= 2, 'changed library to rescan');

    expect(rebuilds, 2, reason: 'changed library must rescan');
  });
}
