import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/crossfade_duration_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/sleep_timer_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/saved_track_likes.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/theme_ui/artwork_palette.dart';
import 'package:spotube/services/theme_ui/artwork_palette_provider.dart';

/// A point-in-time view of the data a theme UI may bind to.
///
/// The map keeps the raw values (a [Duration], a bool, a number) so a
/// `conditional` can compare them, while [display] is the human-readable form
/// a `text` node shows. Keeping the two apart matters: `player.loop` compares
/// as `loop`/`single`/`none`, but reads as `ALL`/`ONE`/`OFF` in the UI.
class ThemeUiBindings {
  final Map<String, Object?> values;

  const ThemeUiBindings(this.values);

  Object? raw(String? name) => name == null ? null : values[name];

  bool isTruthy(String? name) {
    final value = raw(name);
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }

  bool matches(String? name, Object? expected) {
    final value = raw(name);
    if (expected == null) return isTruthy(name);
    if (expected is bool) return isTruthy(name) == expected;
    if (expected is num && value is num) return value == expected;
    if (expected is String) {
      if (value is bool) return value.toString() == expected;
      if (value is num) return value.toString() == expected;
      return value == expected;
    }
    return value == expected;
  }

  String display(String? name) {
    final value = raw(name);
    return switch (value) {
      null => '',
      Duration duration => formatDuration(duration),
      DateTime time => '${_two(time.hour)}:${_two(time.minute)}',
      bool boolean => boolean ? 'ON' : 'OFF',
      double number => name == 'player.volume'
          ? '${(number * 100).round()}%'
          : _trimNumber(number),
      num number => _trimNumber(number.toDouble()),
      String text => switch (name) {
          'player.loop' => switch (text) {
              'loop' => 'ALL',
              'single' => 'ONE',
              'none' => 'OFF',
              _ => text.toUpperCase(),
            },
          _ => text,
        },
      _ => value.toString(),
    };
  }
}

/// Bindings a page publishes to the slots it contains.
///
/// Slot content is rendered deep inside the page's tree, so passing the map
/// explicitly through every intermediate widget would couple host widgets to
/// the theme system. The scope is read by [ThemeUiHost]'s slot builder and
/// merged over the app-wide bindings; it is empty on every host-owned page.
class ThemeUiPageBindings extends InheritedWidget {
  final Map<String, Object?> values;

  const ThemeUiPageBindings({
    required this.values,
    required super.child,
    super.key,
  });

  static Map<String, Object?>? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeUiPageBindings>()
        ?.values;
  }

  /// The page's bindings without subscribing the caller.
  ///
  /// Actions run outside build, where `dependOnInheritedWidgetOfExactType`
  /// is not allowed. A collection play action reads the track list through
  /// this, once, at tap time.
  static Map<String, Object?>? read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<ThemeUiPageBindings>()?.values;
  }

  @override
  bool updateShouldNotify(ThemeUiPageBindings oldWidget) {
    return oldWidget.values != values;
  }
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${_two(seconds)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _trimNumber(double value) {
  if (!value.isFinite) return '0';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The latest whole-second position tick. Auto-disposed so a theme with no
/// position-bound UI does not keep a listener after its slots unmount.
final themePlayerPositionProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.read(audioPlayerPortProvider).positionTickStream,
);

final themePlayerDurationProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.read(audioPlayerPortProvider).durationStream,
);

/// The live playback rate. media_kit's rate stream replays nothing on listen,
/// so the current value is seeded first — a theme's speed slider then reads
/// the truth instead of resetting to 1.0 on rebuild.
final themePlayerSpeedProvider = StreamProvider.autoDispose<double>(
  (ref) async* {
    final port = ref.read(audioPlayerPortProvider);
    yield port.speed;
    yield* port.speedStream;
  },
);

/// Package metadata is a platform-channel call; one lookup per session is
/// enough, and an unavailable channel (tests, a stripped build) is "".
final themeAppVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '';
  }
});

/// Whether the backend is buffering the current source, seeded with the port's
/// current state so the first frame has the truth. A theme with no buffering
/// display does not keep this listener.
final themePlayerBufferingProvider = StreamProvider.autoDispose<bool>(
  (ref) async* {
    final port = ref.read(audioPlayerPortProvider);
    yield port.isBuffering;
    yield* port.bufferingStream;
  },
);

/// Whether the current source reached the end. Seeded from the port;
/// `completedStream` flips it true and a fresh `playingStream` event clears
/// it, so a theme that shows "replay" after completion tracks the transport.
final themePlayerCompletedProvider = StreamProvider.autoDispose<bool>(
  (ref) async* {
    final port = ref.read(audioPlayerPortProvider);
    yield await port.isCompleted;
    yield* port.completedStream.asyncMap((_) async => true);
  },
);

