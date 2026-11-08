/// What a `bind` name carries and where the host reads it from.
///
/// The registry is descriptive: the node renderer still accepts page-scoped
/// names it cannot enumerate ahead of time, and a theme authored for a newer
/// host is not rejected. Its jobs are demand detection (which provider
/// sources a document actually uses), the debug overlay, and one place to
/// see the shape of the contract.
enum ThemeUiBindingKind {
  string,
  number,
  integer,
  boolean,
  duration,
  color,
  datetime,
  list,
  map,
  dynamic,
}

class ThemeUiBindingDefinition {
  final String name;
  final ThemeUiBindingKind kind;

  /// The provider/service that answers this binding. Stable descriptive
  /// keys (`audioPlayer`, `savedPlaylists`, …) rather than provider objects,
  /// so the registry stays const and has no import cycle with providers.
  final String source;
  final String scope;
  final String phase;

  const ThemeUiBindingDefinition(
    this.name,
    this.kind,
    this.source, {
    this.scope = 'global',
    this.phase = 'P4',
  });
}

/// The global binding contract.
///
/// Page scopes (`home.*`, `collection.*`, `item.*`, …) are supplied by the
/// page that owns them and therefore have no fixed source here; the page's
/// bindings are merged over these at render time.
class ThemeUiBindingRegistry {
  ThemeUiBindingRegistry._();

  static const definitions = <ThemeUiBindingDefinition>[
    ThemeUiBindingDefinition(
        'player.trackId', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.title', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.artist', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.album', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.artwork', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.playing', ThemeUiBindingKind.boolean, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.liked', ThemeUiBindingKind.boolean, 'savedTracks',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.loop', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.shuffled', ThemeUiBindingKind.boolean, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.muted', ThemeUiBindingKind.boolean, 'volume',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.position', ThemeUiBindingKind.duration, 'positionTicker',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.duration', ThemeUiBindingKind.duration, 'positionTicker',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.volume', ThemeUiBindingKind.number, 'volume',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'player.speed', ThemeUiBindingKind.number, 'audioPlayer',
        phase: 'existing'),
    ThemeUiBindingDefinition('user.name', ThemeUiBindingKind.string, 'user',
        phase: 'existing'),
    ThemeUiBindingDefinition('user.avatar', ThemeUiBindingKind.string, 'user',
        phase: 'existing'),
    ThemeUiBindingDefinition('app.version', ThemeUiBindingKind.string, 'app',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'app.brightness', ThemeUiBindingKind.string, 'presentation',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'app.themeMode', ThemeUiBindingKind.string, 'preferences',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'app.sidebarCollapsed', ThemeUiBindingKind.boolean, 'layoutPrefs'),
    ThemeUiBindingDefinition(
        'app.asideOpen', ThemeUiBindingKind.boolean, 'layoutPrefs'),
    ThemeUiBindingDefinition(
        'app.pinnedPlaylistIds', ThemeUiBindingKind.list, 'layoutPrefs',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'app.pinnedStationIds', ThemeUiBindingKind.list, 'layoutPrefs',
        phase: 'existing'),
    ThemeUiBindingDefinition('app.greeting', ThemeUiBindingKind.string, 'clock',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'app.currentRoute', ThemeUiBindingKind.string, 'router'),
    ThemeUiBindingDefinition('clock.now', ThemeUiBindingKind.datetime, 'clock',
        phase: 'existing'),
    ThemeUiBindingDefinition(
        'library.playlists', ThemeUiBindingKind.list, 'savedPlaylists'),
    ThemeUiBindingDefinition(
        'library.pinTargets', ThemeUiBindingKind.list, 'themeLayout'),
    ThemeUiBindingDefinition('library.pins', ThemeUiBindingKind.list, 'pins'),
    ThemeUiBindingDefinition(
        'library.albums', ThemeUiBindingKind.list, 'savedAlbums'),
    ThemeUiBindingDefinition(
        'library.artists', ThemeUiBindingKind.list, 'savedArtists'),
    ThemeUiBindingDefinition(
        'library.folders', ThemeUiBindingKind.list, 'preferences'),
    ThemeUiBindingDefinition(
        'library.counts', ThemeUiBindingKind.map, 'library'),
    ThemeUiBindingDefinition(
        'library.activeSection', ThemeUiBindingKind.string, 'router'),
    ThemeUiBindingDefinition(
        'queue.tracks', ThemeUiBindingKind.list, 'audioPlayer'),
    ThemeUiBindingDefinition(
        'queue.currentIndex', ThemeUiBindingKind.integer, 'audioPlayer'),
    ThemeUiBindingDefinition(
        'queue.next', ThemeUiBindingKind.map, 'audioPlayer'),
    ThemeUiBindingDefinition(
        'queue.count', ThemeUiBindingKind.integer, 'audioPlayer'),
    ThemeUiBindingDefinition(
        'palette.dominant', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'palette.vibrant', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'palette.muted', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'palette.darkMuted', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'palette.lightMuted', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'palette.onDominant', ThemeUiBindingKind.color, 'palette'),
    ThemeUiBindingDefinition(
        'audio.bass', ThemeUiBindingKind.number, 'audioEffects',
        phase: 'P7'),
    ThemeUiBindingDefinition(
        'audio.treble', ThemeUiBindingKind.number, 'audioEffects',
        phase: 'P7'),
    ThemeUiBindingDefinition(
        'audio.normalization', ThemeUiBindingKind.boolean, 'audioEffects',
        phase: 'P7'),
    ThemeUiBindingDefinition(
        'audio.crossfade', ThemeUiBindingKind.number, 'audioEffects',
        phase: 'P7'),
    ThemeUiBindingDefinition(
        'audio.sleepTimer', ThemeUiBindingKind.number, 'audioEffects',
        phase: 'P7'),
    ThemeUiBindingDefinition(
        'audio.speed', ThemeUiBindingKind.number, 'audioPlayer',
        phase: 'P7'),
    ThemeUiBindingDefinition('theme.id', ThemeUiBindingKind.string, 'theme'),
    ThemeUiBindingDefinition('theme.name', ThemeUiBindingKind.string, 'theme'),
    ThemeUiBindingDefinition(
        'theme.version', ThemeUiBindingKind.string, 'theme'),
    ThemeUiBindingDefinition(
        'setting.<key>', ThemeUiBindingKind.dynamic, 'settings'),
    ThemeUiBindingDefinition(
        'state.<key>', ThemeUiBindingKind.dynamic, 'localState'),
    ThemeUiBindingDefinition(
        'player.buffering', ThemeUiBindingKind.boolean, 'audioPlayer',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'player.completed', ThemeUiBindingKind.boolean, 'audioPlayer',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'player.error', ThemeUiBindingKind.string, 'audioPlayer',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'downloads.active', ThemeUiBindingKind.integer, 'downloads',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'downloads.queued', ThemeUiBindingKind.integer, 'downloads',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'downloads.failed', ThemeUiBindingKind.integer, 'downloads',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'downloads.completed', ThemeUiBindingKind.integer, 'downloads',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'downloads.progress', ThemeUiBindingKind.map, 'downloads',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'lyrics.available', ThemeUiBindingKind.boolean, 'lyrics',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'lyrics.synced', ThemeUiBindingKind.boolean, 'lyrics',
        phase: 'system'),
    ThemeUiBindingDefinition('lyrics.line', ThemeUiBindingKind.string, 'lyrics',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.active', ThemeUiBindingKind.boolean, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.playing', ThemeUiBindingKind.boolean, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.buffering', ThemeUiBindingKind.boolean, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.station', ThemeUiBindingKind.string, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.liveTitle', ThemeUiBindingKind.string, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition('radio.error', ThemeUiBindingKind.string, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'radio.stations', ThemeUiBindingKind.list, 'radio',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'connect.available', ThemeUiBindingKind.boolean, 'connect',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'connect.clients', ThemeUiBindingKind.list, 'connect',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'connect.clientCount', ThemeUiBindingKind.integer, 'connect',
        phase: 'system'),
    ThemeUiBindingDefinition(
        'search.query', ThemeUiBindingKind.string, 'query'),
    ThemeUiBindingDefinition(
        'search.hasQuery', ThemeUiBindingKind.boolean, 'query'),
    ThemeUiBindingDefinition(
        'search.<scope>.query', ThemeUiBindingKind.string, 'query'),
  ];

