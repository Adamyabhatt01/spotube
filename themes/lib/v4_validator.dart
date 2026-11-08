import 'validator.dart';
import 'v3_validator.dart';

/// The keys a v4 payload may carry at the top level.
///
/// v4 is a breaking contract, and every key the host reads is listed here.
/// `dynamic` is part of it: v4 first dropped it as a v3 escape hatch, but that
/// was the one key themes genuinely needed and v4 had no replacement for —
/// shell and artwork palette sync has no other spelling, and the host never
/// stopped honouring it. `light` and `dark` remain from v2 because every theme
/// still has to carry both palettes.
const v4TopLevelKeys = <String>[
  'specVersion',
  'uiKit',
  'light',
  'dark',
  'surfaces',
  'background',
  'radius',
  'density',
  'tokens',
  'dynamic',
  'typography',
  'spacing',
  'motion',
  'scale',
  'icons',
  'components',
  'layout',
  'branding',
  'assets',
  'capabilities',
  'ui',
  'pages',
  'ext',
];

/// The capabilities granted to a theme that does not declare the block.
const v4DefaultCapabilities = <String>{'library.read', 'player.control'};

/// `theme.assets` is implicit: loading the theme's own files is not a user
/// permission, it is what a theme is.
const v4ImplicitCapabilities = <String>{'theme.assets'};

/// Every capability the v4 host knows.
const v4Capabilities = <String>{
  ...v4DefaultCapabilities,
  ...v4ImplicitCapabilities,
  'library.write',
  'audio.effects',
  'ui.pages',
  'ui.hostWidgets',
  'settings.write',
  'clipboard.write',
};

/// The semantic nodes v4 adds to the v3 set.
///
/// The runtime implementations land phase by phase; the vocabulary is closed
/// now so a theme cannot invent a node the host will silently ignore.
const v4NewUiNodeTypes = <String>[
  // Layout
  'box',
  'grid',
  'resizable',
  'safeArea',
  'aspectRatio',
  'kitScope',
  // Content
  'badge',
  'chip',
  'avatar',
  'skeleton',
  'spinner',
  // Input
  'slider',
  'switch',
  'checkbox',
  'radioGroup',
  'textField',
  'textArea',
  'select',
  'segmented',
  // Navigation
  'tabs',
  'menu',
  'contextMenu',
  'breadcrumb',
  'pagination',
  // Overlay
  'dialog',
  'sheet',
  'popover',
  'tooltip',
  // Data
  'virtualList',
  'table',
  'tree',
  'accordion',
  'collapsible',
  'carousel',
  // Special
  'hostWidget',
];

/// Every node type a v4 UI document may use.
const v4UiNodeTypes = <String>[...uiNodeTypes, ...v4NewUiNodeTypes];

/// The props every v4 node may carry on top of its own.
///
/// These come from the common node envelope in the contract: a node can be
/// hidden, forced into a kit, animated, or given a kit variant wherever it
/// appears. `semantics` is the accessibility envelope: a `{label, hint,
/// value, excludeSemantics}` object the host renders as a [Semantics] unit.
const v4EnvelopeProps = <String>[
  'bind',
  'disabledWhen',
  'hiddenWhen',
  'kit',
  'variant',
  'animate',
  'semantics',
];

/// The props the v4-only nodes read.
///
/// A prop the node does not read is an error, exactly as in v3. The semantic
/// checks for these props arrive with their phase; the closed key list is what
/// stops a typo from becoming a permanently ignored prop.
const _v4NodeProps = <String, List<String>>{
  'box': [
    'background',
    'gradient',
    'border',
    'radius',
    'width',
    'height',
    'clip',
    'padding',
    'opacity',
    // `blur` is the node-level frost; `blurTint` keeps it reading as glass
    // while the scroll freeze holds sigma at zero.
    'blur',
    'blurTint',
  ],
  'grid': ['columns', 'gap'],
  'resizable': ['direction', 'initial', 'min', 'max', 'storageKey'],
  'safeArea': ['edges'],
  'aspectRatio': ['ratio'],
  'kitScope': [],
  'badge': ['text', 'variant'],
  'chip': ['label', 'selectedBind', 'selectedEquals'],
  'avatar': ['src', 'fallback', 'size'],
  'skeleton': ['width', 'height', 'radius', 'count'],
  'spinner': ['size', 'color'],
  'slider': ['min', 'max', 'step', 'label', 'showValue', 'orientation'],
  'switch': ['label'],
  'checkbox': ['label'],
  'radioGroup': ['options'],
  'textField': ['placeholder', 'debounceMs', 'clearable', 'icon'],
  'textArea': [
    'placeholder',
    'debounceMs',
    'clearable',
    'icon',
    'minLines',
    'maxLines',
  ],
  'select': ['options', 'placeholder'],
  'segmented': ['options', 'valueBind'],
  'tabs': ['items', 'panels'],
  'menu': ['items', 'trigger', 'placement'],
  // `target` opts a theme-owned menu into the user's host-menu config.
  // `hostItem` hands the row to the host's own menu for the item it draws.
  'contextMenu': ['items', 'target', 'hostItem'],
  'breadcrumb': ['items'],
  'pagination': ['pageBind', 'pageCount'],
  'dialog': ['title', 'description', 'openBind'],
  'sheet': ['side', 'width', 'openBind'],
  'popover': ['placement', 'trigger'],
  'tooltip': ['text', 'placement'],
  // `columns` matches what `list` took in phase 5B: a long grid belongs on the
  // lazy list, and without the count the recommended node could not draw one.
  'virtualList': [
    'itemTemplate',
    'itemExtent',
    'overscan',
    'limit',
    'filter',
    'columns',
    // Paginated paging of an arbitrarily long collection: when the viewport
    // nears the end the host fires this action with `$value` the visible
    // item count, gated by `hasMoreBind` (truthy to fire) and `loadingBind`
    // (truthy to stay quiet).
    'onEndReached',
    'hasMoreBind',
    'loadingBind',
    'endThreshold',
  ],
  'table': ['columns', 'rowTemplate', 'stickyHeader', 'sortable'],
  'tree': ['labelKey', 'childrenKey', 'expandedKey'],
  'accordion': ['items', 'multiple'],
  'collapsible': ['title', 'openBind'],
  'carousel': ['itemTemplate', 'height', 'autoplay'],
  'hostWidget': ['id', 'props'],
};

/// Props v4 adds to a node type that already existed in v3.
///
/// The v3 tables stay frozen: a v3 payload that carries one of these is still
/// a typo, but a v4 theme may filter a `list` or draw a wavy `progress`.
const _v4ExtraBaseProps = <String, List<String>>{
  // `columns` keeps a vertical, data-bound list from becoming one endless
  // column; the host fills a fixed grid instead of hard-coding shortcut rows.
  'list': [
    'filter',
    'columns',
    'onEndReached',
    'hasMoreBind',
    'loadingBind',
    'endThreshold',
  ],
  'progress': ['style'],
  // The frost `box` took, on the node that actually draws panels.
  'card': ['blur', 'blurTint'],
  // `conditional` composes nested conditions; the plain bind/equals/invert
  // shape predates them.
  'conditional': ['allOf', 'anyOf'],
};

/// The closed prop table a v4 node is checked against.
final Map<String, List<String>> v4UiNodeProps = () {
  final table = <String, List<String>>{};
  for (final entry in uiNodeProps.entries) {
    table[entry.key] = [
      ...entry.value,
      for (final key in _v4ExtraBaseProps[entry.key] ?? const <String>[])
        if (!entry.value.contains(key)) key,
      for (final key in v4EnvelopeProps)
        if (!entry.value.contains(key)) key,
    ];
  }
  for (final entry in _v4NodeProps.entries) {
    table[entry.key] = [
      ...entry.value,
      for (final key in v4EnvelopeProps)
        if (!entry.value.contains(key)) key,
    ];
  }
  return table;
}();

/// The bindings v4 adds to the v3 set.
///
/// `item.*`, `collection.*` and the other page scopes stay open, but may now
/// carry a dotted sub-path such as `collection.palette.dominant`.
const v4UiBindings = <String>[
  ...uiBindings,
  'player.speed',
  'player.muted',
  'player.buffering',
  'player.completed',
  'player.error',
  'app.sidebarCollapsed',
  'app.asideOpen',
  'app.pinnedPlaylistIds',
  'app.pinnedStationIds',
  'library.pinTargets',
  'library.playlists',
  'library.pins',
  'library.albums',
  'library.artists',
  'library.folders',
  'library.counts',
  'queue.tracks',
  'queue.currentIndex',
  'queue.next',
  'queue.count',
  'downloads.active',
  'downloads.queued',
  'downloads.failed',
  'downloads.completed',
  'downloads.progress',
  'lyrics.available',
  'lyrics.synced',
  'lyrics.line',
  'radio.active',
  'radio.playing',
  'radio.buffering',
  'radio.station',
  'radio.liveTitle',
  'radio.error',
  'radio.stations',
  'app.currentRoute',
  'library.activeSection',
  'connect.available',
  'connect.clients',
  'connect.clientCount',
  'palette.dominant',
  'palette.vibrant',
  'palette.muted',
  'palette.darkMuted',
  'palette.lightMuted',
  'palette.onDominant',
  'audio.bass',
  'audio.treble',
  'audio.normalization',
  'audio.crossfade',
  'audio.sleepTimer',
  'audio.speed',
  'theme.id',
  'theme.name',
  'theme.version',
];

