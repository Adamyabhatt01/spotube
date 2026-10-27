import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart' as paths;
import 'package:shadcn_flutter/shadcn_flutter.dart' hide join;
import 'package:spotube/models/color.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/market.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/music_cache_policy.dart';
import 'package:spotube/services/vpn/vpn_mode.dart';
import 'package:spotube/utils/perf_counters.dart';
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
  AudioPlayerPort get _player => ref.read(audioPlayerPortProvider);

  /// The in-flight initial load, exposed so consumers that must not act on
  /// pre-load defaults can await it. Null only when [build] has not run (a
  /// test stub overrides it); `await null` is a no-op. The future never
  /// throws — [loadPreferences] reports and degrades internally.
  Future<void>? get initialLoad => _initialLoad;
  Future<void>? _initialLoad;

  @override
  build() {
    ref.watch(databaseProvider);
    _initialLoad ??= loadPreferences();
    unawaited(_initialLoad!);
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
                // Fresh installs allow real transparency: the theme plugin
                // decides per theme, this is only the user's opt-out. The
                // column default stays false so no migration is needed and
                // existing rows keep their stored choice.
                transparentWindow: const Value(true),
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
            await _player.setAudioNormalization(event.normalizeAudio);
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

  void setPlayerDock(PlayerDock dock) {
    setData(PreferencesTableCompanion(playerDock: Value(dock)));
  }

  void setTransparentWindow(bool enabled) {
    setData(PreferencesTableCompanion(transparentWindow: Value(enabled)));
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

  void setSidebarLibraryOrder(List<String> order) {
    setData(PreferencesTableCompanion(sidebarLibraryOrder: Value(order)));
  }

  void setPinnedPlaylistIds(List<String> ids) {
    setData(PreferencesTableCompanion(pinnedPlaylistIds: Value(ids)));
  }

  void setMainPlaylistOrder(List<String> ids) {
    setData(PreferencesTableCompanion(mainPlaylistOrder: Value(ids)));
  }

  /// Removes [playlistId] from both persisted playlist orders after deletion.
  ///
  /// The two lists stay independent; only the deleted id is removed from each,
  /// preserving the relative order of everything else.
  void removePlaylistFromOrders(String playlistId) {
    final pins = state.pinnedPlaylistIds
        .where((id) => id != playlistId)
        .toList(growable: false);
    final mainOrder = (state.mainPlaylistOrder ?? const <String>[])
        .where((id) => id != playlistId)
        .toList(growable: false);
    setData(
      PreferencesTableCompanion(
        pinnedPlaylistIds: Value(pins),
        mainPlaylistOrder: Value(mainOrder),
      ),
    );
  }

  void setPinnedStationIds(List<String> ids) {
    setData(PreferencesTableCompanion(pinnedStationIds: Value(ids)));
  }

  /// Pins [id] to the sidebar (and, on layouts without one, to the top of the
  /// Playlists page) when absent; unpins it when present.
  ///
  /// New pins go to the front of the pinned block. The most recent pin is the
  /// one the user is looking at, so it is the one that must rank highest —
  /// appending buried it below every older pin on a phone, where the Playlists
  /// page was the only place to see it.
  void togglePinnedPlaylist(String id) {
    final ids = List<String>.of(state.pinnedPlaylistIds);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.insert(0, id);
    }
    setPinnedPlaylistIds(ids);
  }

  /// Pins [favoriteKey] (a station's `provider:id`) to the sidebar when
  /// absent, unpins it when present. Same append-at-end rule as playlists so
  /// a newly pinned station lands at the end of the pinned block.
  void togglePinnedStation(String favoriteKey) {
    final ids = List<String>.of(state.pinnedStationIds);
    if (ids.contains(favoriteKey)) {
      ids.remove(favoriteKey);
    } else {
      ids.add(favoriteKey);
    }
    setPinnedStationIds(ids);
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
    _player.setAudioNormalization(normalize);
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

  /// The opt-in ceiling on the streamed-music cache, in megabytes. `0` is the
  /// default and means no eviction at all — the historic behavior.
  Future<void> setMusicCacheLimitMb(int megabytes) async {
    await setData(
      PreferencesTableCompanion(musicCacheLimitMb: Value(megabytes)),
    );
    // Picking a limit frees the disk right then, instead of whenever the next
    // track happens to finish caching. Passing the new value explicitly
    // because `state` only catches up through the table stream.
    await enforceMusicCacheQuota(limitMb: megabytes);
  }

  /// Trim the music cache down to `musicCacheLimitMb`, least-recently-used
  /// first. Returns what it removed; a no-op when no ceiling is set.
  Future<CacheDiskReport> enforceMusicCacheQuota({
    Set<String> pinnedPaths = const {},
    int? limitMb,
  }) async {
    final limit = limitMb ?? state.musicCacheLimitMb;
    if (limit <= 0) return CacheDiskReport.empty;

    try {
      final report = await enforceCacheQuota(
        dir: Directory(await getMusicCacheDir()),
        limitBytes: limit * 1024 * 1024,
        pinnedPaths: pinnedPaths,
      );
      if (report.didWork) {
        PerfCounters.note('musicCache.evictedFiles', report.removedFiles);
        PerfCounters.note('musicCache.evictedBytes', report.freedBytes);
        AppLogger.log.d(() => 'Music cache trimmed: $report');
      }
      return report;
    } catch (e, stack) {
      // Disk policy must never be the thing that breaks playback.
      AppLogger.reportError(e, stack);
      return CacheDiskReport.empty;
    }
  }

  /// Startup disk hygiene for staged transfers, in three places:
  ///
  ///  1. `.part` files in the music cache that an interrupted playback mirror
  ///     abandoned. Never renamed into the cache, so each is pure waste.
  ///  2. `.part` files in the download folder that a killed chunked download
  ///     abandoned. Staging lives next to the target, which is the user's own
  ///     music folder, so these are up to a whole track each and the library
  ///     scan hides them.
  ///  3. The legacy `.chunk_dl_*` scratch dirs under `<temp>/Spotube`, from
  ///     before downloads wrote positionally. Startup is before this process
  ///     can have a download in flight, so no age window applies to those.
  ///
  /// Every window is [staleMirrorWindow], long enough that a transfer still
  /// running in this or another instance is untouched.
  Future<void> sweepStaleMusicCacheMirrors() async {
    try {
      final report = await sweepIncompleteMirrors(
        dir: Directory(await getMusicCacheDir()),
        olderThan: staleMirrorWindow,
      );
      if (report.didWork) {
        PerfCounters.note('musicCache.sweptFiles', report.removedFiles);
        PerfCounters.note('musicCache.sweptBytes', report.freedBytes);
        AppLogger.log.d(() => 'Abandoned mirror parts removed: $report');
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }

    // Chunked downloads stage next to their *target*, i.e. inside the user's
    // music folder, so a SIGKILL / OOM / power loss mid-download left a file up
    // to the size of a whole track there permanently — the library scan does
    // not even list them (`.part` matches no supported audio type), so the only
    // symptom is the folder quietly filling up until downloads start failing
    // with ENOSPC. Same age window as the mirror sweep, so an in-flight
    // transfer here or in a second instance survives.
    try {
      final report = await sweepIncompleteMirrors(
        dir: Directory(state.downloadLocation),
        olderThan: staleMirrorWindow,
      );
      if (report.didWork) {
        PerfCounters.note('downloads.sweptStagingFiles', report.removedFiles);
        PerfCounters.note('downloads.sweptStagingBytes', report.freedBytes);
        AppLogger.log.d(() => 'Abandoned download staging removed: $report');
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }

    // Chunk staging from before positional writes lived in the temp dir;
    try {
      final report = await sweepStaleChunkStaging();
      if (report.didWork) {
        PerfCounters.note(
          'downloads.sweptChunkDirs',
          report.removedFiles,
        );
        AppLogger.log.d(() => 'Legacy chunk scratch removed: $report');
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  void setThemeTransition(bool enabled) {
    setData(PreferencesTableCompanion(themeTransition: Value(enabled)));
  }

  void setThemeTransitionMs(int milliseconds) {
    setData(PreferencesTableCompanion(themeTransitionMs: Value(milliseconds)));
  }

  void setVpnMode(VpnMode mode) {
    setData(PreferencesTableCompanion(vpnMode: Value(mode)));
  }

  void setVpnConnectionUuid(String? uuid) {
    setData(PreferencesTableCompanion(vpnConnectionUuid: Value(uuid)));
  }

  void setVpnAutoDisconnect(bool autoDisconnect) {
    setData(
      PreferencesTableCompanion(vpnAutoDisconnect: Value(autoDisconnect)),
    );
  }

  void setVpnWaitTimeoutSec(int seconds) {
    final clamped = seconds.clamp(5, 600);
    setData(PreferencesTableCompanion(vpnWaitTimeoutSec: Value(clamped)));
  }

  void setVpnDeviceName(String? deviceName) {
    setData(PreferencesTableCompanion(vpnDeviceName: Value(deviceName)));
  }
}

final userPreferencesProvider =
    NotifierProvider<UserPreferencesNotifier, PreferencesTableData>(
  () => UserPreferencesNotifier(),
);