/// The most recent backend playback error, or empty string when no error has
/// been reported in this session.
final themePlayerErrorProvider = StreamProvider.autoDispose<String>(
  (ref) async* {
    final port = ref.read(audioPlayerPortProvider);
    yield '';
    yield* port.errorStream;
  },
);

/// Live per-track download progress as a fraction (0.0–1.0), keyed by track
/// id. Only downloading tasks appear. The bytes arrive on each task's
/// `downloadedBytesStream`, so this provider subscribes per downloading task
/// and drops out when the task finishes.
final downloadProgressProvider =
    AutoDisposeNotifierProvider<DownloadProgressTracker, Map<String, double>>(
  DownloadProgressTracker.new,
);

class DownloadProgressTracker extends AutoDisposeNotifier<Map<String, double>> {
  final _subscriptions = <String, StreamSubscription<int>>{};
  bool _disposed = false;

  @override
  Map<String, double> build() {
    final tasks = ref.watch(downloadManagerProvider);
    ref.onDispose(() {
      _disposed = true;
      _cancelAll();
    });
    final downloading = {
      for (final task in tasks)
        if (task.status == DownloadStatus.downloading) task.track.id: task,
    };
    for (final id in _subscriptions.keys
        .where((id) => !downloading.containsKey(id))
        .toList()) {
      _subscriptions.remove(id)?.cancel();
    }
    for (final entry in downloading.entries) {
      if (_subscriptions.containsKey(entry.key)) continue;
      final task = entry.value;
      final total = task.totalSizeBytes ?? 0;
      _subscriptions[entry.key] = task.downloadedBytesStream.listen(
        (bytes) {
          if (_disposed) return;
          state = {
            ...state,
            if (total > 0)
              entry.key: (bytes / total).clamp(0.0, 1.0).toDouble(),
          };
        },
      );
      if (total > 0) {
        state = {...state, entry.key: 0.0};
      }
    }
    return state;
  }

  void _cancelAll() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// Demand for the current document, memoized by Riverpod.
///
/// Recomputes on a theme switch and on a `plugin` action that replaces the
/// UI; every slot in that document then shares one scan.
final themeUiBindingDemandProvider = Provider<ThemeUiBindingDemand>((ref) {
  final ui = ref.watch(effectiveThemeUiProvider);
  return ThemeUiBindingDemand.scan(ui);
});

const themeUiDefaultQueryScope = 'default';

/// Per-scope search text written by `setQuery`/`clearQuery`.
///
/// Session-scoped on purpose: a query is view state, not a preference. The
/// flat key map lets two search fields (a sidebar and a page) keep separate
/// text without inventing a provider per surface.
class ThemeUiQueryState extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const <String, String>{};

  void set(String scope, String value) {
    final key = scope.isEmpty ? themeUiDefaultQueryScope : scope;
    state = {...state, key: value};
  }

  void clear(String scope) {
    final key = scope.isEmpty ? themeUiDefaultQueryScope : scope;
    if (!state.containsKey(key)) return;
    final next = {...state}..remove(key);
    state = next;
  }
}

final themeUiQueryProvider =
    NotifierProvider<ThemeUiQueryState, Map<String, String>>(
  ThemeUiQueryState.new,
);

/// Ephemeral theme UI state written by `setLocal`/`toggleLocal`/`clearLocal`.
/// Values are published as `state.<key>`. Session-scoped (never persisted),
/// namespaced per selected theme plugin like `setting.*` so one theme's
/// toggles do not leak into another's UI.
final themeUiLocalStateProvider =
    NotifierProvider<ThemeUiLocalState, Map<String, Object?>>(
  ThemeUiLocalState.new,
);

/// Like [themeUiQueryProvider], but open-ended values rather than search
/// text: a dialog can bind `openBind: "state.dialogOpen"` and close it with a
/// `setLocal` action the same way a `setting.*`-backed control does today,
/// without the value surviving the session.
class ThemeUiLocalState extends Notifier<Map<String, Object?>> {
  ThemeSettingsNamespace? _namespace;

  @override
  Map<String, Object?> build() {
    _namespace = ref.watch(themeSettingsNamespaceProvider);
    return const <String, Object?>{};
  }

  /// Scoped to the active theme so a state key from a previous theme cannot
  /// be mistaken for one of the current theme's keys.
  String _scopeKey(String key) {
    final namespace = _namespace;
    return namespace == null
        ? 'none.$key'
        : '${namespace.author}.${namespace.name}.$key';
  }