/// Whether [name] is a v4 binding the host resolves.
bool isV4UiBinding(String name) {
  if (v4UiBindings.contains(name)) return true;
  if (RegExp(
    r'^app\.region\.[A-Za-z][A-Za-z0-9_-]{0,31}\.(collapsed|size)$',
  ).hasMatch(name)) {
    return true;
  }
  // A theme's own persisted settings, written by `setSetting`/`toggleSetting`
  // and published by the host's `setting` namespace — the read-back half of a
  // settings page, so a toggle survives the rebuild its own action causes.
  if (RegExp(r'^setting\.[A-Za-z][A-Za-z0-9_.-]{0,63}$').hasMatch(name)) {
    return true;
  }
  // Ephemeral theme-local state, written by `setLocal`/`toggleLocal` and
  // published by the host's `state` namespace. Session-scoped, never
  // persisted — the dialog/filter/expanded-section half of a theme.
  if (RegExp(r'^state\.[A-Za-z][A-Za-z0-9_.-]{0,63}$').hasMatch(name)) {
    return true;
  }
  return RegExp(
    r'^(item|home|collection|artist|search|library|queue|downloads|stats|'
    r'lyrics|radio|connect)\.'
    r'[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*){0,4}$',
  ).hasMatch(name);
}

/// The actions v4 adds to the v3 set.
const v4UiActionTypes = <String>[
  ...uiActionTypes,
  'setBass',
  'setTreble',
  'setNormalization',
  'setCrossfade',
  'setSleepTimer',
  'setSpeed',
  'setMuted',
  'pinItem',
  'unpinItem',
  'createPlaylist',
  'renamePlaylist',
  'deletePlaylist',
  'addToPlaylist',
  'playStation',
  'toggleStationFavorite',
  'setQuery',
  'clearQuery',
  'setSetting',
  'toggleSetting',
  'setLocal',
  'toggleLocal',
  'clearLocal',
  'openPage',
  'closePage',
  'toggleSidebar',
  'toggleRegion',
  'toggleAside',
  'copy',
  'refresh',
  'scrollTo',
  'dismiss',
];

/// The slot names v4 publishes.
const v4SlotNames = <String>[
  ...slotNames,
  'sidebar.content',
  'sidebar.library',
  'aside.content',
  'library.local.content',
  'radio.content',
  'radio.before_sections',
  'radio.after_sections',
];

/// Whether [name] is a v4 slot. `page.<id>` is the routed theme-page body.
bool isV4UiSlot(String name) {
  if (v4SlotNames.contains(name)) return true;
  return RegExp(r'^page\.[a-z][a-z0-9_-]{0,31}$').hasMatch(name);
}

/// The vocabulary a v4 UI document is checked against.
final v4UiVocabulary = UiVocabulary(
  maxSpecVersion: 2,
  nodeTypes: v4UiNodeTypes,
  nodeProps: v4UiNodeProps,
  isBinding: isV4UiBinding,
  actionTypes: v4UiActionTypes,
  isSlot: isV4UiSlot,
  components: v4ComponentGroups,
  buttonVariants: v4ButtonVariants,
);

/// The v4 vocabulary with the slot names this payload's shell declares.
///
/// A custom region invents its slot (`bar.bottom`), so the closed built-in list
/// grows by exactly the names the shell tree targets — not by a wildcard.
UiVocabulary v4UiVocabularyFor(Iterable<String> shellSlots) {
  final declared = shellSlots.toSet();
  if (declared.isEmpty) return v4UiVocabulary;
  return UiVocabulary(
    maxSpecVersion: 2,
    nodeTypes: v4UiNodeTypes,
    nodeProps: v4UiNodeProps,
    isBinding: isV4UiBinding,
    actionTypes: v4UiActionTypes,
    isSlot: (name) => isV4UiSlot(name) || declared.contains(name),
    components: v4ComponentGroups,
    buttonVariants: v4ButtonVariants,
  );
}

/// Every slot a shell tree (or one of its responsive variants) names.
Set<String> _shellSlotNames(Object? layout) {
  final names = <String>{};

  void walk(Object? raw) {
    if (raw is! Map) return;
    final slot = raw['slot'];
    // `content` keeps the router outlet and ignores a slot, so a name that
    // only appears there is not a slot the host will render.
    if (raw['region'] != 'content' && slot is String && slot.isNotEmpty) {
      names.add(slot);
    }
    final children = raw['children'];
    if (children is List) {
      for (final child in children) {
        walk(child);
      }
    }
  }

  if (layout is Map) {
    walk(layout['shell']);
    final responsive = layout['responsive'];
    if (responsive is Map) {
      for (final variant in responsive.values) {
        if (variant is Map) walk(variant['shell']);
      }
    }
  }
  return names;
}

const _layoutKeys = <String>{
  'chrome',
  'nav',
  'progress',
  'sidebar',
  'sidebarWidth',
  'aside',
  'asideWidth',
  'navItems',
  'navbarItems',
  'libraryItems',
  'player',
  'home',
  'settings',
  'titlebar',
  'splash',
  'shell',
  'pinTargets',
  'responsive',
};

const _playerKeys = <String>{
  'dock',
  'showTrackDetails',
  'showActions',
  'showVolume',
  'showLyrics',
  'showProgress',
};

const _titlebarKeys = <String>{'height', 'padding', 'showBack'};
const _splashKeys = <String>{'logo', 'background', 'text'};
const _homeKeys = <String>{'sections'};
const _settingsKeys = <String>{'sections'};

/// The props a shell node may carry, whether it is a container or a leaf.
const _shellNodeKeys = <String>{
  'type',
  'region',
  'id',
  'slot',
  'label',
  'width',
  'height',
  'flex',
  'minWidth',
  'maxWidth',
  'minHeight',
  'maxHeight',
  'resizable',
  'collapsible',
  'collapsedSize',
  'overflow',
  'hiddenWhen',
  'safeArea',
  'zIndex',
  'focusOrder',
  'storageKey',
  'children',
};

const _shellTypes = <String>{'row', 'column', 'stack', 'grid'};
const _shellRegions = <String>{
  'content',
  'sidebar',
  'aside',
  'player',
  'titlebar',
  'navbar',
  'custom',
};

/// Host regions a shell may declare at most once. `custom` is repeatable.
const _shellSingles = <String>{
  'sidebar',
  'aside',
  'player',
  'titlebar',
  'navbar',
};

const _shellOverflowModes = <String>{'clip', 'scroll', 'wrap', 'menu'};
const _shellSafeAreas = <String>{'top', 'right', 'bottom', 'left'};
const _shellResizeEdges = <String>{'start', 'end', 'top', 'bottom'};
const _shellStorageKeyPattern = r'^[a-z][a-z0-9_.-]{0,63}$';
const _shellPercentPattern = r'^(?:100(?:\.0+)?|[0-9]{1,2}(?:\.[0-9]+)?)%$';
const _shellMaxDepth = 8;
const _shellMaxLeaves = 24;

const _responsiveKeys = <String>{
  'chrome',
  'nav',
  'progress',
  'sidebar',
  'sidebarWidth',
  'aside',
  'asideWidth',
  'navItems',
  'navbarItems',
  'libraryItems',
  'player',
  'home',
  'settings',
  'titlebar',
  'splash',
  'shell',
  'pages',
};

const _breakpoints = <String>{'compact', 'medium', 'expanded'};

const _typographyKeys = <String>{
  'family',
  'monoFamily',
  'brandFamily',
  'styles',
  'fonts',
};

const _textStyleKeys = <String>{
  'fontSize',
  'fontWeight',
  'height',
  'letterSpacing',
  'color',
  'fontFamily',
  'fontStyle',
};

const _fontKeys = <String>{'family', 'asset', 'weight', 'style'};

const _spacingKeys = <String>{
  'xs',
  'sm',
  'md',
  'lg',
  'xl',
  'xxl',
  'page',
  'section',
  'cardGap',
  'pageHorizontal',
  'custom',
};

const _motionKeys = <String>{
  'fast',
  'normal',
  'slow',
  'pageTransition',
  'sheet',
  'easing',
  'custom',
};

