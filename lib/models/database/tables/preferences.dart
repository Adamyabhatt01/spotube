part of '../database.dart';

enum LayoutMode {
  compact,
  extended,
  adaptive,
}

enum CloseBehavior {
  minimizeToTray,
  close,
}

/// How much of the desktop bottom player the volume control takes up when it is
/// not being used. Only the wide layouts draw that bar, so this is inert on
/// touch and in compact mode.
enum VolumeControlMode {
  always,
  hover,
  hidden,
}

/// Where the desktop bottom player bar docks.
///
/// `fullWidth` is the historic look: a floating scaffold footer spanning the
/// whole window, painted over the sidebar's bottom edge (which is why the
/// sidebar reserves clearance for it). `docked` stops the bar at the sidebar
/// edge and lays it out under the content only, letting the sidebar run full
/// height. Inert on compact/mobile layouts, which render `PlayerOverlay`.
enum PlayerDock {
  fullWidth,
  docked,
}

enum YoutubeClientEngine {
  ytDlp("yt-dlp"),
  youtubeExplode("YouTubeExplode"),
  newPipe("NewPipe"),
  ytdlpFlutter("ytdlp_flutter");

  final String label;

  const YoutubeClientEngine(this.label);

  bool isAvailableForPlatform() {
    return switch (this) {
      YoutubeClientEngine.youtubeExplode =>
        YouTubeExplodeEngine.isAvailableForPlatform,
      YoutubeClientEngine.ytDlp => YtDlpEngine.isAvailableForPlatform,
      YoutubeClientEngine.newPipe => NewPipeEngine.isAvailableForPlatform,
      YoutubeClientEngine.ytdlpFlutter => true,
    };
  }
}

enum SearchMode {
  youtube._("YouTube"),
  youtubeMusic._("YouTube Music");

  final String label;

  const SearchMode._(this.label);

  factory SearchMode.fromString(String key) {
    return SearchMode.values.firstWhere((e) => e.name == key);
  }
}

class PreferencesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get albumColorSync =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get amoledDarkTheme =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get checkUpdate => boolean().withDefault(const Constant(true))();
  BoolColumn get normalizeAudio =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showSystemTrayIcon =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get systemTitleBar =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get skipNonMusic => boolean().withDefault(const Constant(false))();
  // NOTE: enum defaults are spelled as string literals (not `X.y.name`)
  // on purpose. drift's schema exporter falls back to static analysis for
  // this database (the model transitively imports dart:ui), and the
  // fallback stringifies `.name` expressions without their imports,
  // producing uncompilable snapshots. Literals keep codegen reproducible.
  TextColumn get closeBehavior =>
      textEnum<CloseBehavior>().withDefault(const Constant("close"))();
  TextColumn get accentColorScheme => text()
      .withDefault(const Constant("Slate:0xff64748b"))
      .map(const SpotubeColorConverter())();
  TextColumn get layoutMode =>
      textEnum<LayoutMode>().withDefault(const Constant("adaptive"))();
  TextColumn get locale => text()
      .withDefault(
        const Constant('{"languageCode":"system","countryCode":"system"}'),
      )
      .map(const LocaleConverter())();
  TextColumn get market =>
      textEnum<Market>().withDefault(const Constant("US"))();
  TextColumn get searchMode =>
      textEnum<SearchMode>().withDefault(const Constant("youtube"))();
  TextColumn get downloadLocation => text().withDefault(const Constant(""))();
  TextColumn get localLibraryLocation =>
      text().withDefault(const Constant("")).map(const StringListConverter())();
  TextColumn get themeMode =>
      textEnum<ThemeMode>().withDefault(const Constant("system"))();
  TextColumn get audioSourceId => text().nullable()();
  TextColumn get youtubeClientEngine => textEnum<YoutubeClientEngine>()
      .withDefault(const Constant("youtubeExplode"))();
  BoolColumn get discordPresence =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get endlessPlayback =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enableConnect =>
      boolean().withDefault(const Constant(false))();
  IntColumn get connectPort => integer().withDefault(const Constant(-1))();
  BoolColumn get cacheMusic => boolean().withDefault(const Constant(true))();

  /// Ceiling on the streamed-music cache directory, in megabytes. `0` means
  /// no limit — what every pre-existing install effectively had, so the
  /// default leaves the cache exactly as it was.
  IntColumn get musicCacheLimitMb => integer().withDefault(const Constant(0))();
  TextColumn get sourcePriority =>
      text().withDefault(const Constant("")).map(const StringListConverter())();
  TextColumn get sidebarLibraryOrder =>
      text().withDefault(const Constant("")).map(const StringListConverter())();
  TextColumn get pinnedPlaylistIds =>
      text().withDefault(const Constant("")).map(const StringListConverter())();
  TextColumn get pinnedStationIds =>
      text().withDefault(const Constant("")).map(const StringListConverter())();

  /// Order of the Playlists section, independent of the sidebar pins.
  ///
  /// Null is the migration sentinel: v28 seeds it once from
  /// [pinnedPlaylistIds] so existing users keep their pinned-first layout.
  /// An intentionally empty list is stored as `""` (not null), so it is never
  /// repopulated on a re-entered migration step.
  TextColumn get mainPlaylistOrder =>
      text().nullable().map(const StringListConverter())();
  BoolColumn get autoDownloadQuality =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get themeTransition =>
      boolean().withDefault(const Constant(false))();
  IntColumn get themeTransitionMs =>
      integer().withDefault(const Constant(250))();
  TextColumn get volumeControlMode =>
      textEnum<VolumeControlMode>().withDefault(const Constant("always"))();
  TextColumn get playerDock =>
      textEnum<PlayerDock>().withDefault(const Constant("fullWidth"))();
  IntColumn get lastUpdateCheckMs => integer().withDefault(const Constant(0))();
  // Automatic VPN (user-owned system connection, opt-in). Disabled by
  // default: zero behavioral change unless the user selects a mode AND a
  // system connection. Enum default is a string literal on purpose (see
  // the note on closeBehavior above).
  TextColumn get vpnMode =>
      textEnum<VpnMode>().withDefault(const Constant("disabled"))();
  TextColumn get vpnConnectionUuid => text().nullable()();
  BoolColumn get vpnAutoDisconnect =>
      boolean().withDefault(const Constant(true))();
  IntColumn get vpnWaitTimeoutSec =>
      integer().withDefault(const Constant(60))();
  // Share-only tunnel device (e.g. a provider app's tun interface).
  // Alternative to [vpnConnectionUuid]: when set (and no UUID is set), the
  // manager waits for and shares this live device without ever activating
  // or deactivating anything. Null by default.
  TextColumn get vpnDeviceName => text().nullable()();
  // Real-transparency user veto (opt-out, fresh installs default on).
  // The active theme plugin requests real transparency with
  // `background.transparent == true`; this setting only allows the user to
  // refuse it, forcing the painted (fake) backdrop instead. Column default
  // stays false on purpose — fresh seeds write true explicitly (see
  // `UserPreferencesNotifier.loadPreferences` and `defaults()` below), so
  // no migration is needed and existing rows keep their stored choice.
  BoolColumn get transparentWindow =>
      boolean().withDefault(const Constant(false))();

  static PreferencesTableData defaults() {
    return PreferencesTableData(
      id: 0,
      albumColorSync: true,
      amoledDarkTheme: false,
      checkUpdate: true,
      normalizeAudio: false,
      showSystemTrayIcon: false,
      systemTitleBar: false,
      skipNonMusic: false,
      closeBehavior: CloseBehavior.close,
      accentColorScheme: SpotubeColor(Colors.slate.toARGB32(), name: "Slate"),
      layoutMode: LayoutMode.adaptive,
      locale: const Locale("system", "system"),
      market: Market.US,
      searchMode: SearchMode.youtube,
      downloadLocation: "",
      localLibraryLocation: [],
      themeMode: ThemeMode.system,
      audioSourceId: null,
      youtubeClientEngine: kIsIOS
          ? YoutubeClientEngine.youtubeExplode
          : YoutubeClientEngine.newPipe,
      discordPresence: true,
      endlessPlayback: true,
      enableConnect: false,
      cacheMusic: true,
      musicCacheLimitMb: 0,
      connectPort: -1,
      sourcePriority: [],
      sidebarLibraryOrder: [],
      pinnedPlaylistIds: [],
      pinnedStationIds: [],
      mainPlaylistOrder: null,
      autoDownloadQuality: false,
      themeTransition: false,
      themeTransitionMs: 250,
      volumeControlMode: VolumeControlMode.always,
      playerDock: PlayerDock.fullWidth,
      lastUpdateCheckMs: 0,
      vpnMode: VpnMode.disabled,
      vpnConnectionUuid: null,
      vpnAutoDisconnect: true,
      vpnWaitTimeoutSec: 60,
      vpnDeviceName: null,
      transparentWindow: true,
    );
  }
}
