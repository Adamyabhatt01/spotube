import 'validator.dart';
import 'v3_validator.dart';

/// The keys a v4 payload may carry at the top level.
///
/// v4 is a breaking contract: the v3 escape-hatch key `dynamic` is not part of
/// it, and every other key is listed here. `light` and `dark` remain from v2
/// because every theme still has to carry both palettes.
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
/// appears.
const v4EnvelopeProps = <String>[
  'bind',
  'disabledWhen',
  'hiddenWhen',
  'kit',
  'variant',
  'animate',
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
  ],
  'grid': ['columns', 'gap'],
  'resizable': ['direction', 'initial', 'min', 'max', 'storageKey'],
  'safeArea': ['edges'],
  'aspectRatio': ['ratio'],
  'kitScope': [],
  'badge': ['text', 'variant'],
  'chip': ['label', 'selectedBind'],
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
  'contextMenu': ['items'],
  'breadcrumb': ['items'],
  'pagination': ['pageBind', 'pageCount'],
  'dialog': ['title', 'description', 'openBind'],
  'sheet': ['side', 'width', 'openBind'],
  'popover': ['placement', 'trigger'],
  'tooltip': ['text', 'placement'],
  'virtualList': ['itemTemplate', 'itemExtent', 'overscan', 'limit', 'filter'],
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
  'list': ['filter'],
  'progress': ['style'],
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
  'app.sidebarCollapsed',
  'app.asideOpen',
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
  return RegExp(
    r'^(item|home|collection|artist|search|library|queue|downloads|stats)\.'
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
  'setQuery',
  'clearQuery',
  'setSetting',
  'toggleSetting',
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
  for (final key in raw.keys) {
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

void _capabilityUsage(
  Map<String, dynamic> payload,
  Set<String> granted,
  List<Issue> issues,
) {
  void checkBinding(Map node, String path) {
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
      if (raw is! String) continue;
      final name = raw.startsWith('!') ? raw.substring(1) : raw;
      if (name.startsWith('audio.') && !granted.contains('audio.effects')) {
        issues.add(
          Issue(
            Severity.error,
            '$path.$key',
            'reading $name requires the audio.effects capability',
          ),
        );
      }
      if ((name.startsWith('library.') || name.startsWith('item.')) &&
          !granted.contains('library.read')) {
        issues.add(
          Issue(
            Severity.error,
            '$path.$key',
            'reading $name requires the library.read capability',
          ),
        );
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

  void walkNode(Object? raw, String path) {
    if (raw is! Map) return;
    final node = raw;
    if (node['type'] == 'hostWidget' && !granted.contains('ui.hostWidgets')) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'hostWidget requires the ui.hostWidgets capability',
        ),
      );
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
      for (var i = 0; i < children.length; i++) {
        walkNode(children[i], '$path.children[$i]');
      }
    }
  }

  void walkTree(Object? raw, String path) {
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        walkNode(raw[i], '$path[$i]');
      }
    } else if (raw is Map) {
      walkNode(raw, path);
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