const _scaleKeys = <String>{'size', 'text', 'radius', 'icon', 'spacing'};
const _iconsKeys = <String>{'sm', 'md', 'lg', 'xl', 'overrides', 'custom'};

const _brandingKeys = <String>{
  'appName',
  'shortName',
  'tagline',
  'wordmark',
  'logo',
  'titlebarTitle',
  'windowTitle',
  'aboutName',
  'notificationName',
  'showHostAttribution',
};

const _assetKeys = <String>{'path', 'kind', 'role'};
const _uiKeys = <String>{
  'specVersion',
  'slots',
  'screens',
  'templates',
  'renderPoints',
  'pages',
  'menus',
};

/// The context-menu targets the v4 host publishes.
const v4ContextMenuTargets = <String>{
  'track',
  'playlist',
  'album',
  'artist',
  'queueItem',
  'download',
  'searchResult',
  'radio',
};

const _menuEntryKeys = <String>{
  'id',
  'label',
  'icon',
  'action',
  'capability',
  'when',
  'destructive',
};

/// The render points the v4.0 host publishes.
///
/// Mirrors `themeUiRenderPoints` in the host. Unknown ids are a warning, not
/// an error: a theme authored for a newer host still loads on this one, and
/// the extra mapping is simply ignored.
const v4RenderPoints = <String>{
  'search.field',
  'search.suggestions',
  'search.suggestion.item',
  'search.suggestion.group',
  'search.empty',
  'search.loading',
  'search.recent',
  'contextMenu.container',
  'contextMenu.item',
  'contextMenu.separator',
  'contextMenu.submenu',
  'library.playlist.item',
  'library.playlist.group',
  'library.playlist.empty',
  'queue.item',
  'table.header',
  'table.row',
  'player.trackDetails',
  'toast.item',
};

/// The host widgets the v4.0 host mounts.
///
/// Mirrors `ThemeUiHostWidgetIds` in the app. This is the closed escape hatch
/// from the contract: a theme that names an id the host does not know renders
/// nothing, which is survivable, so it warns instead of failing — the same
/// policy as an unknown render point, and deliberately looser than the prop
/// table below.
const v4HostWidgetIds = <String>{
  'library.playlists',
  'library.pins',
  'library.albums',
  'library.artists',
  'player.controls',
  'audio.bass',
  'audio.equalizer',
  'audio.crossfade',
  'audio.sleepTimer',
  'queue.list',
  'search.field',
  'theme.settings',
};

/// The props each host widget reads, inside its `props` bag.
///
/// Unlike an unknown id, an unknown prop is always a typo, and a widget that
/// quietly ignores it leaves the theme author with no way to find out — so the
/// host rejects it as an error, exactly as it does for a node prop.
const v4HostWidgetProps = <String, Set<String>>{
  'library.playlists': {
    'compact',
    'showSearch',
    'showCreate',
    'limit',
    'filter',
    'pinTarget',
    'direction',
    'showPin',
    'showQueue',
    'showPlay',
    'coverPlays',
    'showTitle',
    'showSubtitle',
    'density',
    'coverSize',
    'coverRadius',
    'showDividers',
    'rowSpacing',
  },
  'library.pins': {
    'compact',
    'target',
    'direction',
    'showPin',
    'showQueue',
    'showPlay',
    'coverPlays',
    'showTitle',
    'showSubtitle',
    'density',
    'coverSize',
    'coverRadius',
    'showDividers',
    'rowSpacing',
  },
  'library.albums': {
    'compact',
    'showQueue',
    'showPlay',
    'coverPlays',
    'showTitle',
    'showSubtitle',
    'density',
    'coverSize',
    'coverRadius',
    'showDividers',
    'rowSpacing',
  },
  'library.artists': {
    'compact',
    'showPlay',
    'coverPlays',
    'showTitle',
    'showSubtitle',
    'density',
    'coverSize',
    'coverRadius',
    'showDividers',
    'rowSpacing',
  },
  'player.controls': {'compact', 'showProgress', 'showVolume'},
  'audio.bass': {'compact'},
  'audio.equalizer': {'bands'},
  'audio.crossfade': <String>{},
  'audio.sleepTimer': <String>{},
  'queue.list': {'compact'},
  'search.field': {'placeholder', 'scope'},
  'theme.settings': <String>{},
};

/// Host widget props that must be booleans.
const _hostWidgetBoolProps = <String>{
  'compact',
  'showSearch',
  'showCreate',
  'showProgress',
  'showVolume',
  'showPin',
  'showQueue',
  'showPlay',
  'coverPlays',
  'showTitle',
  'showSubtitle',
  'showDividers',
};

/// Host widget props that must be whole numbers inside a range the host can
/// honor. The bound is the host's own clamp, so a payload that validates here
/// also renders the same way on every build.
const _hostWidgetCountProps = <String, ({int min, int max})>{
  'limit': (min: 1, max: 200),
  'bands': (min: 1, max: 10),
  'coverSize': (min: 32, max: 96),
  'coverRadius': (min: 0, max: 24),
  'rowSpacing': (min: 0, max: 24),
};

/// Host widget props whose value is a closed vocabulary.
const _hostWidgetEnumProps = <String, Set<String>>{
  'filter': {'all', 'pins', 'recent'},
  'direction': {'vertical', 'horizontal'},
  'density': {'standard', 'compact'},
};

/// Host widget props that must be strings, with their length cap.
const _hostWidgetStringProps = <String, int>{
  'placeholder': 80,
  'pinTarget': 64,
  'target': 64,
};

/// Props naming a pin target, which must be one the document declares.
const _hostWidgetTargetProps = <String>{'pinTarget', 'target'};

/// A `search.field` scope names a binding (`search.<scope>.query`), so the host
/// accepts only this character set. Left as a free-form string an author would
/// write `scope: "album name"` and silently get the app's own search field back.
final _hostWidgetScopePattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// The host stops expanding render-point templates after this many levels.
const v4MaxTemplateDepth = 8;
const _slotKeys = <String>{'children', 'refreshSeconds'};
const _screenKeys = <String>{'title', 'showBack', 'children'};
const _templateKeys = <String>{'params', 'children'};
const _pageKeys = <String>{
  'id',
  'title',
  'icon',
  'parent',
  'showBack',
  'visible',
};

const _actionCapabilities = <String, String>{
  'playPause': 'player.control',
  'next': 'player.control',
  'previous': 'player.control',
  'seek': 'player.control',
  'setVolume': 'player.control',
  'setShuffle': 'player.control',
  'setLoopMode': 'player.control',
  'setBass': 'audio.effects',
  'setTreble': 'audio.effects',
  'setNormalization': 'audio.effects',
  'setCrossfade': 'audio.effects',
  'setSleepTimer': 'audio.effects',
  'setSpeed': 'player.control',
  'setMuted': 'player.control',
  'pinItem': 'library.write',
  'unpinItem': 'library.write',
  'createPlaylist': 'library.write',
  'renamePlaylist': 'library.write',
  'deletePlaylist': 'library.write',
  'addToPlaylist': 'library.write',
  'setSetting': 'settings.write',
  'toggleSetting': 'settings.write',
  'openPage': 'ui.pages',
  'closePage': 'ui.pages',
  'copy': 'clipboard.write',
};

/// The action verbs the v4 host knows. Mirrors `ThemeUiAction.knownTypes`.
const v4ActionVerbs = <String>{
  'navigate',
  'playPause',
  'next',
  'previous',
  'seek',
  'setVolume',
  'setShuffle',
  'setLoopMode',
  'like',
  'download',
  'openSettings',
  'openLyrics',
  'openQueue',
  'openDownloads',
  'toast',
  'plugin',
  'playItem',
  'playCollection',
  'openItem',
  'likeItem',
  'downloadItem',
  'pinItem',
  'unpinItem',
  'dismiss',
  'setQuery',
  'clearQuery',
  'setSetting',
  'toggleSetting',
  'setLocal',
  'toggleLocal',
  'clearLocal',
  'copy',
  'refresh',
  'toggleSidebar',
  'toggleAside',
  'toggleRegion',
  'openPage',
  'closePage',
  'setBass',
  'setTreble',
  'setNormalization',
  'setCrossfade',
  'setSleepTimer',
  'setSpeed',
  'setMuted',
  'createPlaylist',
  'renamePlaylist',
  'deletePlaylist',
  'addToPlaylist',
  'playStation',
  'toggleStationFavorite',
};

