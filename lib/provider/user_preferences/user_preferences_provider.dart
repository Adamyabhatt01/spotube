import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart' as paths;
import 'package:shadcn_flutter/shadcn_flutter.dart' hide join;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/market.dart';
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:open_file/open_file.dart';

typedef UserPreferences = PreferencesTableData;

/// Which platform side effects a preferences transition requires. Pure
/// for testability: the `watchSingle` listener below applies it, so
/// unrelated preference writes (accent, language, …) no longer trigger
/// native calls on every change.
({
  bool titleBarStyle,
  bool audioNormalization,
}) preferencesSideEffects({
  required PreferencesTableData previous,
  required PreferencesTableData next,
}) {
  return (
    titleBarStyle: next.systemTitleBar != previous.systemTitleBar,
    audioNormalization: next.normalizeAudio != previous.normalizeAudio,
  );
}

/// Initialization status of [userPreferencesProvider]. The provider keeps
/// its sync API, but this companion makes the load outcome explicit so
/// pre-load defaults are never mistaken for loaded state: `AsyncLoading`
/// while [UserPreferencesNotifier.loadPreferences] runs, `AsyncData` when
/// the row is live, `AsyncError` when loading failed (degraded — the app
/// stays usable on defaults, and the error is reported, never silent).
final userPreferencesStatusProvider =
    StateProvider<AsyncValue<void>>((_) => const AsyncLoading());

class UserPreferencesNotifier extends Notifier<PreferencesTableData> {
  @override
  build() {
    ref.watch(databaseProvider);
    unawaited(loadPreferences());
    return PreferencesTable.defaults();
  }

