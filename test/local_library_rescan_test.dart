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
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

class _StubPrefsNotifier extends UserPreferencesNotifier {
  _StubPrefsNotifier(this.stub);

  PreferencesTableData stub;

  @override
  PreferencesTableData build() => stub;
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('local_rescan_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
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
    final prefs = _StubPrefsNotifier(initial);
    final container = ProviderContainer(
      overrides: [userPreferencesProvider.overrideWith(() => prefs)],
    );
    addTearDown(container.dispose);

    var rebuilds = 0;
    container.listen(localTracksProvider, (previous, next) {
      if (next is AsyncData && !next.isLoading) rebuilds++;
    });

    await container.read(localTracksProvider.future);
    await Future.delayed(const Duration(milliseconds: 50));
    expect(rebuilds, 1, reason: 'initial scan must complete');

    // Simulate a drift re-emission: brand-new row instance, a genuinely
    // changed scalar field, and a NEW (but content-equal) list instance —
    // exactly what any unrelated preference write produces today.
    prefs.state = initial.copyWith(
      normalizeAudio: !initial.normalizeAudio,
      localLibraryLocation: List.of(initial.localLibraryLocation),
    );
    await Future.delayed(const Duration(milliseconds: 100));

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
    await Future.delayed(const Duration(milliseconds: 50));

    expect(rebuilds, 2, reason: 'changed library must rescan');
  });
}