/// Validates the v4 half of a payload.
///
/// The v2 palette and the shared v3 blocks are checked by the existing
/// validators. This layer adds the strict sweeps, the v4 vocabulary, the
/// capability checks and the new layout/page blocks.
List<Issue> validateV4Blocks(Map<String, dynamic> payload) {
  final issues = <Issue>[];

  final specVersion = payload['specVersion'];
  if (specVersion is! num || specVersion != 4) {
    issues.add(
      const Issue(
        Severity.error,
        'specVersion',
        'must be 4 — v4 is the current contract',
      ),
    );
    return issues;
  }

  final capabilities = _capabilities(payload, issues);

  issues.addAll(
    validateV3Blocks(
      payload,
      vocabulary: v4UiVocabularyFor(_shellSlotNames(payload['layout'])),
      allowComponentStates: false,
      allowKits: true,
      allowProgressStyle: true,
    ),
  );

  _sweepBlocks(payload, issues, capabilities);
  _layoutV4(payload['layout'], issues);
  _pages(payload['pages'], 'pages', issues, capabilities);
  _capabilityUsage(payload, capabilities, issues);
  return issues;
}

/// The capabilities a payload grants, including the implicit asset access.
Set<String> v4GrantedCapabilities(Map<String, dynamic> payload) {
  final declared = payload['capabilities'];
  if (declared is! List)
    return {...v4DefaultCapabilities, ...v4ImplicitCapabilities};
  return {
    for (final value in declared)
      if (value is String) value,
    ...v4ImplicitCapabilities,
  };
}

Set<String> _capabilities(Map<String, dynamic> payload, List<Issue> issues) {
  final raw = payload['capabilities'];
  if (raw == null) {
    return {...v4DefaultCapabilities, ...v4ImplicitCapabilities};
  }
  if (raw is! List) {
    issues.add(
      const Issue(Severity.error, 'capabilities', 'must be a list of names'),
    );
    return {...v4DefaultCapabilities, ...v4ImplicitCapabilities};
  }

  final granted = <String>{...v4ImplicitCapabilities};
  final seen = <String>{};
  for (var i = 0; i < raw.length; i++) {
    final value = raw[i];
    if (value is! String || !v4Capabilities.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          'capabilities[$i]',
          'unknown capability — the host rejects the theme',
        ),
      );
      continue;
    }
    if (!seen.add(value)) {
      issues.add(
        Issue(
          Severity.warning,
          'capabilities[$i]',
          'duplicate capability — ignored',
        ),
      );
      continue;
    }
    granted.add(value);
  }
  return granted;
}

void _sweepBlocks(
  Map<String, dynamic> payload,
  List<Issue> issues,
  Set<String> capabilities,
) {
  final uiKit = payload['uiKit'];
  if (uiKit != null && (uiKit is! String || !uiKits.contains(uiKit))) {
    issues.add(
      Issue(Severity.error, 'uiKit', 'must be one of ${uiKits.join(', ')}'),
    );
  }

  _sweep(payload['typography'], 'typography', _typographyKeys, issues);
  final typography = payload['typography'];
  if (typography is Map) {
    final styles = typography['styles'];
    if (styles is Map) {
      for (final entry in styles.entries) {
        _sweep(
          entry.value,
          'typography.styles.${entry.key}',
          _textStyleKeys,
          issues,
        );
      }
    }
    final fonts = typography['fonts'];
    if (fonts is List) {
      for (var i = 0; i < fonts.length; i++) {
        _sweep(fonts[i], 'typography.fonts[$i]', _fontKeys, issues);
      }
    }
  }

  _sweep(payload['spacing'], 'spacing', _spacingKeys, issues);
  _sweep(payload['motion'], 'motion', _motionKeys, issues);
  _sweep(payload['scale'], 'scale', _scaleKeys, issues);
  _sweep(payload['icons'], 'icons', _iconsKeys, issues);
  _sweep(payload['branding'], 'branding', _brandingKeys, issues);

  final assets = payload['assets'];
  if (assets is List) {
    for (var i = 0; i < assets.length; i++) {
      _sweep(assets[i], 'assets[$i]', _assetKeys, issues);
    }
  } else if (assets is Map) {
    for (final entry in assets.entries) {
      final list = entry.value;
      if (list is! List) continue;
      for (var i = 0; i < list.length; i++) {
        _sweep(list[i], 'assets.${entry.key}[$i]', _assetKeys, issues);
      }
    }
  }

  _sweepComponents(payload['components'], issues);
  _sweepUi(payload['ui'], issues, capabilities);
}

void _sweepComponents(Object? raw, List<Issue> issues) {
  if (raw is! Map) return;
  final components = raw.cast<String, dynamic>();
  for (final entry in components.entries) {
    if (uiKits.contains(entry.key)) {
      final kit = entry.value;
      if (kit is! Map) {
        issues.add(
          Issue(
            Severity.error,
            'components.${entry.key}',
            'must be an object of component overrides',
          ),
        );
        continue;
      }
      for (final override in kit.entries) {
        if (!v4ComponentGroups.contains(override.key)) {
          issues.add(
            Issue(
              Severity.error,
              'components.${entry.key}.${override.key}',
              'not a component the app knows',
            ),
          );
          continue;
        }
        if (override.key == 'buttons' && override.value is Map) {
          for (final button in (override.value as Map).entries) {
            if (!buttonVariants.contains(button.key)) {
              issues.add(
                Issue(
                  Severity.error,
                  'components.${entry.key}.${override.key}.${button.key}',
                  'not a button variant the app knows',
                ),
              );
              continue;
            }
            _sweepComponentStyle(
              button.value,
              'components.${entry.key}.${override.key}.${button.key}',
              issues,
            );
          }
          continue;
        }
        _sweepComponentStyle(
          override.value,
          'components.${entry.key}.${override.key}',
          issues,
        );
      }
      continue;
    }

    if (!v4ComponentGroups.contains(entry.key)) {
      issues.add(
        Issue(
          Severity.error,
          'components.${entry.key}',
          'not a component the app knows',
        ),
      );
      continue;
    }
    if (entry.key == 'buttons' && entry.value is Map) {
      for (final button in (entry.value as Map).entries) {
        if (!buttonVariants.contains(button.key)) {
          issues.add(
            Issue(
              Severity.error,
              'components.buttons.${button.key}',
              'not a button variant the app knows',
            ),
          );
          continue;
        }
        _sweepComponentStyle(
          button.value,
          'components.buttons.${button.key}',
          issues,
        );
      }
      continue;
    }
    _sweepComponentStyle(entry.value, 'components.${entry.key}', issues);
  }
}

void _sweepComponentStyle(Object? raw, String path, List<Issue> issues) {
  if (raw is! Map) return;
  // `progress` is the one component group whose shape is a style: `linear`
  // (default) or `wavy`, the animated ribbon the seek line can draw. The
  // same key is valid on a kit override (`components.material.progress`).
  final isProgress = path.split('.').contains('progress');
  for (final key in raw.keys) {
    if (key == 'style') {
      if (!isProgress) {
        issues.add(
          Issue(
            Severity.error,
            '$path.style',
            'only progress supports a style',
          ),
        );
      } else if (raw[key] != 'linear' && raw[key] != 'wavy') {
        issues.add(
          Issue(
            Severity.error,
            '$path.style',
            'must be "linear" or "wavy"',
          ),
        );
      }
      continue;
    }
    if (!componentStyleKeys.contains(key)) {
      issues.add(
        Issue(
          Severity.error,
          '$path.$key',
          'not a component style prop the app reads',
        ),
      );
    }
  }
}

void _sweepUi(Object? raw, List<Issue> issues, Set<String>? capabilities) {
  if (raw is! Map) return;
  final ui = raw.cast<String, dynamic>();
  _sweep(ui, 'ui', _uiKeys, issues);

  final slots = ui['slots'];
  if (slots is Map) {
    for (final entry in slots.entries) {
      _sweep(entry.value, 'ui.slots.${entry.key}', _slotKeys, issues);
    }
  }
  final screens = ui['screens'];
  if (screens is Map) {
    for (final entry in screens.entries) {
      _sweep(entry.value, 'ui.screens.${entry.key}', _screenKeys, issues);
    }
  }
  final templates = ui['templates'];
  if (templates is Map) {
    for (final entry in templates.entries) {
      _sweep(entry.value, 'ui.templates.${entry.key}', _templateKeys, issues);
    }
  }
  _renderPoints(ui['renderPoints'], templates, issues);
  _pages(ui['pages'], 'ui.pages', issues, capabilities);
  _menus(ui['menus'], issues, capabilities);
}

