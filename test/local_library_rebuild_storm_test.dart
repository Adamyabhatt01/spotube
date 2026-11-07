// Regression test for the Local-library rebuild storm (Playlists↔Local
// transition jitter).
//
// UserLocalLibraryPage and LocalFolderItem used to call
// `useFuture(UserPreferencesNotifier.getMusicCacheDir())` inline. That hands
// useFuture a FRESH Future on every build; flutter_hooks 0.20.5 compares by
// identity, re-subscribes, and setState()s when it completes — so the page
// rebuilt forever and every route transition into/out of it stuttered.
// The futures are now memoized, so the pump loop below must settle.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/modules/library/local_folder/local_folder_item.dart';
import 'package:spotube/pages/library/user_local_tracks/user_local_tracks.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

/// Bounded pump loop: with the fresh-future bug, every pump schedules the
/// next frame, so the cap is hit. A healthy widget settles in a few frames.
Future<int> _pumpUntilSettled(WidgetTester tester) async {
  var frames = 0;
  while (WidgetsBinding.instance.hasScheduledFrame && frames < 120) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('local_rebuild_');
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);
    UserPreferencesNotifier.resetMusicCacheDirForTest();
  });

  tearDown(() async {
    UserPreferencesNotifier.resetMusicCacheDirForTest();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  testWidgets('Local library page settles instead of rebuilding forever',
      (tester) async {
    final prefs = StubPrefsNotifier(
      PreferencesTable.defaults().copyWith(downloadLocation: tempRoot.path),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userPreferencesProvider.overrideWith(() => prefs),
          localTracksProvider.overrideWith((ref) async => {}),
          // The page body is now a theme slot; stub the theme away so the
          // test does not spin up the metadata-plugin/Hetu stack (and the
          // Riverpod async-selector teardown it brings).
          themeDefinitionProvider.overrideWith((ref) async => null),
          themeUiProvider.overrideWith((ref) async => null),
        ],
        child: const ShadcnApp(
          localizationsDelegates: [AppLocalizations.delegate],
          home: UserLocalLibraryPage(),
        ),
      ),
    );

    final frames = await _pumpUntilSettled(tester);
    expect(
      frames,
      lessThan(120),
      reason: 'page keeps scheduling rebuilds — useFuture loop is back',
    );

    // Functional check: the cache-dir future resolved, so the cache folder
    // tile rendered next to the downloads tile.
    expect(find.text('Downloads'), findsOne);
    expect(find.textContaining('Cache'), findsOne);
  });

  testWidgets('LocalFolderItem settles instead of rebuilding forever',
      (tester) async {
    final prefs = StubPrefsNotifier(
      PreferencesTable.defaults().copyWith(downloadLocation: tempRoot.path),
    );

    // Same fresh-future bug lived in LocalFolderItem's cache-folder check.
    // Mounted directly so a regression there can't hide behind the page test.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userPreferencesProvider.overrideWith(() => prefs),
          localTracksProvider.overrideWith((ref) async => {}),
          // The page body is now a theme slot; stub the theme away so the
          // test does not spin up the metadata-plugin/Hetu stack (and the
          // Riverpod async-selector teardown it brings).
          themeDefinitionProvider.overrideWith((ref) async => null),
          themeUiProvider.overrideWith((ref) async => null),
        ],
        child: const ShadcnApp(
          localizationsDelegates: [AppLocalizations.delegate],
          home: Padding(
            padding: EdgeInsets.all(8),
            child: LocalFolderItem(folder: '/some/library/folder'),
          ),
        ),
      ),
    );

    final frames = await _pumpUntilSettled(tester);
    expect(
      frames,
      lessThan(120),
      reason: 'folder tile keeps scheduling rebuilds — useFuture loop is back',
    );

    // Functional check: non-special folders render their basename.
    expect(find.text('folder'), findsOne);
  });
}