  void set(String key, Object? value) {
    final scoped = _scopeKey(key);
    if (value == null) {
      if (!state.containsKey(scoped)) return;
      state = {...state}..remove(scoped);
      return;
    }
    state = {...state, scoped: value};
  }

  void toggle(String key) {
    final current = state[_scopeKey(key)];
    set(key, !_valueIsTruthy(current));
  }

  void clear(String? key) {
    if (key == null) {
      state = const <String, Object?>{};
      return;
    }
    final scoped = _scopeKey(key);
    if (!state.containsKey(scoped)) return;
    state = {...state}..remove(scoped);
  }
}

/// Theme-owned settings toggled through `setSetting`/`toggleSetting`.
///
/// Values are published as `setting.<key>`. The namespace is the selected
/// theme plugin's `theme.<author>.<name>.` prefix, so switching themes reads a
/// different map and does not leak one theme's toggles into another's UI.
typedef ThemeSettingsNamespace = ({String author, String name});

final themeSettingsNamespaceProvider = Provider<ThemeSettingsNamespace?>((ref) {
  final plugin = ref.watch(
    metadataPluginsProvider.select(
      (state) => state.valueOrNull?.defaultThemePluginConfig,
    ),
  );
  if (plugin == null) return null;
  return (author: plugin.author, name: plugin.name);
});

class ThemeUiSettingsState extends Notifier<Map<String, Object?>> {
  ThemeSettingsNamespace? _namespace;

  @override
  Map<String, Object?> build() {
    final namespace = ref.watch(themeSettingsNamespaceProvider);
    _namespace = namespace;
    if (namespace == null || !KVStoreService.isInitialized) {
      return const <String, Object?>{};
    }
    return KVStoreService.themeSettings(namespace.author, namespace.name);
  }

  void set(String key, Object? value) {
    if (value == null) {
      if (!state.containsKey(key)) return;
      final next = {...state}..remove(key);
      state = next;
    } else {
      state = {...state, key: value};
    }
    unawaited(_persist(key, value));
  }

  void toggle(String key) {
    final current = state[key];
    set(key, current is bool ? !current : !_valueIsTruthy(current));
  }

  void reset() {
    state = const <String, Object?>{};
    final namespace = _namespace;
    if (namespace == null || !KVStoreService.isInitialized) return;
    unawaited(
      KVStoreService.clearThemeSettings(namespace.author, namespace.name),
    );
  }

  Future<void> _persist(String key, Object? value) async {
    final namespace = _namespace;
    if (namespace == null || !KVStoreService.isInitialized) return;
    await KVStoreService.setThemeSetting(
      namespace.author,
      namespace.name,
      key,
      value,
    );
  }
}

bool _valueIsTruthy(Object? value) {
  return switch (value) {
    null => false,
    bool boolean => boolean,
    num number => number != 0,
    String text => text.isNotEmpty,
    _ => true,
  };
}

final themeUiSettingsProvider =
    NotifierProvider<ThemeUiSettingsState, Map<String, Object?>>(
  ThemeUiSettingsState.new,
);