/// Checks `ui.menus`: host target keys, namespaced ids and allowlisted verbs.
///
/// A theme can append rows to a host menu, never replace one. Duplicate ids
/// inside a target are an error because the user's stored order and hidden
/// list address rows by id.
void _menus(
  Object? raw,
  List<Issue> issues,
  Set<String>? capabilities,
) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'ui.menus', 'must be an object'));
    return;
  }

  for (final entry in raw.entries) {
    final target = entry.key;
    final path = 'ui.menus.$target';
    if (target is! String || !v4ContextMenuTargets.contains(target)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'not a context-menu target the host publishes',
        ),
      );
      continue;
    }
    final rows = entry.value;
    if (rows is! List) {
      issues.add(Issue(Severity.error, path, 'must be a list'));
      continue;
    }
    if (rows.length > 32) {
      issues.add(Issue(Severity.error, path, 'has more than 32 entries'));
    }

    final seen = <String>{};
    for (var i = 0; i < rows.length && i < 32; i++) {
      final itemPath = '$path[$i]';
      final item = rows[i];
      if (item is! Map) {
        issues.add(Issue(Severity.error, itemPath, 'must be an object'));
        continue;
      }
      _sweep(item, itemPath, _menuEntryKeys, issues);

      final id = item['id'];
      if (id is! String ||
          !id.startsWith('theme.') ||
          id.length > 64 ||
          id.length <= 'theme.'.length) {
        issues.add(
          Issue(
            Severity.error,
            '$itemPath.id',
            'must be a theme.<name> id of at most 64 characters',
          ),
        );
      } else if (!seen.add(id)) {
        issues.add(Issue(Severity.error, '$itemPath.id', 'duplicate id "$id"'));
      }

      final label = item['label'];
      if (label is! String || label.trim().isEmpty || label.length > 80) {
        issues.add(
          Issue(
            Severity.error,
            '$itemPath.label',
            'must be a non-empty string of at most 80 characters',
          ),
        );
      }

      final icon = item['icon'];
      if (icon != null && (icon is! String || icon.length > 32)) {
        issues.add(
          Issue(Severity.error, '$itemPath.icon', 'must be a short token'),
        );
      }

      final when = item['when'];
      if (when != null && (when is! String || when.length > 160)) {
        issues.add(
          Issue(
            Severity.error,
            '$itemPath.when',
            'must be a string of at most 160 characters',
          ),
        );
      }

      final destructive = item['destructive'];
      if (destructive != null && destructive is! bool) {
        issues.add(
          Issue(Severity.error, '$itemPath.destructive', 'must be a boolean'),
        );
      }

      final action = item['action'];
      if (action is! Map) {
        issues.add(
          Issue(Severity.error, '$itemPath.action', 'must be an action object'),
        );
      } else {
        final type = action['type'];
        if (type is! String || !v4ActionVerbs.contains(type)) {
          issues.add(
            Issue(
              Severity.error,
              '$itemPath.action.type',
              'not an action verb the host dispatches',
            ),
          );
        } else {
          final required = _actionCapabilities[type];
          if (required != null &&
              capabilities != null &&
              !capabilities.contains(required)) {
            issues.add(
              Issue(
                Severity.error,
                '$itemPath.action.type',
                '$type requires the $required capability',
              ),
            );
          }
        }
      }

      final capability = item['capability'];
      if (capability != null) {
        if (capability is! String ||
            !v4Capabilities.contains(capability)) {
          issues.add(
            Issue(
              Severity.error,
              '$itemPath.capability',
              'must name a v4 capability',
            ),
          );
        } else if (capabilities != null &&
            !capabilities.contains(capability)) {
          issues.add(
            Issue(
              Severity.error,
              '$itemPath.capability',
              'the document does not grant $capability',
            ),
          );
        }
      }
    }
  }
}

/// Checks `ui.renderPoints`.
///
/// The catalogue is closed, so an unknown id is a warning and the host ignores
/// it. A mapping whose template is absent also warns (the host keeps its
/// default), while a template the host cannot legally render is an error: the
/// author asked for a replacement that would silently fall back.
void _renderPoints(Object? raw, Object? templatesRaw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(
      const Issue(Severity.error, 'ui.renderPoints', 'must be an object'),
    );
    return;
  }

  final templates = templatesRaw is Map ? templatesRaw : const {};
  for (final entry in raw.entries) {
    final id = entry.key;
    final path = 'ui.renderPoints.$id';
    if (id is! String) continue;
    if (!v4RenderPoints.contains(id)) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'not a render point the host publishes — ignored at runtime',
        ),
      );
      continue;
    }

    final name = entry.value;
    if (name is! String || name.trim().isEmpty) {
      issues.add(Issue(Severity.error, path, 'must name a template'));
      continue;
    }
    if (!templates.containsKey(name)) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'template "$name" is missing — the host default is used',
        ),
      );
      continue;
    }

    final problem = _templateReferenceProblem(templates, name);
    if (problem != null) {
      issues.add(Issue(Severity.error, path, problem));
    }
  }
}

String? _templateReferenceProblem(
  Map templates,
  String name, [
  List<String> path = const [],
  int depth = 1,
]) {
  if (depth > v4MaxTemplateDepth) {
    return 'template nesting is deeper than $v4MaxTemplateDepth';
  }
  if (path.contains(name)) return 'template "$name" refers to itself';
  final template = templates[name];
  if (template is! Map) return 'template "$name" is missing';

  final nextPath = [...path, name];
  final children = template['children'];
  if (children is List) {
    for (final child in children) {
      final problem = _templateNodeProblem(templates, child, nextPath, depth);
      if (problem != null) return problem;
    }
  }
  return null;
}

String? _templateNodeProblem(
  Map templates,
  Object? raw,
  List<String> path,
  int depth,
) {
  if (raw is! Map) return null;
  final node = raw.cast<String, dynamic>();
  if (node['type'] == 'hostWidget') {
    return 'hostWidget is not allowed in a render-point template';
  }
  if (node['type'] == 'template') {
    final props = node['props'];
    final reference = props is Map && props['name'] != null
        ? props['name']
        : node['name'];
    if (reference is String && reference.trim().isNotEmpty) {
      if (depth + 1 > v4MaxTemplateDepth) {
        return 'template nesting is deeper than $v4MaxTemplateDepth';
      }
      if (path.contains(reference)) {
        return 'template "$reference" refers to itself';
      }
      final template = templates[reference];
      if (template is! Map) return 'template "$reference" is missing';
      final nextPath = [...path, reference];
      final children = template['children'];
      if (children is List) {
        for (final child in children) {
          final problem = _templateNodeProblem(
            templates,
            child,
            nextPath,
            depth + 1,
          );
          if (problem != null) return problem;
        }
      }
    }
  }

  final children = node['children'];
  if (children is List) {
    for (final child in children) {
      final problem = _templateNodeProblem(templates, child, path, depth);
      if (problem != null) return problem;
    }
  }
  return null;
}

void _sweep(Object? raw, String path, Set<String> allowed, List<Issue> issues) {
  if (raw is! Map) return;
  for (final key in raw.keys) {
    if (!allowed.contains(key)) {
      issues.add(
        Issue(
          Severity.error,
          '$path.$key',
          'not a v4 key — the host rejects it',
        ),
      );
    }
  }
}

void _layoutV4(Object? raw, List<Issue> issues) {
  if (raw is! Map) return;
  final layout = raw.cast<String, dynamic>();
  _sweep(layout, 'layout', _layoutKeys, issues);

  _enum(layout, 'layout.sidebar', const {'host', 'theme'}, issues);
  _enum(layout, 'layout.aside', const {'none', 'theme'}, issues);
  _size(layout, 'layout.sidebarWidth', issues);
  _size(layout, 'layout.asideWidth', issues);
  _shell(layout['shell'], 'layout.shell', issues);
  _pinTargets(layout['pinTargets'], 'layout.pinTargets', issues);

  final player = layout['player'];
  if (player is Map) {
    _sweep(player, 'layout.player', _playerKeys, issues);
    _enum(player, 'layout.player.dock', const {
      'full',
      'compact',
      'stage',
    }, issues);
  }
  final home = layout['home'];
  if (home is Map) _sweep(home, 'layout.home', _homeKeys, issues);
  final settings = layout['settings'];
  if (settings is Map) {
    _sweep(settings, 'layout.settings', _settingsKeys, issues);
  }
  final titlebar = layout['titlebar'];
  if (titlebar is Map) {
    _sweep(titlebar, 'layout.titlebar', _titlebarKeys, issues);
  }
  final splash = layout['splash'];
  if (splash is Map) _sweep(splash, 'layout.splash', _splashKeys, issues);

  final responsive = layout['responsive'];
  if (responsive is! Map) return;
  for (final entry in responsive.entries) {
    final path = 'layout.responsive.${entry.key}';
    if (!_breakpoints.contains(entry.key)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${_breakpoints.join(', ')}',
        ),
      );
      continue;
    }
    final variant = entry.value;
    if (variant is! Map) continue;
    _sweep(variant, path, _responsiveKeys, issues);
    _enum(variant, '$path.sidebar', const {'host', 'theme'}, issues);
    _enum(variant, '$path.aside', const {'none', 'theme'}, issues);
    _size(variant, '$path.sidebarWidth', issues);
    _size(variant, '$path.asideWidth', issues);
    _shell(variant['shell'], '$path.shell', issues);

    final player = variant['player'];
    if (player is Map) {
      _sweep(player, '$path.player', _playerKeys, issues);
      _enum(player, '$path.player.dock', const {
        'full',
        'compact',
        'stage',
      }, issues);
    }
    final home = variant['home'];
    if (home is Map) _sweep(home, '$path.home', _homeKeys, issues);
    final settings = variant['settings'];
    if (settings is Map) {
      _sweep(settings, '$path.settings', _settingsKeys, issues);
    }
    final titlebar = variant['titlebar'];
    if (titlebar is Map) {
      _sweep(titlebar, '$path.titlebar', _titlebarKeys, issues);
    }
    final splash = variant['splash'];
    if (splash is Map) _sweep(splash, '$path.splash', _splashKeys, issues);
    _pageVisibility(variant['pages'], '$path.pages', issues);
  }
}

