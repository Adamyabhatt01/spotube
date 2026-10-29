import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/history.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
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

/// Demand for the current document, memoized by Riverpod.
///
/// Recomputes on a theme switch and on a `plugin` action that replaces the
/// UI; every slot in that document then shares one scan.
final themeUiBindingDemandProvider = Provider<ThemeUiBindingDemand>((ref) {
  final ui = ref.watch(themeUiProvider).asData?.value;
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

/// Theme-owned settings toggled through `setSetting`/`toggleSetting`.
///
/// Values are published as `setting.<key>`; this is the read side that makes
/// a theme's own toggle survive the rebuild its action causes. Persistence
/// is a later phase; within a session the values are stable.
class ThemeUiSettingsState extends Notifier<Map<String, Object?>> {
  @override
  Map<String, Object?> build() => const <String, Object?>{};

  void set(String key, Object? value) {
    state = {...state, key: value};
  }

  void toggle(String key) {
    final current = state[key];
    final next = current is bool ? !current : !_valueIsTruthy(current);
    state = {...state, key: next};
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
  if (wants.wants('clock.now')) values['clock.now'] = now;

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
    values['player.loop'] = player.loopMode.name;
    values['player.shuffled'] = player.shuffled;
    // There is no per-player speed surface yet; the contract keeps the
    // binding so a theme can read it without a null branch at P7.
    values['player.speed'] = 1.0;
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

  // ----------------------------------------------------------- library
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
    final folders = preferences?.localLibraryLocation ?? const <String>[];

    if (wantsPlaylists) {
      values['library.playlists'] = themeLibraryPlaylists(playlists, pinnedIds);
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
    final preferences = ref.watch(userPreferencesProvider);
    final gains = EqualizerSettings.normalizeGains(preferences.equalizerGains);
    values['audio.bass'] = gains.first;
    values['audio.treble'] = gains.last;
    values['audio.normalization'] = preferences.normalizeAudio;
    values['audio.crossfade'] = 0;
    values['audio.sleepTimer'] = 0;
    values['audio.speed'] = 1.0;
  }

  return ThemeUiBindings(values);
}

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
        'trackCount': 0,
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
        'trackCount': 0,
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

List<Map<String, Object?>> themeLibraryPins(
  Iterable<SpotubeSimplePlaylistObject> playlists,
  Set<String> pinnedPlaylistIds, {
  Iterable<String> stationPins = const [],
  Iterable<RadioStation> favorites = const [],
  Iterable<RadioStation> history = const [],
}) {
  final byId = {for (final playlist in playlists) playlist.id: playlist};
  final stations = <String, RadioStation>{};
  for (final station in [...favorites, ...history]) {
    stations[station.favoriteKey] = station;
  }

  return [
    for (final id in pinnedPlaylistIds)
      if (byId[id] case final playlist?)
        {
          'id': playlist.id,
          'name': playlist.name,
          'artwork': playlist.images.asUrlString(
            placeholder: ImagePlaceholder.collection,
          ),
          'owner': playlist.owner.name,
          'trackCount': 0,
          'pinned': true,
          'palette': const <String, String>{},
          'uri': playlist.externalUri,
          'type': 'playlist',
        },
    for (final key in stationPins)
      if (stations[key] case final station?)
        {
          'id': station.favoriteKey,
          'name': station.name,
          'artwork': station.faviconUrl ?? '',
          'owner': station.provider,
          'trackCount': 0,
          'pinned': true,
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