  static final Map<String, ThemeUiBindingDefinition> _byName = {
    for (final definition in definitions) definition.name: definition,
  };

  /// Namespace-level defaults for page scopes and dynamic keys.
  static const namespaceDefaults = <String, ThemeUiBindingDefinition>{
    'home': ThemeUiBindingDefinition(
        'home.*', ThemeUiBindingKind.dynamic, 'page',
        scope: 'home'),
    'collection': ThemeUiBindingDefinition(
        'collection.*', ThemeUiBindingKind.dynamic, 'page',
        scope: 'collection'),
    'artist': ThemeUiBindingDefinition(
        'artist.*', ThemeUiBindingKind.dynamic, 'page',
        scope: 'artist'),
    'search': ThemeUiBindingDefinition(
        'search.*', ThemeUiBindingKind.dynamic, 'search',
        scope: 'search'),
    'downloads': ThemeUiBindingDefinition(
        'downloads.*', ThemeUiBindingKind.dynamic, 'page',
        scope: 'downloads'),
    'stats': ThemeUiBindingDefinition(
        'stats.*', ThemeUiBindingKind.dynamic, 'page',
        scope: 'stats'),
    'item': ThemeUiBindingDefinition(
        'item.*', ThemeUiBindingKind.dynamic, 'item',
        scope: 'item'),
    'region': ThemeUiBindingDefinition(
        'region.*', ThemeUiBindingKind.dynamic, 'layout',
        scope: 'region'),
    'setting': ThemeUiBindingDefinition(
        'setting.*', ThemeUiBindingKind.dynamic, 'settings',
        scope: 'setting'),
    'state': ThemeUiBindingDefinition(
        'state.*', ThemeUiBindingKind.dynamic, 'localState',
        scope: 'state'),
  };

  static ThemeUiBindingDefinition? lookup(String name) {
    final exact = _byName[name];
    if (exact != null) return exact;
    // A scoped query (`search.sidebar.query`) is answered by the search
    // namespace before the generic scope fallback.
    if (name.startsWith('search.') && name.endsWith('.query')) {
      return _byName['search.<scope>.query'];
    }
    final separator = name.indexOf('.');
    if (separator <= 0) return null;
    return namespaceDefaults[name.substring(0, separator)];
  }

  static Set<String> get globalNames => {
        for (final definition in definitions)
          if (definition.scope == 'global') definition.name,
      };

  /// Distinct provider sources the given binding names would subscribe.
  static Set<String> sourcesFor(Iterable<String> names) {
    final sources = <String>{};
    for (final name in names) {
      final definition = lookup(name);
      if (definition != null) sources.add(definition.source);
    }
    return sources;
  }
}