/// Validates `layout.shell`.
///
/// The host parser fails closed: any invalid child throws away the whole shell
/// and the legacy layout returns. This mirrors those structural rules and adds
/// the type checks the parser silently coerces, so an author sees the broken
/// path instead of a layout that quietly disappeared.
void _shell(Object? raw, String path, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be a shell node object'));
    return;
  }

  final state = _ShellState();
  _shellNode(raw.cast<String, dynamic>(), path, 0, state, issues);

  if (state.contents == 0) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'shell must contain exactly one content region',
      ),
    );
  }
}

class _ShellState {
  int contents = 0;
  int leaves = 0;
  bool reportedLeaves = false;
  final singlePaths = <String, String>{};
  final idPaths = <String, String>{};
  final slotPaths = <String, String>{};
}

void _shellNode(
  Map<String, dynamic> node,
  String path,
  int depth,
  _ShellState state,
  List<Issue> issues,
) {
  if (depth > _shellMaxDepth) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'shell nests deeper than $_shellMaxDepth containers',
      ),
    );
    return;
  }

  _sweep(node, path, _shellNodeKeys, issues);

  final region = node['region'];
  final type = node['type'];
  if (region != null && type != null) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'a node is either a region leaf or a container, not both',
      ),
    );
    return;
  }
  if (region == null && type == null) {
    issues.add(
      Issue(Severity.error, path, 'must declare either region or type'),
    );
    return;
  }

  if (region != null) {
    _shellRegion(node, path, state, issues);
    return;
  }
  _shellContainer(node, path, depth, state, issues);
}

void _shellContainer(
  Map<String, dynamic> node,
  String path,
  int depth,
  _ShellState state,
  List<Issue> issues,
) {
  final type = node['type'];
  if (type is! String || !_shellTypes.contains(type)) {
    issues.add(
      Issue(
        Severity.error,
        '$path.type',
        'must be one of ${_shellTypes.join(', ')}',
      ),
    );
    return;
  }

  final children = node['children'];
  if (children is! List) {
    issues.add(
      Issue(Severity.error, '$path.children', 'must be a list of nodes'),
    );
    return;
  }
  if (children.isEmpty) {
    issues.add(
      Issue(Severity.error, '$path.children', 'must contain at least one node'),
    );
    return;
  }
  if (children.length > _shellMaxLeaves) {
    issues.add(
      Issue(
        Severity.error,
        '$path.children',
        'more than $_shellMaxLeaves children — the host drops the extras',
      ),
    );
  }

  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final childPath = '$path.children[$i]';
    if (child is! Map) {
      issues.add(
        Issue(Severity.error, childPath, 'must be a shell node object'),
      );
      continue;
    }
    _shellNode(
      child.cast<String, dynamic>(),
      childPath,
      depth + 1,
      state,
      issues,
    );
  }
}

void _shellRegion(
  Map<String, dynamic> node,
  String path,
  _ShellState state,
  List<Issue> issues,
) {
  final region = node['region'];
  if (region is! String || !_shellRegions.contains(region)) {
    issues.add(
      Issue(
        Severity.error,
        '$path.region',
        'must be one of ${_shellRegions.join(', ')}',
      ),
    );
    return;
  }

  state.leaves++;
  if (state.leaves > _shellMaxLeaves && !state.reportedLeaves) {
    state.reportedLeaves = true;
    issues.add(
      Issue(
        Severity.error,
        path,
        'shell has more than $_shellMaxLeaves region leaves',
      ),
    );
  }

  String? id;
  final idRaw = node['id'];
  if (idRaw != null) {
    if (idRaw is! String || idRaw.trim().isEmpty || idRaw.length > 64) {
      issues.add(
        Issue(
          Severity.error,
          '$path.id',
          'must be a non-empty string of at most 64 characters',
        ),
      );
    } else {
      id = idRaw;
    }
  }

  final slotRaw = node['slot'];
  String? slot;
  if (slotRaw != null) {
    if (slotRaw is! String || slotRaw.trim().isEmpty || slotRaw.length > 64) {
      issues.add(
        Issue(
          Severity.error,
          '$path.slot',
          'must be a non-empty string of at most 64 characters',
        ),
      );
    } else {
      slot = slotRaw;
    }
  }

  if (region == 'custom') {
    if (id == null) {
      issues.add(
        Issue(Severity.error, '$path.id', 'custom regions require an id'),
      );
    }
    if (slot == null) {
      issues.add(
        Issue(Severity.error, '$path.slot', 'custom regions require a slot'),
      );
    }
    if (node['label'] == null) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'custom regions need a label for screen readers',
        ),
      );
    }
  }

  final effectiveId = id ?? (region == 'custom' ? null : region);
  if (effectiveId != null) {
    final prior = state.idPaths[effectiveId];
    if (prior != null) {
      issues.add(
        Issue(
          Severity.error,
          '$path.id',
          'duplicate region id "$effectiveId" (already used at $prior)',
        ),
      );
    } else {
      state.idPaths[effectiveId] = path;
    }
  }

  if (region == 'content') {
    state.contents++;
    if (state.contents > 1) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'duplicate content region — a shell has exactly one',
        ),
      );
    }
  } else if (_shellSingles.contains(region)) {
    final prior = state.singlePaths[region];
    if (prior != null) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'duplicate $region region (already declared at $prior)',
        ),
      );
    } else {
      state.singlePaths[region] = path;
    }
  }

  if (slot != null) {
    final prior = state.slotPaths[slot];
    if (prior != null) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.slot',
          'slot "$slot" is also drawn at $prior',
        ),
      );
    } else {
      state.slotPaths[slot] = path;
    }
  }

  _shellSize(node['width'], '$path.width', issues);
  _shellSize(node['height'], '$path.height', issues);
  _shellInteger(node['flex'], '$path.flex', 0, 1000, issues);
  _shellNumber(node['minWidth'], '$path.minWidth', 0, 4000, issues);
  _shellNumber(node['maxWidth'], '$path.maxWidth', 0, 4000, issues);
  _shellNumber(node['minHeight'], '$path.minHeight', 0, 4000, issues);
  _shellNumber(node['maxHeight'], '$path.maxHeight', 0, 4000, issues);
  _shellNumber(node['collapsedSize'], '$path.collapsedSize', 0, 4000, issues);
  _shellInteger(node['zIndex'], '$path.zIndex', 0, 1000, issues);
  _shellInteger(node['focusOrder'], '$path.focusOrder', 0, 1000, issues);
  _bool(node, '$path.collapsible', issues);
  _shellString(node['label'], '$path.label', 80, issues);
  _shellString(node['hiddenWhen'], '$path.hiddenWhen', 200, issues);

  final overflow = node['overflow'];
  if (overflow != null &&
      (overflow is! String || !_shellOverflowModes.contains(overflow))) {
    issues.add(
      Issue(
        Severity.error,
        '$path.overflow',
        'must be one of ${_shellOverflowModes.join(', ')}',
      ),
    );
  }

  _shellSafeArea(node['safeArea'], '$path.safeArea', issues);
  _shellResizable(node['resizable'], '$path.resizable', issues);

  final storageKey = node['storageKey'];
  if (storageKey != null &&
      (storageKey is! String ||
          !RegExp(_shellStorageKeyPattern).hasMatch(storageKey))) {
    issues.add(
      Issue(
        Severity.error,
        '$path.storageKey',
        'must be a lowercase key of at most 64 characters '
            '(letters, digits, _, . and -)',
      ),
    );
  }
}