/// Builds the binding snapshot for the current frame.
///
/// `brightness` and `themeMode` come from the widget tree because they are
/// presentation state, not provider state. `demand` is the document scan:
/// a provider is watched only when the theme references one of its bindings,
/// so a theme that never draws the library does not open the saved lists,
/// and a theme with no position display does not subscribe to the ticker.
ThemeUiBindings buildThemeUiBindings(
  WidgetRef ref, {
  required Brightness brightness,
  required String themeMode,
  ThemeUiBindingDemand? demand,
  ThemeLayout? layout,
}) {
  final wants = demand ?? ThemeUiBindingDemand.all;
  final values = <String, Object?>{};
  final now = DateTime.now();

  // ---------------------------------------------------------------- app
  if (wants.wants('app.version')) {
    values['app.version'] =
        ref.watch(themeAppVersionProvider).asData?.value ?? '';
  }
  if (wants.wants('app.brightness')) values['app.brightness'] = brightness.name;
  if (wants.wants('app.themeMode')) values['app.themeMode'] = themeMode;
  final wantsShell =
      wants.wants('app.sidebarCollapsed') || wants.wants('app.asideOpen');
  if (wantsShell) {
    // One watch for both flags: they live on the same row and a toggle of
    // either should rebuild the theme chrome that binds them.
    final prefs = ref.watch(
      userPreferencesProvider.select((p) => (p.sidebarCollapsed, p.asideOpen)),
    );
    if (wants.wants('app.sidebarCollapsed')) {
      values['app.sidebarCollapsed'] = prefs.$1;
    }
    if (wants.wants('app.asideOpen')) values['app.asideOpen'] = prefs.$2;
  }
  if (wants.wants('app.greeting')) {
    values['app.greeting'] = greetingFor(now);
  }
  final wantsAppPins = wants.wants('app.pinnedPlaylistIds') ||
      wants.wants('app.pinnedStationIds');
  if (wantsAppPins) {
    final prefs = ref.watch(userPreferencesProvider);
    if (wants.wants('app.pinnedPlaylistIds')) {
      values['app.pinnedPlaylistIds'] = prefs.pinnedPlaylistIds;
    }
    if (wants.wants('app.pinnedStationIds')) {
      values['app.pinnedStationIds'] = prefs.pinnedStationIds;
    }
  }
  if (wants.wants('clock.now')) values['clock.now'] = now;

  if (wants.wants('item.liked')) {
    final likes = ref.watch(savedTrackLikesProvider);
    final savedTracks =
        ref.watch(metadataPluginSavedTracksProvider).asData?.value.items ??
            const <SpotubeTrackObject>[];
    final savedTrackIds = <String>{
      for (final track in savedTracks) track.id,
      for (final entry in likes.entries)
        if (entry.value) entry.key,
    };
    values['library.savedTrackIds'] = savedTrackIds;
  }

  // ------------------------------------------------------------- player
  final wantsPlayer = wants.wantsNamespace('player');
  final wantsQueue = wants.wantsNamespace('queue');
  final wantsPalette = wants.wantsNamespace('palette');
  final wantsAudio = wants.wantsNamespace('audio');

  final player = wantsPlayer || wantsQueue || wantsPalette
      ? ref.watch(audioPlayerProvider)
      : null;

  if (wantsPlayer) {
    final track = player!.activeTrack;
    final artwork = track?.album.images.asUrlString(
          placeholder: ImagePlaceholder.albumArt,
        ) ??
        placeholderUrlMap[ImagePlaceholder.albumArt]!;
    values['player.trackId'] = track?.id ?? '';
    values['player.title'] = track?.name ?? '';
    values['player.artist'] =
        track?.artists.map((artist) => artist.name).join(', ') ?? '';
    values['player.album'] = track?.album.name ?? '';
    values['player.artwork'] = artwork;
    values['player.playing'] = player.playing;
    if (wants.wants('player.liked')) {
      values['player.liked'] = track != null &&
          (ref.watch(savedTrackLikesProvider)[track.id] ??
              ref
                  .watch(metadataPluginIsSavedTrackProvider(track.id))
                  .asData
                  ?.value ??
              false);
    }
    values['player.loop'] = player.loopMode.name;
    values['player.shuffled'] = player.shuffled;
    if (wants.wants('player.speed')) {
      values['player.speed'] = _resolvedSpeed(ref);
    }
  }
  if (wants.wants('player.volume') || wants.wants('player.muted')) {
    final volume = ref.watch(volumeProvider);
    if (wants.wants('player.volume')) values['player.volume'] = volume;
    if (wants.wants('player.muted')) values['player.muted'] = volume <= 0;
  }
  if (wants.wants('player.position')) {
    values['player.position'] =
        ref.watch(themePlayerPositionProvider).asData?.value ??
            ref.read(audioPlayerPortProvider).position;
  }
  if (wants.wants('player.duration')) {
    values['player.duration'] =
        ref.watch(themePlayerDurationProvider).asData?.value ??
            ref.read(audioPlayerPortProvider).duration;
  }

  // -------------------------------------------------------------- queue
  if (wantsQueue) {
    final tracks = player!.tracks;
    values['queue.tracks'] = themeQueueTracks(tracks);
    values['queue.count'] = tracks.length;
    values['queue.currentIndex'] = player.currentIndex;
    final nextIndex = player.currentIndex + 1;
    values['queue.next'] = nextIndex >= 0 && nextIndex < tracks.length
        ? themeQueueTrack(tracks[nextIndex])
        : null;
  }

  // ------------------------------------------------------------ palette
  if (wantsPalette) {
    // Rebuilds once when a palette this theme asked for is stored.
    ref.watch(themeUiPaletteRevisionProvider);
    final cache = ref.read(themeUiPaletteCacheProvider);
    final artwork = player?.activeTrack?.album.images.asUrlString(
      placeholder: ImagePlaceholder.albumArt,
    );
    ArtworkPalette? palette;
    if (artwork != null && artwork.startsWith('http')) {
      palette = cache[artwork];
      if (palette == null) unawaited(cache.load(artwork));
    }
    values.addAll((palette ?? ArtworkPalette.neutral).bindings);
  }

  // ------------------------------------------------------------- user
  if (wants.wantsNamespace('user')) {
    final user = ref.watch(metadataPluginUserProvider).asData?.value;
    values['user.name'] = user?.name ?? '';
    values['user.avatar'] = user?.images.asUrlString(
          placeholder: ImagePlaceholder.artist,
        ) ??
        placeholderUrlMap[ImagePlaceholder.artist]!;
  }

  // ------------------------------------------------------------ theme
  if (wants.wantsNamespace('theme')) {
    final config = ref.watch(
      metadataPluginsProvider
          .select((state) => state.asData?.value.defaultThemePluginConfig),
    );
    values['theme.id'] =
        config == null ? '' : '${config.author}::${config.name}';
    values['theme.name'] = config?.name ?? '';
    values['theme.version'] = config?.version ?? '';
  }

  // ---------------------------------------------------------- settings
  if (wants.wantsNamespace('setting')) {
    for (final entry in ref.watch(themeUiSettingsProvider).entries) {
      values['setting.${entry.key}'] = entry.value;
    }
  }

  // -------------------------------------------------------- ephemeral
  if (wants.wantsNamespace('state')) {
    final namespace = ref.watch(themeSettingsNamespaceProvider);
    final prefix =
        namespace == null ? 'none.' : '${namespace.author}.${namespace.name}.';
    for (final entry in ref.watch(themeUiLocalStateProvider).entries) {
      if (!entry.key.startsWith(prefix)) continue;
      values['state.${entry.key.substring(prefix.length)}'] = entry.value;
    }
  }

  // ------------------------------------------------------------- query
  if (wants.wantsNamespace('search')) {
    final queries = ref.watch(themeUiQueryProvider);
    final defaultQuery = queries[themeUiDefaultQueryScope] ?? '';
    values['search.query'] = defaultQuery;
    values['search.hasQuery'] = defaultQuery.trim().isNotEmpty;
    for (final entry in queries.entries) {
      if (entry.key == themeUiDefaultQueryScope) continue;
      values['search.${entry.key}.query'] = entry.value;
    }
  }

  // --------------------------------------------------- player transport
  if (wants.wants('player.buffering')) {
    values['player.buffering'] =
        ref.watch(themePlayerBufferingProvider).asData?.value ??
            ref.read(audioPlayerPortProvider).isBuffering;
  }
  if (wants.wants('player.completed')) {
    values['player.completed'] =
        ref.watch(themePlayerCompletedProvider).asData?.value ?? false;
  }
  if (wants.wants('player.error')) {
    values['player.error'] =
        ref.watch(themePlayerErrorProvider).asData?.value ?? '';
  }

  // ---------------------------------------------------------- downloads
  if (wants.wantsNamespace('downloads')) {
    final tasks = ref.watch(downloadManagerProvider);
    values['downloads.active'] =
        tasks.where((task) => task.status == DownloadStatus.downloading).length;
    values['downloads.queued'] =
        tasks.where((task) => task.status == DownloadStatus.queued).length;
    values['downloads.failed'] = tasks
        .where(
          (task) =>
              task.status == DownloadStatus.failed ||
              task.status == DownloadStatus.canceled,
        )
        .length;
    values['downloads.completed'] =
        tasks.where((task) => task.status == DownloadStatus.completed).length;
    if (wants.wants('downloads.progress')) {
      values['downloads.progress'] = ref.watch(downloadProgressProvider);
    }
  }

  // ------------------------------------------------------------ lyrics
  if (wants.wantsNamespace('lyrics')) {
    final track = player?.activeTrack;
    values['lyrics.available'] = false;
    values['lyrics.synced'] = false;
    values['lyrics.line'] = '';
    if (track is SpotubeFullTrackObject) {
      final lyrics = ref.watch(syncedLyricsProvider(track)).asData?.value;
      final position = ref.watch(themePlayerPositionProvider).asData?.value ??
          ref.read(audioPlayerPortProvider).position;
      if (lyrics != null) {
        values['lyrics.available'] = lyrics.hasContent;
        values['lyrics.synced'] = lyrics.isSynced;
        values['lyrics.line'] = _currentLyricLine(lyrics, position);
      }
    }
  }

  // ------------------------------------------------------------- radio
  if (wants.wantsNamespace('radio')) {
    final radio = ref.watch(radioPlaybackControllerProvider);
    values['radio.active'] = radio.isRadio;
    values['radio.playing'] = radio.playing;
    values['radio.buffering'] = radio.buffering;
    values['radio.station'] = radio.activeStation?.name ?? '';
    values['radio.liveTitle'] = radio.liveTitle ?? '';
    values['radio.error'] = radio.error?.toString() ?? '';
  }

  // ----------------------------------------------------------- connect
  if (wants.wantsNamespace('connect')) {
    final services = ref.watch(connectClientsProvider).asData?.value.services;
    final clients = services == null
        ? const <String>[]
        : [for (final service in services) service.name];
    values['connect.clients'] = clients;
    values['connect.clientCount'] = clients.length;
    values['connect.available'] = clients.isNotEmpty;
  }

  // ----------------------------------------------------------- library
  if (wants.wants('library.pinTargets')) {
    values['library.pinTargets'] = themePinTargets(layout);
  }
  final wantsPlaylists = wants.wants('library.playlists');
  final wantsPins = wants.wants('library.pins');
  final wantsAlbums = wants.wants('library.albums');
  final wantsArtists = wants.wants('library.artists');
  final wantsFolders = wants.wants('library.folders');
  final wantsCounts = wants.wants('library.counts');

  if (wantsPlaylists ||
      wantsPins ||
      wantsAlbums ||
      wantsArtists ||
      wantsFolders ||
      wantsCounts) {
    final preferences = (wantsPins || wantsFolders || wantsCounts)
        ? ref.watch(userPreferencesProvider)
        : null;

    final playlists = (wantsPlaylists || wantsPins || wantsCounts)
        ? (ref
                .watch(metadataPluginSavedPlaylistsProvider)
                .asData
                ?.value
                .items ??
            const <SpotubeSimplePlaylistObject>[])
        : const <SpotubeSimplePlaylistObject>[];
    final albums = (wantsAlbums || wantsCounts)
        ? (ref.watch(metadataPluginSavedAlbumsProvider).asData?.value.items ??
            const <SpotubeSimpleAlbumObject>[])
        : const <SpotubeSimpleAlbumObject>[];
    final artists = (wantsArtists || wantsCounts)
        ? (ref.watch(metadataPluginSavedArtistsProvider).asData?.value.items ??
            const <SpotubeFullArtistObject>[])
        : const <SpotubeFullArtistObject>[];
    final savedTracks = wantsCounts
        ? (ref.watch(metadataPluginSavedTracksProvider).asData?.value.items ??
            const <SpotubeTrackObject>[])
        : const <SpotubeTrackObject>[];
    final pinnedIds = preferences == null
        ? const <String>{}
        : preferences.pinnedPlaylistIds.toSet();
    final targetPins = (wantsPins || wantsPlaylists || wantsCounts)
        ? ref.watch(themePinsProvider)
        : const <String, List<String>>{};
    final allPinnedIds = {
      ...pinnedIds,
      for (final ids in targetPins.values) ...ids,
    };
    final folders = preferences?.localLibraryLocation ?? const <String>[];

    if (wantsPlaylists) {
      values['library.playlists'] =
          themeLibraryPlaylists(playlists, allPinnedIds);
    }
    if (wantsAlbums) values['library.albums'] = themeLibraryAlbums(albums);
    if (wantsArtists) {
      values['library.artists'] = themeLibraryArtists(artists);
    }
    if (wantsFolders) {
      values['library.folders'] = themeLibraryFolders(folders);
    }
    if (wantsPins) {
      final stationPins = preferences?.pinnedStationIds ?? const <String>[];
      values['library.pins'] = themeLibraryPins(
        playlists,
        pinnedIds,
        targetPins: targetPins,
        stationPins: stationPins,
        favorites: ref.watch(radioFavoritesProvider).asData?.value ??
            const <RadioStation>[],
        history: ref.watch(radioHistoryProvider).asData?.value ??
            const <RadioStation>[],
      );
    }
    if (wantsCounts) {
      values['library.counts'] = {
        'playlists': playlists.length,
        'pins': (preferences?.pinnedPlaylistIds.length ?? 0) +
            targetPins.values.fold<int>(0, (sum, ids) => sum + ids.length) +
            (preferences?.pinnedStationIds.length ?? 0),
        'albums': albums.length,
        'artists': artists.length,
        'folders': folders.length,
        'tracks': savedTracks.length,
      };
    }
  }

  // ------------------------------------------------------ audio effects
  if (wantsAudio) {
    // Only the EQ-derived facts live in the preferences row; the rest are
    // per-effect providers subscribed on demand so a theme that binds just
    // `audio.bass` costs no sleep-timer or crossfade listener.
    if (wants.wants('audio.bass') ||
        wants.wants('audio.treble') ||
        wants.wants('audio.normalization')) {
      final preferences = ref.watch(userPreferencesProvider);
      if (wants.wants('audio.bass') || wants.wants('audio.treble')) {
        final gains = EqualizerSettings.normalizeGains(
          preferences.equalizerGains,
        );
        values['audio.bass'] = gains.first;
        values['audio.treble'] = gains.last;
      }
      if (wants.wants('audio.normalization')) {
        values['audio.normalization'] = preferences.normalizeAudio;
      }
    }
    if (wants.wants('audio.crossfade')) {
      values['audio.crossfade'] = ref.watch(crossfadeProvider);
    }
    if (wants.wants('audio.sleepTimer')) {
      final remaining = ref.watch(sleepTimerProvider);
      values['audio.sleepTimer'] = remaining?.inMinutes ?? 0;
    }
    if (wants.wants('audio.speed')) {
      values['audio.speed'] = _resolvedSpeed(ref);
    }
  }

  return ThemeUiBindings(values);
}