  /// Loads (or seeds) the preferences row and subscribes to updates.
  /// Public so tests can drive the real init path against a stub
  /// database. Failures are reported and published as degraded status
  /// instead of leaving permanent silent defaults.
  Future<void> loadPreferences() async {
    final status = ref.read(userPreferencesStatusProvider.notifier);
    try {
      final db = ref.read(databaseProvider);

      var result = await (db.select(db.preferencesTable)
            ..where((tbl) => tbl.id.equals(0)))
          .getSingleOrNull();
      if (result == null) {
        await db.into(db.preferencesTable).insert(
              PreferencesTableCompanion.insert(
                id: const Value(0),
                downloadLocation: Value(await _getDefaultDownloadDirectory()),
              ),
            );
        result = await (db.select(db.preferencesTable)
              ..where((tbl) => tbl.id.equals(0)))
            .getSingle();
      }

      state = result;

      final subscription = (db.select(db.preferencesTable)
            ..where((tbl) => tbl.id.equals(0)))
          .watchSingle()
          .listen((event) async {
        try {
          final previous = state;
          state = event;

          final effects =
              preferencesSideEffects(previous: previous, next: event);
          if (kIsDesktop && effects.titleBarStyle) {
            await windowManager.setTitleBarStyle(
              event.systemTitleBar
                  ? TitleBarStyle.normal
                  : TitleBarStyle.hidden,
            );
          }

          if (effects.audioNormalization) {
            await audioPlayer.setAudioNormalization(event.normalizeAudio);
          }
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      });

      ref.onDispose(() {
        subscription.cancel();
      });

      status.state = const AsyncData(null);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      try {
        status.state = AsyncError(e, stack);
      } catch (_) {
        // Provider already disposed; the report above is the record.
      }
    }
  }

  Future<String> _getDefaultDownloadDirectory() async {
    if (kIsAndroid) return "/storage/emulated/0/Download/Spotube";

    if (kIsMacOS) {
      return join((await paths.getLibraryDirectory()).path, "Caches");
    }

    return paths.getDownloadsDirectory().then((dir) {
      return join(dir!.path, "Spotube");
    });
  }

  Future<void> setData(PreferencesTableCompanion data) async {
    final db = ref.read(databaseProvider);

    final query = db.update(db.preferencesTable)..where((t) => t.id.equals(0));

    await query.write(data);
  }

  Future<void> reset() async {
    final db = ref.read(databaseProvider);

    final query = db.update(db.preferencesTable);

    await query.replace(PreferencesTableCompanion.insert(id: const Value(0)));
  }

  static Future<Directory>? _musicCacheRootDir;

  /// The OS cache directory tracks are cached under.
  ///
  /// Resolved once per process: it derives from OS paths, which do not change
  /// while the app runs, while every caller used to pay a platform-channel
  /// round trip for it — the playback proxy asks twice per track. A failed
  /// resolution is not cached, so a transient path_provider error stays
  /// retryable.
  static Future<Directory> _musicCacheRoot() {
    final cached = _musicCacheRootDir;
    if (cached != null) return cached;

    final future = kIsAndroid
        ? paths.getExternalCacheDirectories().then((dirs) => dirs!.first)
        : paths.getApplicationCacheDirectory();
    _musicCacheRootDir = future;
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) => _musicCacheRootDir = null,
    );
    return future;
  }

  static Future<String> getMusicCacheDir() async {
    final dir = await _musicCacheRoot();
    if (kIsAndroid) {
      // Android can drop an app's external cache directory while it runs, so
      // the recreate stays per call — only the channel round trip is memoized.
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return join(dir.path, 'Cached Tracks');
    }

    return join(dir.path, 'cached_tracks');
  }

  @visibleForTesting
  static void resetMusicCacheDirForTest() => _musicCacheRootDir = null;

  Future<void> openCacheFolder() async {
    try {
      final filePath = await getMusicCacheDir();

      await OpenFile.open(filePath);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  void setThemeMode(ThemeMode mode) {
    setData(PreferencesTableCompanion(themeMode: Value(mode)));
  }

  void setRecommendationMarket(Market country) {
    setData(PreferencesTableCompanion(market: Value(country)));
  }

  void setAccentColorScheme(SpotubeColor color) {
    setData(PreferencesTableCompanion(accentColorScheme: Value(color)));
  }

  void setAlbumColorSync(bool sync) {
    setData(PreferencesTableCompanion(albumColorSync: Value(sync)));
  }

  void setCheckUpdate(bool check) {
    setData(PreferencesTableCompanion(checkUpdate: Value(check)));
  }

  void setDownloadLocation(String downloadDir) {
    if (downloadDir.isEmpty) return;
    setData(PreferencesTableCompanion(downloadLocation: Value(downloadDir)));
  }

  void setLocalLibraryLocation(List<String> localLibraryDirs) {
    setData(
      PreferencesTableCompanion(
        localLibraryLocation: Value(localLibraryDirs),
      ),
    );
  }

  void setLayoutMode(LayoutMode mode) {
    setData(PreferencesTableCompanion(layoutMode: Value(mode)));
  }

  void setCloseBehavior(CloseBehavior behavior) {
    setData(PreferencesTableCompanion(closeBehavior: Value(behavior)));
  }

  void setVolumeControlMode(VolumeControlMode mode) {
    setData(PreferencesTableCompanion(volumeControlMode: Value(mode)));
  }

  void setLastUpdateCheckMs(int atMs) {
    setData(PreferencesTableCompanion(lastUpdateCheckMs: Value(atMs)));
  }

  void setShowSystemTrayIcon(bool show) {
    setData(PreferencesTableCompanion(showSystemTrayIcon: Value(show)));
  }

  void setLocale(Locale locale) {
    setData(PreferencesTableCompanion(locale: Value(locale)));
  }

  void setSearchMode(SearchMode mode) {
    setData(PreferencesTableCompanion(searchMode: Value(mode)));
  }

  void setSkipNonMusic(bool skip) {
    setData(PreferencesTableCompanion(skipNonMusic: Value(skip)));
  }

  void setYoutubeClientEngine(YoutubeClientEngine engine) {
    setData(PreferencesTableCompanion(youtubeClientEngine: Value(engine)));
  }

  void setSourcePriority(List<String> priority) {
    setData(PreferencesTableCompanion(sourcePriority: Value(priority)));
  }

  void setAutoDownloadQuality(bool auto) {
    setData(
      PreferencesTableCompanion(autoDownloadQuality: Value(auto)),
    );
  }

  void setSystemTitleBar(bool isSystemTitleBar) {
    setData(
      PreferencesTableCompanion(
        systemTitleBar: Value(isSystemTitleBar),
      ),
    );
  }

  void setDiscordPresence(bool discordPresence) {
    setData(PreferencesTableCompanion(discordPresence: Value(discordPresence)));
  }

  void setAmoledDarkTheme(bool isAmoled) {
    setData(PreferencesTableCompanion(amoledDarkTheme: Value(isAmoled)));
  }

  void setNormalizeAudio(bool normalize) {
    setData(PreferencesTableCompanion(normalizeAudio: Value(normalize)));
    audioPlayer.setAudioNormalization(normalize);
  }

  void setEndlessPlayback(bool endless) {
    setData(PreferencesTableCompanion(endlessPlayback: Value(endless)));
  }

  void setEnableConnect(bool enable) {
    setData(PreferencesTableCompanion(enableConnect: Value(enable)));
  }

  void setConnectPort(int port) {
    assert(
      port >= -1 && port <= 65535,
      "Port must be between -1 and 65535, got $port",
    );
    setData(PreferencesTableCompanion(connectPort: Value(port)));
  }

  void setCacheMusic(bool cache) {
    setData(PreferencesTableCompanion(cacheMusic: Value(cache)));
  }

  void setThemeTransition(bool enabled) {
    setData(PreferencesTableCompanion(themeTransition: Value(enabled)));
  }

  void setThemeTransitionMs(int milliseconds) {
    setData(PreferencesTableCompanion(themeTransitionMs: Value(milliseconds)));
  }
}

final userPreferencesProvider =
    NotifierProvider<UserPreferencesNotifier, PreferencesTableData>(
  () => UserPreferencesNotifier(),
);