void _shellSize(Object? value, String path, List<Issue> issues) {
  if (value == null) return;
  if (value is num && value.isFinite && value >= 0 && value <= 4000) return;
  if (value == 'auto') return;
  if (value is String && RegExp(_shellPercentPattern).hasMatch(value)) return;
  issues.add(
    Issue(
      Severity.error,
      path,
      'must be pixels (0..4000), a percentage, or "auto"',
    ),
  );
}

void _shellNumber(
  Object? value,
  String path,
  double min,
  double max,
  List<Issue> issues,
) {
  if (value == null) return;
  if (value is num && value.isFinite && value >= min && value <= max) return;
  issues.add(
    Issue(
      Severity.error,
      path,
      'must be a number between ${min.toInt()} and ${max.toInt()}',
    ),
  );
}

void _shellInteger(
  Object? value,
  String path,
  int min,
  int max,
  List<Issue> issues,
) {
  if (value == null) return;
  if (value is num &&
      value.isFinite &&
      value == value.roundToDouble() &&
      value >= min &&
      value <= max) {
    return;
  }
  issues.add(
    Issue(Severity.error, path, 'must be an integer between $min and $max'),
  );
}

void _shellString(Object? value, String path, int max, List<Issue> issues) {
  if (value == null) return;
  if (value is String && value.length <= max) return;
  issues.add(
    Issue(Severity.error, path, 'must be a string of at most $max characters'),
  );
}

void _shellSafeArea(Object? raw, String path, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list of edges'));
    return;
  }
  final seen = <String>{};
  for (var i = 0; i < raw.length; i++) {
    final edge = raw[i];
    if (edge is! String || !_shellSafeAreas.contains(edge)) {
      issues.add(
        Issue(
          Severity.error,
          '$path[$i]',
          'must be one of ${_shellSafeAreas.join(', ')}',
        ),
      );
    } else if (!seen.add(edge)) {
      issues.add(Issue(Severity.error, '$path[$i]', 'duplicate edge "$edge"'));
    }
  }
}

void _shellResizable(Object? raw, String path, List<Issue> issues) {
  if (raw == null || raw is bool) return;
  if (raw is! Map) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'must be a boolean or a {edges, storageKey, min, max} object',
      ),
    );
    return;
  }

  _sweep(raw, path, const {'edges', 'storageKey', 'min', 'max'}, issues);
  final edges = raw['edges'];
  if (edges != null) {
    if (edges is! List) {
      issues.add(Issue(Severity.error, '$path.edges', 'must be a list'));
    } else {
      final seen = <String>{};
      for (var i = 0; i < edges.length; i++) {
        final edge = edges[i];
        if (edge is! String || !_shellResizeEdges.contains(edge)) {
          issues.add(
            Issue(
              Severity.error,
              '$path.edges[$i]',
              'must be one of ${_shellResizeEdges.join(', ')}',
            ),
          );
        } else if (!seen.add(edge)) {
          issues.add(
            Issue(Severity.error, '$path.edges[$i]', 'duplicate edge "$edge"'),
          );
        }
      }
    }
  }

  final storageKey = raw['storageKey'];
  if (storageKey != null &&
      (storageKey is! String ||
          !RegExp(_shellStorageKeyPattern).hasMatch(storageKey))) {
    issues.add(
      Issue(
        Severity.error,
        '$path.storageKey',
        'must be a lowercase key of at most 64 characters '
            '(letters, digits, _, . and -)',
      ),
    );
  }
  _shellNumber(raw['min'], '$path.min', 0, 4000, issues);
  _shellNumber(raw['max'], '$path.max', 0, 4000, issues);
}

/// Validates `layout.pinTargets`.
void _pinTargets(Object? raw, String path, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list of pin targets'));
    return;
  }

  final ids = <String, int>{};
  for (var i = 0; i < raw.length; i++) {
    final targetPath = '$path[$i]';
    final target = raw[i];
    if (target is! Map) {
      issues.add(Issue(Severity.error, targetPath, 'must be an object'));
      continue;
    }
    _sweep(target, targetPath, const {'id', 'label'}, issues);

    final id = target['id'];
    if (id is! String || id.trim().isEmpty || id.length > 64) {
      issues.add(
        Issue(
          Severity.error,
          '$targetPath.id',
          'must be a non-empty string of at most 64 characters',
        ),
      );
    } else if (ids.containsKey(id)) {
      issues.add(
        Issue(
          Severity.error,
          '$targetPath.id',
          'duplicate pin target id (already declared at index ${ids[id]})',
        ),
      );
    } else {
      ids[id] = i;
    }

    final label = target['label'];
    if (label != null && (label is! String || label.length > 80)) {
      issues.add(
        Issue(
          Severity.error,
          '$targetPath.label',
          'must be a string of at most 80 characters',
        ),
      );
    }
  }
}

void _pages(
  Object? raw,
  String path,
  List<Issue> issues,
  Set<String>? capabilities,
) {
  if (raw == null) return;
  if (raw is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list of pages'));
    return;
  }
  if (raw.length > 32) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'more than 32 pages — the host rejects the theme',
      ),
    );
  }
  if (raw.isNotEmpty &&
      capabilities != null &&
      !capabilities.contains('ui.pages')) {
    issues.add(
      Issue(Severity.error, path, 'pages require the ui.pages capability'),
    );
  }

  final ids = <String>{};
  for (var i = 0; i < raw.length; i++) {
    final pagePath = '$path[$i]';
    final page = raw[i];
    if (page is! Map) {
      issues.add(Issue(Severity.error, pagePath, 'must be an object'));
      continue;
    }
    _sweep(page, pagePath, _pageKeys, issues);

    final id = page['id'];
    if (id is! String || !RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(id)) {
      issues.add(
        Issue(
          Severity.error,
          '$pagePath.id',
          'must be a lowercase page id of at most 32 characters',
        ),
      );
    } else if (!ids.add(id)) {
      issues.add(Issue(Severity.error, '$pagePath.id', 'duplicate page id'));
    }

    _string(page, '$pagePath.title', 80, issues);
    _string(page, '$pagePath.icon', 64, issues);
    _string(page, '$pagePath.parent', 64, issues);
    _bool(page, '$pagePath.showBack', issues);
    _bool(page, '$pagePath.visible', issues);
  }
}

void _pageVisibility(Object? raw, String path, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  for (final entry in raw.entries) {
    final page = entry.value;
    if (page is! Map) {
      issues.add(
        Issue(Severity.error, '$path.${entry.key}', 'must be an object'),
      );
      continue;
    }
    _sweep(page, '$path.${entry.key}', const {'visible'}, issues);
    _bool(page, '$path.${entry.key}.visible', issues);
  }
}

/// The pin targets a document declares, or the host default when it declares
/// none. `library.playlists` and `library.pins` name one of these to decide
/// which list they render.
Set<String> _declaredPinTargets(Map<String, dynamic> payload) {
  final layout = payload['layout'];
  final raw = layout is Map ? layout['pinTargets'] : null;
  if (raw is! List) return const {'sidebar'};
  final ids = <String>{};
  for (final target in raw) {
    if (target is Map && target['id'] is String) ids.add(target['id'] as String);
  }
  return ids.isEmpty ? const {'sidebar'} : ids;
}

/// Checks one `hostWidget` node against the closed registry.
///
/// The distinction is deliberate: an id the host does not mount is a warning
/// because the theme still loads and the slot is simply empty, while a prop the
/// widget never reads is an error because it is a typo that would otherwise sit
/// unnoticed in a document that looks valid.
void _hostWidget(
  Map node,
  String path,
  Set<String> pinTargets,
  List<Issue> issues,
) {
  final id = node['id'];
  if (id is! String || !v4HostWidgetIds.contains(id)) {
    issues.add(
      Issue(
        Severity.warning,
        '$path.id',
        'not a host widget the host mounts — ignored at runtime',
      ),
    );
    return;
  }

  // A missing or malformed bag is reported by the node walk; there is nothing
  // left to check here.
  final props = node['props'];
  if (props is! Map) return;

  final allowed = v4HostWidgetProps[id]!;
  for (final key in props.keys) {
    if (key is String && allowed.contains(key)) continue;
    issues.add(
      Issue(
        Severity.error,
        '$path.props.$key',
        'not a prop of the "$id" host widget — the host ignores it',
      ),
    );
  }

  for (final key in allowed) {
    if (!_hostWidgetBoolProps.contains(key)) continue;
    _bool(props, '$path.props.$key', issues);
  }

  for (final entry in _hostWidgetCountProps.entries) {
    if (!allowed.contains(entry.key)) continue;
    final value = props[entry.key];
    if (value == null) continue;
    if (value is! num ||
        !value.isFinite ||
        value.roundToDouble() != value.toDouble() ||
        value < entry.value.min ||
        value > entry.value.max) {
      issues.add(
        Issue(
          Severity.error,
          '$path.props.${entry.key}',
          'must be a whole number between ${entry.value.min} '
              'and ${entry.value.max}',
        ),
      );
    }
  }

  for (final entry in _hostWidgetEnumProps.entries) {
    if (!allowed.contains(entry.key)) continue;
    _enum(props, '$path.props.${entry.key}', entry.value, issues);
  }

  for (final entry in _hostWidgetStringProps.entries) {
    if (!allowed.contains(entry.key)) continue;
    _string(props, '$path.props.${entry.key}', entry.value, issues);
  }

  if (allowed.contains('scope')) {
    final value = props['scope'];
    if (value != null &&
        (value is! String || !_hostWidgetScopePattern.hasMatch(value))) {
      issues.add(
        Issue(
          Severity.error,
          '$path.props.scope',
          'must be 1-32 letters, digits, dashes or underscores',
        ),
      );
    }
  }

  for (final key in _hostWidgetTargetProps) {
    if (!allowed.contains(key)) continue;
    final value = props[key];
    if (value is! String || pinTargets.contains(value)) continue;
    issues.add(
      Issue(
        Severity.warning,
        '$path.props.$key',
        'not a declared pin target — the host falls back to the sidebar',
      ),
    );
  }
}