/// The live playback rate: the streamed value when known, else the port's
/// current speed. Never null, so a bound slider has no null branch.
double _resolvedSpeed(WidgetRef ref) =>
    ref.watch(themePlayerSpeedProvider).asData?.value ??
    ref.read(audioPlayerPortProvider).speed;

/// Lifts an explicit palette map, then a cached artwork palette, over
/// [bindings].
///
/// Precedence is the nearest artwork scope: an `item.palette`/
/// `collection.palette` map the page supplied wins, then the palette of the
/// scope's artwork, then whatever the player scope already put in place.
/// Missing keys are left alone, so a page that only overrides `dominant`
/// still inherits the rest from the player.
ThemeUiBindings withArtworkPalette(
  ThemeUiBindings bindings, {
  required ArtworkPalette? Function(String url) paletteFor,
  void Function(String url)? request,
}) {
  final values = <String, Object?>{...bindings.values};
  final explicit = _scopedPalette(bindings.values);
  final artwork = _scopedArtwork(bindings.values);
  final derived = artwork == null ? null : paletteFor(artwork);

  if (derived == null && artwork != null && request != null) {
    request(artwork);
  }

  final palette = derived;
  if (palette != null) {
    for (final entry in palette.bindings.entries) {
      values[entry.key] = entry.value;
    }
  }
  if (explicit != null) {
    for (final entry in explicit.entries) {
      values['palette.${entry.key}'] = entry.value;
    }
  }
  return ThemeUiBindings(values);
}

Map<String, Object?>? _scopedPalette(Map<String, Object?> values) {
  for (final key in const [
    'item.palette',
    'collection.palette',
    'artist.palette',
    'playlist.palette',
    'album.palette',
    'palette',
  ]) {
    final raw = values[key];
    if (raw is Map && raw.isNotEmpty) return raw.cast<String, Object?>();
  }
  return null;
}

String? _scopedArtwork(Map<String, Object?> values) {
  for (final key in const [
    'item.artwork',
    'collection.artwork',
    'artist.artwork',
    'playlist.artwork',
    'album.artwork',
    'player.artwork',
  ]) {
    final raw = values[key];
    if (raw is String && raw.startsWith('http')) return raw;
  }
  return null;
}

Map<String, Object?> themeQueueTrack(SpotubeTrackObject track) {
  return {
    'id': track.id,
    'title': track.name,
    'name': track.name,
    'artist': track.artists.map((artist) => artist.name).join(', '),
    'artistId': track.artists.isEmpty ? '' : track.artists.first.id,
    'album': track.album.name,
    'albumId': track.album.id,
    'artwork': track.album.images.asUrlString(
      placeholder: ImagePlaceholder.albumArt,
    ),
    'duration': Duration(milliseconds: track.durationMs),
    'uri': track.externalUri,
    'type': 'track',
  };
}