void _capabilityUsage(
  Map<String, dynamic> payload,
  Set<String> granted,
  List<Issue> issues,
) {
  final pinTargets = _declaredPinTargets(payload);

  void checkBinding(Map node, String path) {
    void checkName(String? name, String key) {
      if (name == null) return;
      final resolved = name.startsWith('!') ? name.substring(1) : name;
      if (resolved.startsWith('audio.') && !granted.contains('audio.effects')) {
        issues.add(
          Issue(
            Severity.error,
            '$path.$key',
            'reading $resolved requires the audio.effects capability',
          ),
        );
      }
      if ((resolved.startsWith('library.') || resolved.startsWith('item.')) &&
          !granted.contains('library.read')) {
        issues.add(
          Issue(
            Severity.error,
            '$path.$key',
            'reading $resolved requires the library.read capability',
          ),
        );
      }
    }

    void checkCondition(Object? raw, String key) {
      if (raw is String) {
        checkName(raw, key);
        return;
      }
      if (raw is! Map) return;
      final bind = raw['bind'];
      if (bind is String) checkName(bind, '$key.bind');
      for (final listKey in const ['allOf', 'anyOf']) {
        final entries = raw[listKey];
        if (entries is! List) continue;
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] is Map || entries[i] is String) {
            checkCondition(entries[i], '$key.$listKey[$i]');
          }
        }
      }
    }

    for (final key in const [
      'bind',
      'maxBind',
      'disabledWhen',
      'hiddenWhen',
      'openBind',
      'pageBind',
      'selectedBind',
      'valueBind',
    ]) {
      final raw = node[key];
      if (raw == null) continue;
      if (key == 'disabledWhen' || key == 'hiddenWhen') {
        checkCondition(raw, key);
      } else if (raw is String) {
        checkName(raw, key);
      }
    }
  }

  void checkAction(Object? raw, String path) {
    if (raw is! Map) return;
    final type = raw['type'];
    if (type is! String) return;
    final required = _actionCapabilities[type];
    if (required != null && !granted.contains(required)) {
      issues.add(
        Issue(
          Severity.error,
          '$path.type',
          '$type requires the $required capability',
        ),
      );
    }
  }

  // Templates named by `itemTemplate`/`rowTemplate` are item content: a blur
  // inside one runs a backdrop filter per row, which is the per-row frost the
  // host docs warn against. Collected during the walk, checked in a second
  // pass over `ui.templates`.
  final itemTemplateNames = <String>{};

  /// Sigma of a node's `blur` prop (flat or under `props`), 0 when absent.
  double _blurSigma(Map node) {
    Object? raw = node['blur'];
    final props = node['props'];
    if (raw == null && props is Map) raw = props['blur'];
    return raw is num && raw.isFinite ? raw.toDouble() : 0;
  }

  void walkNode(Object? raw, String path, {bool inItemTemplate = false}) {
    if (raw is! Map) return;
    final node = raw;
    final type = node['type'];

    final templateRef = node['itemTemplate'] ?? node['rowTemplate'];
    if (templateRef is String && templateRef.trim().isNotEmpty) {
      itemTemplateNames.add(templateRef.trim());
    }

    if (inItemTemplate &&
        (type == 'box' || type == 'card') &&
        _blurSigma(node) > 0) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'blur inside an item template runs a backdrop filter per row — '
              'frost the list container instead',
        ),
      );
    }

    if (type == 'hostWidget') {
      if (!granted.contains('ui.hostWidgets')) {
        issues.add(
          Issue(
            Severity.error,
            path,
            'hostWidget requires the ui.hostWidgets capability',
          ),
        );
      }
      _hostWidget(node, path, pinTargets, issues);
    }
    checkBinding(node.cast<String, dynamic>(), path);
    checkAction(node['action'], '$path.action');
    final actions = node['actions'];
    if (actions is List) {
      for (var i = 0; i < actions.length; i++) {
        checkAction(actions[i], '$path.actions[$i]');
      }
    }
    final children = node['children'];
    if (children is List) {
      // The children of a repeating node ARE the item template: a list row,
      // a carousel card, a table row. Everything below inherits the flag.
      final childInItem = inItemTemplate ||
          type == 'list' ||
          type == 'virtualList' ||
          type == 'carousel';
      for (var i = 0; i < children.length; i++) {
        walkNode(children[i], '$path.children[$i]',
            inItemTemplate: childInItem);
      }
    }
  }

  /// Blur-only pass for templates referenced by `itemTemplate`/`rowTemplate`.
  /// Runs after the main walk so every referencing node has been seen; it
  /// does not re-run the other checks, which the first pass already did.
  void warnItemBlur(Object? raw, String path) {
    if (raw is! Map) return;
    final node = raw;
    final type = node['type'];
    if ((type == 'box' || type == 'card') && _blurSigma(node) > 0) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'blur inside an item template runs a backdrop filter per row — '
              'frost the list container instead',
        ),
      );
    }
    final children = node['children'];
    if (children is List) {
      for (var i = 0; i < children.length; i++) {
        warnItemBlur(children[i], '$path.children[$i]');
      }
    }
  }

  void walkTree(Object? raw, String path,
      {bool inItemTemplate = false}) {
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        walkNode(raw[i], '$path[$i]', inItemTemplate: inItemTemplate);
      }
    } else if (raw is Map) {
      walkNode(raw, path, inItemTemplate: inItemTemplate);
    }
  }

  final ui = payload['ui'];
  if (ui is Map) {
    final slots = ui['slots'];
    if (slots is Map) {
      for (final entry in slots.entries) {
        final slot = entry.value;
        if (slot is Map) {
          walkTree(slot['children'], 'ui.slots.${entry.key}');
        }
      }
    }
    final screens = ui['screens'];
    if (screens is Map) {
      for (final entry in screens.entries) {
        final screen = entry.value;
        if (screen is Map) {
          walkTree(screen['children'], 'ui.screens.${entry.key}');
        }
      }
    }
    final templates = ui['templates'];
    if (templates is Map) {
      for (final entry in templates.entries) {
        final template = entry.value;
        if (template is Map) {
          walkTree(template['children'], 'ui.templates.${entry.key}');
          if (itemTemplateNames.contains(entry.key)) {
            warnItemBlur(
                template['children'], 'ui.templates.${entry.key}');
          }
        }
      }
    }
    final menus = ui['menus'];
    if (menus is Map) {
      for (final entry in menus.entries) {
        final rows = entry.value;
        if (rows is! List) continue;
        for (var i = 0; i < rows.length && i < 32; i++) {
          final row = rows[i];
          if (row is! Map) continue;
          checkAction(row['action'], 'ui.menus.${entry.key}[$i].action');
          final declared = row['capability'];
          if (declared is String && !granted.contains(declared)) {
            issues.add(
              Issue(
                Severity.error,
                'ui.menus.${entry.key}[$i].capability',
                'the document does not grant $declared',
              ),
            );
          }
        }
      }
    }
  }
}

void _enum(Map map, String path, Set<String> allowed, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! String || !allowed.contains(value)) {
    issues.add(
      Issue(Severity.error, path, 'must be one of ${allowed.join(', ')}'),
    );
  }
}

void _size(Map map, String path, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! num || !value.isFinite || value < 0 || value > 1000) {
    issues.add(
      Issue(Severity.error, path, 'must be a width between 0 and 1000'),
    );
  }
}

void _string(Map map, String path, int max, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! String || value.length > max) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'must be a string of at most $max characters',
      ),
    );
  }
}

void _bool(Map map, String path, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! bool) {
    issues.add(Issue(Severity.error, path, 'must be a boolean'));
  }
}