List<Map<String, Object?>> themeQueueTracks(List<SpotubeTrackObject> tracks) {
  return [for (final track in tracks) themeQueueTrack(track)];
}

/// The track total for a row the host has no count for. Saved playlists and
/// albums arrive without one, and a literal `0` read as an empty collection.
const int? _unknownTrackCount = null;

List<Map<String, Object?>> themeLibraryPlaylists(
  Iterable<SpotubeSimplePlaylistObject> playlists,
  Set<String> pinnedIds,
) {
  return [
    for (final playlist in playlists)
      {
        'id': playlist.id,
        'name': playlist.name,
        'artwork': playlist.images.asUrlString(
          placeholder: ImagePlaceholder.collection,
        ),
        'owner': playlist.owner.name,
        'ownerId': playlist.owner.id,
        'trackCount': _unknownTrackCount,
        'pinned': pinnedIds.contains(playlist.id),
        'palette': const <String, String>{},
        'uri': playlist.externalUri,
        'type': 'playlist',
      },
  ];
}

List<Map<String, Object?>> themeLibraryAlbums(
  Iterable<SpotubeSimpleAlbumObject> albums,
) {
  return [
    for (final album in albums)
      {
        'id': album.id,
        'name': album.name,
        'artwork': album.images.asUrlString(
          placeholder: ImagePlaceholder.albumArt,
        ),
        'artist': album.artists.map((artist) => artist.name).join(', '),
        'artistId': album.artists.isEmpty ? '' : album.artists.first.id,
        'year': album.releaseDate == null
            ? ''
            : (DateTime.tryParse(album.releaseDate!)?.year ?? ''),
        'trackCount': _unknownTrackCount,
        'uri': album.externalUri,
        'type': 'album',
      },
  ];
}

List<Map<String, Object?>> themeLibraryArtists(
  Iterable<SpotubeFullArtistObject> artists,
) {
  return [
    for (final artist in artists)
      {
        'id': artist.id,
        'name': artist.name,
        'artwork': artist.images.asUrlString(
          placeholder: ImagePlaceholder.artist,
        ),
        'followers': artist.followers ?? 0,
        'genres': (artist.genres ?? const []).join(', '),
        'uri': artist.externalUri,
        'type': 'artist',
      },
  ];
}

List<Map<String, Object?>> themeLibraryFolders(Iterable<String> locations) {
  return [
    for (final location in locations)
      {
        'path': location,
        'name': p.basename(location),
        'type': 'folder',
      },
  ];
}

/// The declared pin destinations, or the historic sidebar target.
///
/// A theme must declare `layout.pinTargets` before a pin can name a bar; an
/// empty declaration keeps the pre-5B behaviour where every pin lives in the
/// sidebar.
List<Map<String, Object?>> themePinTargets(ThemeLayout? layout) {
  final targets = layout?.pinTargets ?? const <ThemePinTarget>[];
  if (targets.isEmpty) {
    return const [
      {'id': 'sidebar', 'label': 'Sidebar'},
    ];
  }
  return [
    for (final target in targets) {'id': target.id, 'label': target.label},
  ];
}

List<Map<String, Object?>> themeLibraryPins(
  Iterable<SpotubeSimplePlaylistObject> playlists,
  Set<String> pinnedPlaylistIds, {
  Map<String, List<String>> targetPins = const {},
  Iterable<String> stationPins = const [],
  Iterable<RadioStation> favorites = const [],
  Iterable<RadioStation> history = const [],
}) {
  final byId = {for (final playlist in playlists) playlist.id: playlist};
  final stations = <String, RadioStation>{};
  for (final station in [...favorites, ...history]) {
    stations[station.favoriteKey] = station;
  }

  Map<String, Object?> playlistPin(
    SpotubeSimplePlaylistObject playlist,
    String target,
  ) =>
      {
        'id': playlist.id,
        'name': playlist.name,
        'artwork': playlist.images.asUrlString(
          placeholder: ImagePlaceholder.collection,
        ),
        'owner': playlist.owner.name,
        'trackCount': _unknownTrackCount,
        'pinned': true,
        'target': target,
        'palette': const <String, String>{},
        'uri': playlist.externalUri,
        'type': 'playlist',
      };

  return [
    for (final id in pinnedPlaylistIds)
      if (byId[id] case final playlist?) playlistPin(playlist, 'sidebar'),
    for (final entry in targetPins.entries)
      for (final id in entry.value)
        if (byId[id] case final playlist?) playlistPin(playlist, entry.key),
    for (final key in stationPins)
      if (stations[key] case final station?)
        {
          'id': station.favoriteKey,
          'name': station.name,
          'artwork': station.faviconUrl ?? '',
          'owner': station.provider,
          'trackCount': _unknownTrackCount,
          'pinned': true,
          'target': 'sidebar',
          'uri': station.homepageUrl ?? '',
          'type': 'station',
        },
  ];
}

/// The time-of-day greeting a home screen may draw.
///
/// Pure so the bucket boundaries are testable without mocking the clock.
String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The text of the lyric line active at [position], or '' when none is.
///
/// The line is the last slice stamped at or before the position; nothing
/// matches before the first stamp.
String _currentLyricLine(SubtitleSimple lyrics, Duration position) {
  var current = '';
  for (final slice in lyrics.lyrics) {
    if (slice.time > position) break;
    current = slice.text;
  }
  return current;
}
