import 'validator.dart';

/// The v3 blocks: the keys a payload declares with `specVersion: 3` may carry
/// on top of the v2 ones.
const v3TopLevelKeys = <String>[
  'specVersion',
  'typography',
  'spacing',
  'motion',
  'scale',
  'icons',
  'components',
  'layout',
  'branding',
  'assets',
  'ui',
  'ext',
];

/// The extra colour roles a v3 palette may define.
///
/// The v2 seventeen are required; these are optional and fall back to the
/// roles they alias. They are the roles the app draws with that have no v2
/// name of their own — a sidebar, a popover, a chart, a status colour.
const v3PaletteRoles = <String>[
  'popover',
  'popoverForeground',
  'sidebar',
  'sidebarForeground',
  'sidebarPrimary',
  'sidebarPrimaryForeground',
  'sidebarAccent',
  'sidebarAccentForeground',
  'sidebarBorder',
  'sidebarRing',
  'success',
  'successForeground',
  'warning',
  'warningForeground',
  'info',
  'infoForeground',
  'chart1',
  'chart2',
  'chart3',
  'chart4',
  'chart5',
  'chart6',
];

/// The ids a theme may use for the shell's navigation and sections.
///
/// A theme that names an id the app does not know is a theme that hides a
/// piece of the interface nobody can get back, so the list is closed.
const navIds = <String>['home', 'radio', 'stats', 'search'];
const navbarIds = <String>['home', 'search', 'radio', 'library', 'stats'];
const libraryIds = <String>[
  'playlists',
  'artists',
  'albums',
  'stations',
  'local_library',
];
const homeSectionIds = <String>['recent', 'featured', 'new_releases', 'browse'];
const settingsSectionIds = <String>[
  'accounts',
  'language_region',
  'appearance',
  'sidebar',
  'playback',
  'downloads',
  'desktop',
  'developers',
  'about',
];

/// The slots the host publishes, and the only names a theme may fill.
///
/// A slot name is a promise about where the content ends up. The list is
/// closed on purpose: a theme that names a slot the host does not have would
/// otherwise be silently dropped, and the author would never know.
const slotNames = <String>[
  'sidebar.header',
  'sidebar.footer',
  'sidebar.nav.before',
  'sidebar.nav.after',
  'sidebar.library.before',
  'sidebar.library.after',
  'sidebar.pins.before',
  'sidebar.pins.after',
  'player.leading',
  'player.controls',
  'player.trailing',
  'player.progress',
  'stage.center',
  'stage.below',
  'app.overlay',
  'shell.before',
  'shell.after',
  'home.before_sections',
  'home.after_sections',
  'home.content',
  'lyrics.header',
  'lyrics.after_tabs',
  'settings.before',
  'settings.after',
  'collection.content',
  'collection.header',
  'collection.before_tracks',
  'collection.after_tracks',
  'artist.content',
  'artist.header',
  'search.content',
  'library.content',
  'queue.content',
  'downloads.content',
  'stats.content',
];

/// The layout keys a theme may take ownership of.
const enforceIds = <String>[
  'nav',
  'navItems',
  'navbarItems',
  'libraryItems',
  'navOrder',
  'player',
  'playerDock',
  'volume',
  'home',
  'settings',
  'titlebar',
  'splash',
];

/// The component groups the app knows how to restyle.
const componentGroups = <String>[
  'buttons',
  'card',
  'player',
  'input',
  'tabs',
  'nav',
  'tooltip',
  'badge',
  'select',
  'switch',
  'slider',
  'scrollbar',
  'avatar',
  'skeleton',
  'progress',
  'divider',
  'menu',
  'dropdown',
  'modal',
  'dialog',
  'sheet',
  'table',
  'checkbox',
  'radio',
  'toggle',
  'toggleGroup',
  'accordion',
  'alert',
  'breadcrumb',
  'carousel',
  'collapsible',
  'command',
  'contextMenu',
  'drawer',
  'hoverCard',
  'pagination',
  'popover',
  'resizable',
  'sidebar',
  'stepper',
  'toast',
  'tree',
];

/// The button variants a theme may style separately.
const buttonVariants = <String>[
  'primary',
  'secondary',
  'outline',
  'ghost',
  'destructive',
  'link',
  'fixed',
  'muted',
];

/// The node types the renderer knows.
const uiNodeTypes = <String>[
  'row',
  'column',
  'stack',
  'wrap',
  'padding',
  'align',
  'expanded',
  'scroll',
  'text',
  'icon',
  'image',
  'button',
  'card',
  'search',
  'divider',
  'spacer',
  'gap',
  'conditional',
  'template',
  'animate',
  'progress',
  'list',
];

/// The actions the host dispatches on a theme's behalf.
const uiActionTypes = <String>[
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
];

/// Whether [name] is a binding the host resolves.
///
/// `item.*` and the page scopes are open on purpose: a collection entry's and
/// a page's fields are defined by the host's metadata model, and a future field
/// must not require a build validator release. They only resolve where the
/// host publishes that scope.
bool isUiBinding(String name) {
  if (uiBindings.contains(name)) return true;
  return RegExp(
    r'^(item|home|collection|artist|search|library|queue|downloads|stats)\.'
    r'[A-Za-z][A-Za-z0-9_]{0,31}$',
  ).hasMatch(name);
}

/// The data a theme's UI can bind to.
const uiBindings = <String>[
  'player.trackId',
  'player.title',
  'player.artist',
  'player.album',
  'player.artwork',
  'player.playing',
  'player.loop',
  'player.shuffled',
  'player.position',
  'player.duration',
  'player.volume',
  'user.name',
  'user.avatar',
  'app.version',
  'app.brightness',
  'app.themeMode',
  'app.greeting',
  'clock.now',
];

/// The type sizes a text node may name.
const uiTextSizes = <String>[
  'xs',
  'small',
  'sm',
  'md',
  'lg',
  'xl',
  '2xl',
  '3xl',
  '4xl',
  '5xl',
  '6xl',
];

/// The weights a text node may name, when it does not use a number.
const uiFontWeights = <String>[
  'thin',
  'light',
  'normal',
  'medium',
  'semibold',
  'bold',
  'black',
];

/// Where a row or column places its children across the axis.
const uiAlignments = <String>['start', 'center', 'end', 'stretch'];

/// How a row or column distributes its children along the axis.
const uiJustifications = <String>[
  'start',
  'center',
  'end',
  'spaceBetween',
  'spaceAround',
  'spaceEvenly',
];

/// Where a stack pins a child, and where an align node places it.
const uiStackAlignments = <String>[
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
];

/// How a text node flows past its width.
const uiOverflows = <String>['clip', 'ellipsis', 'fade'];

/// How an image fits its box.
const uiImageFits = <String>['cover', 'contain', 'fill', 'none'];

/// How an image is sampled. `nearest` keeps pixel art crisp.
const uiImageFilters = <String>['linear', 'nearest'];

/// What an image node may draw, besides an `asset://` path.
const uiImageSources = <String>['albumArt', 'player.artwork', 'user.avatar'];

/// The loops an animate node may run.
const uiAnimationKinds = <String>['rotate', 'pulse', 'float', 'fade'];

/// The curves an animation may use.
const uiAnimationCurves = <String>[
  'linear',
  'ease',
  'easeIn',
  'easeOut',
  'easeInOut',
  'easeOutCubic',
  'easeInOutCubic',
];

/// The keys of a node that are structure, not props.
const uiStructuralKeys = <String>{
  'type',
  'children',
  'props',
  'action',
  'actions',
};

/// The props each node type reads.
///
/// Closed on purpose: an unknown prop is a typo, and a typo the host ignores
/// is a theme that silently does not do what its author wrote. `props` is
/// accepted as the original shape and merged into the flat one.
const uiNodeProps = <String, List<String>>{
  'row': ['gap', 'align', 'justify'],
  'column': ['gap', 'align', 'justify'],
  'stack': ['align', 'fit'],
  'wrap': ['gap', 'runGap', 'align', 'justify'],
  'padding': [
    'all',
    'horizontal',
    'vertical',
    'top',
    'right',
    'bottom',
    'left',
  ],
  'align': ['align', 'widthFactor', 'heightFactor'],
  'expanded': ['flex'],
  'scroll': ['direction', 'padding'],
  'text': [
    'text',
    'bind',
    'size',
    'weight',
    'color',
    'maxLines',
    'align',
    'overflow',
    'family',
    'letterSpacing',
    'uppercase',
  ],
  'icon': ['icon', 'size', 'color'],
  'image': [
    'src',
    'bind',
    'width',
    'height',
    'radius',
    'shape',
    'fit',
    'filter',
    'tile',
    'opacity',
  ],
  'button': ['label', 'icon', 'variant', 'size', 'disabledWhen'],
  'card': [
    'padding',
    'radius',
    'background',
    'hoverBackground',
    'borderColor',
    'borderWidth',
    'opacity',
    'width',
    'height',
  ],
  'search': ['placeholder'],
  'divider': ['orientation', 'thickness', 'color'],
  'spacer': ['flex'],
  'gap': ['size'],
  'conditional': ['bind', 'equals', 'invert'],
  'template': ['name', 'args'],
  'animate': ['kind', 'duration', 'curve', 'bind', 'reverse'],
  'progress': [
    'bind',
    'maxBind',
    'width',
    'height',
    'hitHeight',
    'radius',
    'borderWidth',
    'borderColor',
    'color',
    'trackColor',
    'thumbColor',
    'thumbSize',
    'interactive',
  ],
  'list': ['bind', 'gap', 'limit', 'align', 'direction'],
};

/// The colour roles a `@role` reference may name.
const roleNames = <String>[
  'primary',
  'primaryForeground',
  'secondary',
  'secondaryForeground',
  'accent',
  'accentForeground',
  'muted',
  'mutedForeground',
  'destructive',
  'destructiveForeground',
  'background',
  'foreground',
  'card',
  'cardForeground',
  'border',
  'input',
  'ring',
  'success',
  'warning',
  'info',
  'popover',
  'popoverForeground',
  'sidebar',
  'sidebarForeground',
  'sidebarPrimary',
  'sidebarPrimaryForeground',
  'sidebarAccent',
  'sidebarAccentForeground',
  'sidebarBorder',
  'sidebarRing',
  'chart1',
  'chart2',
  'chart3',
  'chart4',
  'chart5',
  'chart6',
];

/// The limits a UI tree may not exceed.
const maxUiDepth = 12;
const maxUiNodesPerSlot = 200;
const maxUiNodesTotal = 1000;
const maxUiTextLength = 500;
const maxUiActionsPerNode = 4;
const maxCustomTokens = 32;

/// Validates the v3 blocks of a payload.
///
/// The v2 part is validated by the caller; this is the other half of the
/// contract — the blocks that only a v3 host reads. The rules are the ones
/// the host will enforce, so a theme that passes here is a theme the host can
/// render without clamping anything to the point of being wrong.
List<Issue> validateV3Blocks(Map<String, dynamic> payload) {
  final issues = <Issue>[];

  final specVersion = payload['specVersion'];
  if (specVersion is! num || specVersion < 3) {
    issues.add(
      Issue(
        Severity.error,
        'specVersion',
        'must be 3 or more to declare the v3 blocks',
      ),
    );
    return issues;
  }

  _paletteExtras(payload['light'], 'light', issues);
  _paletteExtras(payload['dark'], 'dark', issues);
  _typography(payload['typography'], issues);
  _spacing(payload['spacing'], issues);
  _motion(payload['motion'], issues);
  _scale(payload['scale'], issues);
  _icons(payload['icons'], issues);
  _components(payload['components'], issues);
  _shellLayout(payload['layout'], issues);
  _branding(payload['branding'], issues);
  _assets(payload['assets'], issues);
  _ui(payload['ui'], issues);

  // `ext` is the escape hatch: a theme may carry data the host does not
  // know, and the host must ignore it rather than reject the payload.
  final ext = payload['ext'];
  if (ext != null && ext is! Map) {
    issues.add(const Issue(Severity.error, 'ext', 'must be an object'));
  }

  return issues;
}

/// The optional colour roles of a palette.
void _paletteExtras(Object? raw, String path, List<Issue> issues) {
  if (raw is! Map) return;
  final palette = raw.cast<String, dynamic>();
  for (final role in v3PaletteRoles) {
    final value = palette[role];
    if (value == null) continue;
    if (value is! String || !_isHex(value)) {
      issues.add(
        Issue(
          Severity.error,
          '$path.$role',
          'must be a #RRGGBB or #AARRGGBB color',
        ),
      );
    }
  }
}

/// The `typography` block.
void _typography(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'typography', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  for (final key in ['family', 'monoFamily', 'brandFamily']) {
    final value = block[key];
    if (value == null) continue;
    if (value is! String || value.length > 64) {
      issues.add(
        Issue(
          Severity.warning,
          'typography.$key',
          'must be a family name of at most 64 characters — dropped',
        ),
      );
    }
  }

  final styles = block['styles'];
  if (styles != null) {
    if (styles is! Map) {
      issues.add(
        const Issue(Severity.error, 'typography.styles', 'must be an object'),
      );
    } else {
      final map = styles.cast<String, dynamic>();
      if (map.length > 32) {
        issues.add(
          Issue(
            Severity.warning,
            'typography.styles',
            'more than 32 style overrides — the extras are dropped',
            resolved: 32,
          ),
        );
      }
      for (final entry in map.entries) {
        _textStyle('typography.styles.${entry.key}', entry.value, issues);
      }
    }
  }

  final fonts = block['fonts'];
  if (fonts != null) {
    if (fonts is! List) {
      issues.add(
        const Issue(Severity.error, 'typography.fonts', 'must be a list'),
      );
    } else {
      if (fonts.length > 8) {
        issues.add(
          Issue(
            Severity.warning,
            'typography.fonts',
            'more than 8 font files — the extras are dropped',
            resolved: 8,
          ),
        );
      }
      for (var i = 0; i < fonts.length && i < 8; i++) {
        final font = fonts[i];
        if (font is! Map) {
          issues.add(
            Issue(Severity.error, 'typography.fonts[$i]', 'must be an object'),
          );
          continue;
        }
        final family = font['family'];
        if (family is! String || family.isEmpty || family.length > 64) {
          issues.add(
            Issue(
              Severity.error,
              'typography.fonts[$i].family',
              'must be a family name of at most 64 characters',
            ),
          );
        }
        _assetPath('typography.fonts[$i].asset', font['asset'], issues);
      }
    }
  }
}

/// One typography style override.
void _textStyle(String path, Object? raw, List<Issue> issues) {
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  final style = raw.cast<String, dynamic>();

  _number(style, '$path.fontSize', min: 8, max: 96, issues: issues);
  _number(style, '$path.fontWeight', min: 100, max: 900, issues: issues);
  _number(style, '$path.height', min: 0.8, max: 2.4, issues: issues);
  _number(style, '$path.letterSpacing', min: -2, max: 8, issues: issues);
  if (style['color'] != null) {
    _colorOrRole('$path.color', style['color'], issues);
  }

  final family = style['fontFamily'];
  if (family != null && (family is! String || family.length > 64)) {
    issues.add(
      Issue(
        Severity.warning,
        '$path.fontFamily',
        'must be a family name of at most 64 characters — dropped',
      ),
    );
  }

  final fontStyle = style['fontStyle'];
  if (fontStyle != null && fontStyle != 'normal' && fontStyle != 'italic') {
    issues.add(
      Issue(
        Severity.warning,
        '$path.fontStyle',
        'must be normal or italic — dropped',
      ),
    );
  }

  final borderStyle = style['borderStyle'];
  if (borderStyle != null && borderStyle != 'solid' && borderStyle != 'pixel') {
    issues.add(
      Issue(
        Severity.warning,
        '$path.borderStyle',
        'must be solid or pixel — the host draws solid',
      ),
    );
  }
}

/// The `spacing` block.
void _spacing(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'spacing', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();
  for (final key in [
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
  ]) {
    _number(block, 'spacing.$key', min: 0, max: 96, issues: issues);
  }
  _customTokens(block, 'spacing.custom', issues);
}

/// The `motion` block.
void _motion(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'motion', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();
  for (final key in ['fast', 'normal', 'slow', 'pageTransition', 'sheet']) {
    _number(block, 'motion.$key', min: 0, max: 1000, issues: issues);
  }

  const easings = [
    'linear',
    'ease',
    'easeIn',
    'easeOut',
    'easeInOut',
    'easeOutCubic',
    'easeInOutCubic',
  ];
  final easing = block['easing'];
  if (easing != null && (easing is! String || !easings.contains(easing))) {
    issues.add(
      Issue(
        Severity.warning,
        'motion.easing',
        'must be one of ${easings.join(', ')} — the host falls back',
        resolved: 'easeOutCubic',
      ),
    );
  }
  _customTokens(block, 'motion.custom', issues);
}

/// The `scale` block.
void _scale(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'scale', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();
  for (final key in ['size', 'text', 'radius', 'icon', 'spacing']) {
    _number(block, 'scale.$key', min: 0.5, max: 2, issues: issues);
  }
}

/// The `icons` block.
void _icons(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'icons', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();
  for (final key in ['sm', 'md', 'lg', 'xl']) {
    _number(block, 'icons.$key', min: 8, max: 64, issues: issues);
  }

  final overrides = block['overrides'];
  if (overrides is Map) {
    for (final entry in overrides.entries) {
      final value = entry.value;
      if (value is! Map) {
        issues.add(
          Issue(
            Severity.error,
            'icons.overrides.${entry.key}',
            'must be an object',
          ),
        );
        continue;
      }
      final icon = value.cast<String, dynamic>();
      if (icon['asset'] != null) {
        _assetPath('icons.overrides.${entry.key}.asset', icon['asset'], issues);
      }
      _number(
        icon,
        'icons.overrides.${entry.key}.size',
        min: 8,
        max: 64,
        issues: issues,
      );
    }
  }
  _customTokens(block, 'icons.custom', issues);
}

/// The `components` block.
void _components(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'components', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  for (final entry in block.entries) {
    if (!componentGroups.contains(entry.key)) {
      issues.add(
        Issue(
          Severity.warning,
          'components.${entry.key}',
          'not a component the app knows — ignored',
        ),
      );
      continue;
    }

    if (entry.key == 'buttons') {
      final buttons = entry.value;
      if (buttons is! Map) {
        issues.add(
          const Issue(
            Severity.error,
            'components.buttons',
            'must be an object',
          ),
        );
        continue;
      }
      for (final button in buttons.entries) {
        if (!buttonVariants.contains(button.key)) {
          issues.add(
            Issue(
              Severity.warning,
              'components.buttons.${button.key}',
              'not a button variant the app knows — ignored',
            ),
          );
          continue;
        }
        _componentStyle(
          'components.buttons.${button.key}',
          button.value,
          issues,
        );
      }
      continue;
    }

    _componentStyle('components.${entry.key}', entry.value, issues);
  }
}

/// One component style.
void _componentStyle(String path, Object? raw, List<Issue> issues) {
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  final style = raw.cast<String, dynamic>();

  _number(style, '$path.padding', min: 0, max: 48, issues: issues);
  _number(style, '$path.margin', min: 0, max: 48, issues: issues);
  _number(style, '$path.gap', min: 0, max: 48, issues: issues);
  // A radius may be a pill: the host clamps a round shape to the shorter
  // side, so 999 means "fully round", not "too big".
  _number(style, '$path.radius', min: 0, max: 999, issues: issues);
  _number(style, '$path.borderWidth', min: 0, max: 8, issues: issues);
  _number(style, '$path.height', min: 0, max: 400, issues: issues);
  _number(style, '$path.width', min: 0, max: 400, issues: issues);
  _number(style, '$path.surfaceOpacity', min: 0, max: 1, issues: issues);
  _number(style, '$path.surfaceBlur', min: 0, max: 64, issues: issues);
  _number(style, '$path.fontSize', min: 8, max: 48, issues: issues);
  _number(style, '$path.fontWeight', min: 100, max: 900, issues: issues);
  _number(style, '$path.iconSize', min: 8, max: 64, issues: issues);
  _number(style, '$path.letterSpacing', min: -2, max: 8, issues: issues);

  for (final key in ['background', 'foreground', 'borderColor']) {
    if (style[key] != null) {
      _colorOrRole('$path.$key', style[key], issues);
    }
  }
  for (final key in ['indicatorColor', 'thumbColor', 'trackColor']) {
    if (style[key] != null) {
      _colorOrRole('$path.$key', style[key], issues);
    }
  }

  final family = style['fontFamily'];
  if (family != null && (family is! String || family.length > 64)) {
    issues.add(
      Issue(
        Severity.warning,
        '$path.fontFamily',
        'must be a family name of at most 64 characters — dropped',
      ),
    );
  }

  final fontStyle = style['fontStyle'];
  if (fontStyle != null && fontStyle != 'normal' && fontStyle != 'italic') {
    issues.add(
      Issue(
        Severity.warning,
        '$path.fontStyle',
        'must be normal or italic — dropped',
      ),
    );
  }

  final borderStyle = style['borderStyle'];
  if (borderStyle != null && borderStyle != 'solid' && borderStyle != 'pixel') {
    issues.add(
      Issue(
        Severity.warning,
        '$path.borderStyle',
        'must be solid or pixel — the host draws solid',
      ),
    );
  }
}

/// The v3 parts of the `layout` block.
void _shellLayout(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'layout', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  _idList(block, 'layout.navItems', navIds, issues, allowScreens: true);
  _idList(block, 'layout.navbarItems', navbarIds, issues, allowScreens: true);
  _idList(block, 'layout.libraryItems', libraryIds, issues, allowScreens: true);

  final enforce = block['enforce'];
  if (enforce != null) {
    if (enforce is! List) {
      issues.add(
        const Issue(Severity.error, 'layout.enforce', 'must be a list'),
      );
    } else {
      for (final value in enforce) {
        if (value is! String || !enforceIds.contains(value)) {
          issues.add(
            Issue(
              Severity.warning,
              'layout.enforce',
              'unknown key — the host ignores it',
            ),
          );
        }
      }
    }
  }

  final player = block['player'];
  if (player is Map) {
    final flags = player.cast<String, dynamic>();
    const docks = ['full', 'compact', 'floating', 'stage'];
    final dock = flags['dock'];
    if (dock != null && (dock is! String || !docks.contains(dock))) {
      issues.add(
        Issue(
          Severity.warning,
          'layout.player.dock',
          'must be one of ${docks.join(', ')} — the host falls back',
          resolved: 'full',
        ),
      );
    }
    for (final key in [
      'showTrackDetails',
      'showActions',
      'showVolume',
      'showLyrics',
      'showProgress',
    ]) {
      final value = flags[key];
      if (value != null && value is! bool) {
        issues.add(
          Issue(Severity.warning, 'layout.player.$key', 'must be a boolean'),
        );
      }
    }
  }

  final home = block['home'];
  if (home is Map) {
    _idList(
      home.cast<String, dynamic>(),
      'layout.home.sections',
      homeSectionIds,
      issues,
    );
  }

  final settings = block['settings'];
  if (settings is Map) {
    _idList(
      settings.cast<String, dynamic>(),
      'layout.settings.sections',
      settingsSectionIds,
      issues,
    );
  }

  final titlebar = block['titlebar'];
  if (titlebar is Map) {
    final bar = titlebar.cast<String, dynamic>();
    _number(bar, 'layout.titlebar.height', min: 0, max: 200, issues: issues);
    _number(bar, 'layout.titlebar.padding', min: 0, max: 48, issues: issues);
    final showBack = bar['showBack'];
    if (showBack != null && showBack is! bool) {
      issues.add(
        const Issue(
          Severity.warning,
          'layout.titlebar.showBack',
          'must be a boolean',
        ),
      );
    }
  }

  final splash = block['splash'];
  if (splash is Map) {
    final spec = splash.cast<String, dynamic>();
    if (spec['logo'] != null) {
      _assetPath('layout.splash.logo', spec['logo'], issues);
    }
    if (spec['background'] != null) {
      _assetPath('layout.splash.background', spec['background'], issues);
    }
    if (spec['text'] != null &&
        (spec['text'] is! String || (spec['text'] as String).length > 80)) {
      issues.add(
        const Issue(
          Severity.warning,
          'layout.splash.text',
          'must be a short string',
        ),
      );
    }
  }

  final responsive = block['responsive'];
  if (responsive is Map) {
    final map = responsive.cast<String, dynamic>();
    if (map.length > 4) {
      issues.add(
        Issue(
          Severity.warning,
          'layout.responsive',
          'more than four variants — the extras are dropped',
          resolved: 4,
        ),
      );
    }
    for (final entry in map.entries) {
      if (entry.value is! Map) {
        issues.add(
          Issue(
            Severity.error,
            'layout.responsive.${entry.key}',
            'must be an object',
          ),
        );
        continue;
      }
      final override = (entry.value as Map).cast<String, dynamic>();
      _idList(
        override,
        'layout.responsive.${entry.key}.navItems',
        navIds,
        issues,
        allowScreens: true,
      );
      _idList(
        override,
        'layout.responsive.${entry.key}.navbarItems',
        navbarIds,
        issues,
        allowScreens: true,
      );
      _idList(
        override,
        'layout.responsive.${entry.key}.libraryItems',
        libraryIds,
        issues,
        allowScreens: true,
      );
      final player = override['player'];
      if (player is Map) {
        final flags = player.cast<String, dynamic>();
        for (final key in [
          'showTrackDetails',
          'showActions',
          'showVolume',
          'showLyrics',
          'showProgress',
        ]) {
          final value = flags[key];
          if (value != null && value is! bool) {
            issues.add(
              Issue(
                Severity.warning,
                'layout.responsive.${entry.key}.player.$key',
                'must be a boolean',
              ),
            );
          }
        }
      }
      final home = override['home'];
      if (home is Map) {
        _idList(
          home.cast<String, dynamic>(),
          'layout.responsive.${entry.key}.home.sections',
          homeSectionIds,
          issues,
        );
      }
      final settings = override['settings'];
      if (settings is Map) {
        _idList(
          settings.cast<String, dynamic>(),
          'layout.responsive.${entry.key}.settings.sections',
          settingsSectionIds,
          issues,
        );
      }
    }
  }
}

/// The `branding` block.
void _branding(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'branding', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  const lengths = {
    'appName': 48,
    'shortName': 24,
    'tagline': 120,
    'titlebarTitle': 48,
    'windowTitle': 48,
    'aboutName': 48,
    'notificationName': 32,
  };
  for (final entry in lengths.entries) {
    final value = block[entry.key];
    if (value == null) continue;
    if (value is! String || value.length > entry.value) {
      issues.add(
        Issue(
          Severity.warning,
          'branding.${entry.key}',
          'must be a string of at most ${entry.value} characters — dropped',
        ),
      );
    }
  }

  if (block['logo'] != null) {
    _assetPath('branding.logo', block['logo'], issues);
  }

  final wordmark = block['wordmark'];
  if (wordmark is Map) {
    final mark = wordmark.cast<String, dynamic>();
    final text = mark['text'];
    if (text != null && (text is! String || text.length > 48)) {
      issues.add(
        const Issue(
          Severity.warning,
          'branding.wordmark.text',
          'must be a short string',
        ),
      );
    }
    final family = mark['fontFamily'];
    if (family != null && (family is! String || family.length > 64)) {
      issues.add(
        const Issue(
          Severity.warning,
          'branding.wordmark.fontFamily',
          'must be a family name',
        ),
      );
    }
    if (mark['asset'] != null) {
      _assetPath('branding.wordmark.asset', mark['asset'], issues);
    }
  }
}

/// The `assets` block: what the theme ships.
///
/// The host resolves these inside the plugin's own directory, so the list is
/// the theme telling the host what it brought along.
void _assets(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'assets', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  const kinds = ['image', 'font', 'icon', 'other'];
  for (final key in block.keys) {
    final entries = block[key];
    if (entries is! List) {
      issues.add(Issue(Severity.error, 'assets.$key', 'must be a list'));
      continue;
    }
    if (entries.length > 64) {
      issues.add(
        Issue(
          Severity.warning,
          'assets.$key',
          'more than 64 assets — the extras are dropped',
          resolved: 64,
        ),
      );
    }
    for (var i = 0; i < entries.length && i < 64; i++) {
      final entry = entries[i];
      if (entry is! Map) {
        issues.add(
          Issue(Severity.error, 'assets.$key[$i]', 'must be an object'),
        );
        continue;
      }
      final asset = entry.cast<String, dynamic>();
      _assetPath('assets.$key[$i].path', asset['path'], issues);
      final kind = asset['kind'];
      if (kind != null && (kind is! String || !kinds.contains(kind))) {
        issues.add(
          Issue(
            Severity.warning,
            'assets.$key[$i].kind',
            'must be one of ${kinds.join(', ')}',
          ),
        );
      }
    }
  }
}

/// Validates a UI specification on its own.
///
/// A theme may put its UI in the payload or answer `getUi()` with it; both
/// are the same document, so both are checked the same way.
List<Issue> validateUiSpec(Map<String, dynamic> spec) {
  final issues = <Issue>[];
  _ui(spec, issues);
  return issues;
}

/// The `ui` block: slots, screens and templates.
void _ui(Object? raw, List<Issue> issues) {
  if (raw == null) return;
  if (raw is! Map) {
    issues.add(const Issue(Severity.error, 'ui', 'must be an object'));
    return;
  }
  final block = raw.cast<String, dynamic>();

  final specVersion = block['specVersion'];
  final version = specVersion is num ? specVersion.toInt() : null;
  if (version != 1 && version != 2) {
    issues.add(
      const Issue(
        Severity.error,
        'ui.specVersion',
        'must be 1 or 2 — the host reads no other version',
      ),
    );
  }
  final reads = version ?? 2;

  var total = 0;

  final slots = block['slots'];
  if (slots is Map) {
    final map = slots.cast<String, dynamic>();
    if (map.length > 48) {
      issues.add(
        Issue(
          Severity.warning,
          'ui.slots',
          'more than 48 slots — the extras are dropped',
          resolved: 48,
        ),
      );
    }
    for (final entry in map.entries) {
      if (!slotNames.contains(entry.key)) {
        issues.add(
          Issue(
            Severity.error,
            'ui.slots.${entry.key}',
            'not a slot the host publishes — the content would never appear',
          ),
        );
        continue;
      }
      final slot = entry.value;
      if (slot is! Map) {
        issues.add(
          Issue(Severity.error, 'ui.slots.${entry.key}', 'must be an object'),
        );
        continue;
      }
      final body = slot.cast<String, dynamic>();
      final refresh = body['refreshSeconds'];
      if (refresh != null) {
        if (refresh is! num || refresh < 0 || refresh > 3600) {
          issues.add(
            Issue(
              Severity.warning,
              'ui.slots.${entry.key}.refreshSeconds',
              'must be a number of seconds between 0 and 3600',
            ),
          );
        }
      }
      total += _uiNodes(
        'ui.slots.${entry.key}',
        body['children'],
        maxUiNodesPerSlot,
        issues,
        reads,
      );
    }
  }

  final screens = block['screens'];
  if (screens is Map) {
    final map = screens.cast<String, dynamic>();
    if (map.length > 16) {
      issues.add(
        Issue(
          Severity.warning,
          'ui.screens',
          'more than 16 screens — the extras are dropped',
          resolved: 16,
        ),
      );
    }
    for (final entry in map.entries) {
      final screen = entry.value;
      if (screen is! Map) {
        issues.add(
          Issue(Severity.error, 'ui.screens.${entry.key}', 'must be an object'),
        );
        continue;
      }
      final body = screen.cast<String, dynamic>();
      final title = body['title'];
      if (title != null && (title is! String || title.length > 80)) {
        issues.add(
          Issue(
            Severity.warning,
            'ui.screens.${entry.key}.title',
            'must be a string of at most 80 characters',
          ),
        );
      }
      final showBack = body['showBack'];
      if (showBack != null && showBack is! bool) {
        issues.add(
          Issue(
            Severity.warning,
            'ui.screens.${entry.key}.showBack',
            'must be a boolean',
          ),
        );
      }
      total += _uiNodes(
        'ui.screens.${entry.key}',
        body['children'],
        500,
        issues,
        reads,
      );
    }
  }

  final templates = block['templates'];
  if (templates is Map) {
    final map = templates.cast<String, dynamic>();
    if (map.length > 32) {
      issues.add(
        Issue(
          Severity.warning,
          'ui.templates',
          'more than 32 templates — the extras are dropped',
          resolved: 32,
        ),
      );
    }
    for (final entry in map.entries) {
      final template = entry.value;
      if (template is! Map) {
        issues.add(
          Issue(
            Severity.error,
            'ui.templates.${entry.key}',
            'must be an object',
          ),
        );
        continue;
      }
      final body = template.cast<String, dynamic>();
      final params = body['params'];
      if (params != null) {
        if (params is! List || params.length > 16) {
          issues.add(
            Issue(
              Severity.warning,
              'ui.templates.${entry.key}.params',
              'must be a list of at most 16 names',
            ),
          );
        } else {
          for (final param in params) {
            if (param is! String || param.length > 64) {
              issues.add(
                Issue(
                  Severity.warning,
                  'ui.templates.${entry.key}.params',
                  'a parameter name must be a short string',
                ),
              );
            }
          }
        }
      }
      total += _uiNodes(
        'ui.templates.${entry.key}',
        body['children'],
        maxUiNodesPerSlot,
        issues,
        reads,
      );
    }
  }

  if (total > maxUiNodesTotal) {
    issues.add(
      Issue(
        Severity.warning,
        'ui',
        'more than $maxUiNodesTotal nodes in total — the extras are dropped',
        resolved: maxUiNodesTotal,
      ),
    );
  }
}

/// A list of nodes, checked for type, depth, size and bindings.
int _uiNodes(
  String path,
  Object? raw,
  int limit,
  List<Issue> issues,
  int version,
) {
  if (raw == null) return 0;
  if (raw is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list of nodes'));
    return 0;
  }
  if (raw.length > limit) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'more than $limit nodes — the extras are dropped',
        resolved: limit,
      ),
    );
  }

  var count = 0;
  for (var i = 0; i < raw.length; i++) {
    count += _uiNode('$path[$i]', raw[i], 0, issues, version);
  }
  return count;
}

/// One node.
int _uiNode(
  String path,
  Object? raw,
  int depth,
  List<Issue> issues,
  int version,
) {
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return 0;
  }
  final node = raw.cast<String, dynamic>();

  if (depth > maxUiDepth) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'deeper than $maxUiDepth levels — the subtree is dropped',
      ),
    );
    return 0;
  }

  final type = node['type'];
  if (type is! String || !uiNodeTypes.contains(type)) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'unknown node type — the host renders nothing for it',
      ),
    );
    return 0;
  }

  if (type == 'animate' && version < 2) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'animate needs ui.specVersion 2 — a v1 host draws its child still',
      ),
    );
  }

  var count = 1;

  // The flat shape is what every theme is written in. `props` is the
  // original shape and is merged in, so a payload written either way reads
  // the same.
  final props = <String, dynamic>{};
  final nested = node['props'];
  if (nested != null) {
    if (nested is! Map) {
      issues.add(Issue(Severity.error, '$path.props', 'must be an object'));
    } else {
      props.addAll(nested.cast<String, dynamic>());
      issues.add(
        Issue(
          Severity.warning,
          '$path.props',
          'the legacy shape — write the props flat on the node',
        ),
      );
    }
  }
  for (final entry in node.entries) {
    if (uiStructuralKeys.contains(entry.key)) continue;
    props[entry.key] = entry.value;
  }

  final allowed = uiNodeProps[type] ?? const <String>[];
  for (final key in props.keys) {
    if (!allowed.contains(key)) {
      issues.add(
        Issue(
          Severity.error,
          '$path.$key',
          'not a prop of a "$type" node — the host ignores it',
        ),
      );
    }
  }
  for (final entry in props.entries) {
    _uiProp('$path.${entry.key}', type, entry.key, entry.value, issues);
  }

  if (node.containsKey('action') && node.containsKey('actions')) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'both action and actions — the host reads actions',
      ),
    );
  }
  if (node['action'] != null) {
    _uiAction('$path.action', node['action'], issues);
  }
  if (node['actions'] != null) {
    final actions = node['actions'];
    if (actions is! List) {
      issues.add(Issue(Severity.error, '$path.actions', 'must be a list'));
    } else {
      if (actions.length > maxUiActionsPerNode) {
        issues.add(
          Issue(
            Severity.warning,
            '$path.actions',
            'more than $maxUiActionsPerNode actions — the extras are dropped',
            resolved: maxUiActionsPerNode,
          ),
        );
      }
      for (var i = 0; i < actions.length; i++) {
        _uiAction('$path.actions[$i]', actions[i], issues);
      }
    }
  }

  final children = node['children'];
  if (children is List) {
    for (var i = 0; i < children.length; i++) {
      count += _uiNode(
        '$path.children[$i]',
        children[i],
        depth + 1,
        issues,
        version,
      );
    }
  } else if (children != null) {
    issues.add(Issue(Severity.error, '$path.children', 'must be a list'));
  }

  return count;
}

/// One prop, checked against what its node type says it means.
void _uiProp(
  String path,
  String type,
  String key,
  Object? value,
  List<Issue> issues,
) {
  if (key == 'bind' || key == 'maxBind' || key == 'disabledWhen') {
    if (value is! String || !isUiBinding(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'not a binding the host knows — the node renders empty',
        ),
      );
    }
    return;
  }

  if (key == 'text') {
    if (value is! String) {
      issues.add(Issue(Severity.error, path, 'must be a string'));
    } else if (value.length > maxUiTextLength) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'longer than $maxUiTextLength characters — truncated',
        ),
      );
    }
    return;
  }

  if (key == 'label') {
    if (value is! String) {
      issues.add(Issue(Severity.error, path, 'must be a string'));
    } else if (value.length > 200) {
      issues.add(
        Issue(Severity.warning, path, 'longer than 200 characters — truncated'),
      );
    }
    return;
  }

  if (key == 'src') {
    if (value is! String) {
      issues.add(Issue(Severity.error, path, 'must be a string'));
    } else if (value.startsWith('asset://')) {
      _assetPath(path, value, issues);
    } else if (!uiImageSources.contains(value) &&
        !(value.contains('.') && isUiBinding(value))) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${uiImageSources.join(', ')}, a binding, '
          'or an asset:// path',
        ),
      );
    }
    return;
  }

  if (key == 'icon') {
    if (value is! String) {
      issues.add(Issue(Severity.error, path, 'must be an icon name'));
    } else if (value.startsWith('asset://')) {
      _assetPath(path, value, issues);
    } else if (value.length > 64) {
      issues.add(
        Issue(Severity.warning, path, 'longer than 64 characters — dropped'),
      );
    }
    return;
  }

  if (key == 'color' || key == 'trackColor' || key == 'thumbColor') {
    _colorOrRole(path, value, issues);
    return;
  }

  if (key == 'size') {
    // `size` means three different things: a type scale on text, a pixel
    // size on an icon, a gap on a gap node. The node type says which.
    if (type == 'icon' || type == 'gap') {
      _uiNumber(
        path,
        value,
        min: type == 'icon' ? 8 : 0,
        max: 96,
        issues: issues,
      );
      return;
    }
    final allowed = type == 'button'
        ? const ['small', 'md', 'lg']
        : uiTextSizes;
    if (value is! String || !allowed.contains(value)) {
      issues.add(
        Issue(Severity.error, path, 'must be one of ${allowed.join(', ')}'),
      );
    }
    return;
  }

  if (key == 'weight') {
    if (value is num) {
      _uiNumber(path, value, min: 100, max: 900, issues: issues);
    } else if (value is! String || !uiFontWeights.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be 100..900 or one of ${uiFontWeights.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'align') {
    final allowed = switch (type) {
      'text' => const ['left', 'center', 'right'],
      'stack' || 'align' => uiStackAlignments,
      _ => uiAlignments,
    };
    if (value is! String || !allowed.contains(value)) {
      issues.add(
        Issue(Severity.error, path, 'must be one of ${allowed.join(', ')}'),
      );
    }
    return;
  }

  if (key == 'justify') {
    if (value is! String || !uiJustifications.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${uiJustifications.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'overflow') {
    if (value is! String || !uiOverflows.contains(value)) {
      issues.add(
        Issue(Severity.error, path, 'must be one of ${uiOverflows.join(', ')}'),
      );
    }
    return;
  }

  if (key == 'fit') {
    // A stack fits its children to itself; an image fits itself to its box.
    final allowed = type == 'stack' ? const ['loose', 'expand'] : uiImageFits;
    if (value is! String || !allowed.contains(value)) {
      issues.add(
        Issue(Severity.error, path, 'must be one of ${allowed.join(', ')}'),
      );
    }
    return;
  }

  if (key == 'filter') {
    if (value is! String || !uiImageFilters.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${uiImageFilters.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'shape') {
    if (value != 'square' && value != 'circle') {
      issues.add(Issue(Severity.error, path, 'must be square or circle'));
    }
    return;
  }

  if (key == 'variant') {
    if (value is! String || !buttonVariants.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${buttonVariants.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'kind') {
    if (value is! String || !uiAnimationKinds.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${uiAnimationKinds.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'curve') {
    if (value is! String || !uiAnimationCurves.contains(value)) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be one of ${uiAnimationCurves.join(', ')}',
        ),
      );
    }
    return;
  }

  if (key == 'duration') {
    _uiNumber(path, value, min: 100, max: 120000, issues: issues);
    return;
  }

  if (key == 'reverse' ||
      key == 'invert' ||
      key == 'uppercase' ||
      key == 'tile' ||
      key == 'interactive') {
    if (value is! bool) {
      issues.add(Issue(Severity.error, path, 'must be a boolean'));
    }
    return;
  }

  if (key == 'equals') {
    if (value is! String && value is! num && value is! bool) {
      issues.add(
        Issue(Severity.error, path, 'must be a string, a number or a boolean'),
      );
    }
    return;
  }

  if (key == 'name') {
    if (value is! String || value.isEmpty || value.length > 64) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be a template name of at most 64 characters',
        ),
      );
    }
    return;
  }

  if (key == 'args') {
    if (value is! Map) {
      issues.add(Issue(Severity.error, path, 'must be an object'));
    }
    return;
  }

  if (key == 'orientation') {
    if (value != 'horizontal' && value != 'vertical') {
      issues.add(Issue(Severity.error, path, 'must be horizontal or vertical'));
    }
    return;
  }

  if (key == 'direction') {
    if (value != 'horizontal' && value != 'vertical') {
      issues.add(Issue(Severity.error, path, 'must be horizontal or vertical'));
    }
    return;
  }

  if (key == 'family') {
    if (value is! String || value.length > 64) {
      issues.add(
        Issue(
          Severity.error,
          path,
          'must be a family name of at most 64 characters',
        ),
      );
    }
    return;
  }

  if (key == 'maxLines') {
    if (value is! int || value < 1 || value > 8) {
      issues.add(Issue(Severity.error, path, 'must be an integer 1..8'));
    }
    return;
  }

  if (key == 'flex') {
    if (value is! int || value < 1 || value > 12) {
      issues.add(Issue(Severity.error, path, 'must be an integer 1..12'));
    }
    return;
  }

  if (key == 'thickness') {
    _uiNumber(path, value, min: 0, max: 8, issues: issues);
    return;
  }

  if (key == 'letterSpacing') {
    _uiNumber(path, value, min: -2, max: 8, issues: issues);
    return;
  }

  if (key == 'widthFactor' || key == 'heightFactor') {
    _uiNumber(path, value, min: 0.1, max: 4, issues: issues);
    return;
  }

  if (key == 'opacity') {
    _uiNumber(path, value, min: 0, max: 1, issues: issues);
    return;
  }

  if (key == 'radius') {
    _uiNumber(path, value, min: 0, max: 999, issues: issues);
    return;
  }

  if (key == 'width' || key == 'height') {
    _uiNumber(path, value, min: 0, max: 2000, issues: issues);
    return;
  }

  if (key == 'gap' ||
      key == 'runGap' ||
      key == 'size' ||
      key == 'padding' ||
      key == 'all' ||
      key == 'horizontal' ||
      key == 'vertical' ||
      key == 'top' ||
      key == 'right' ||
      key == 'bottom' ||
      key == 'left' ||
      key == 'borderWidth' ||
      key == 'hitHeight' ||
      key == 'thumbSize') {
    _uiNumber(path, value, min: 0, max: 96, issues: issues);
    return;
  }

  if (key == 'background' ||
      key == 'hoverBackground' ||
      key == 'borderColor') {
    _colorOrRole(path, value, issues);
    return;
  }

  // The registry above covers every prop a node type declares, so an
  // unhandled key is a registry bug rather than a theme bug.
}

/// One action: the verb the host dispatches, and the arguments it needs.
void _uiAction(String path, Object? raw, List<Issue> issues) {
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  final action = raw.cast<String, dynamic>();
  final type = action['type'];
  if (type is! String || !uiActionTypes.contains(type)) {
    issues.add(
      Issue(
        Severity.error,
        '$path.type',
        'unknown action — the host ignores it',
      ),
    );
    return;
  }
  final args = action['args'];
  if (args != null && args is! Map) {
    issues.add(Issue(Severity.error, '$path.args', 'must be an object'));
    return;
  }
  final map = args is Map
      ? args.cast<String, dynamic>()
      : const <String, dynamic>{};

  if (type == 'navigate') {
    final target = map['target'];
    if (target is! String || target.isEmpty) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.args.target',
          'navigate needs a target — the host ignores the action',
        ),
      );
    }
  } else if (type == 'plugin') {
    final id = map['id'];
    if (id is! String || id.isEmpty) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.args.id',
          'plugin needs an id — the host ignores the action',
        ),
      );
    }
  } else if (type == 'toast') {
    final message = map['message'];
    if (message is! String || message.isEmpty) {
      issues.add(
        Issue(Severity.warning, '$path.args.message', 'toast needs a message'),
      );
    }
  } else if (type == 'seek') {
    final position = map['position'];
    if (position is! num) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.args.position',
          'seek needs a position in seconds',
        ),
      );
    }
  } else if (type == 'setVolume') {
    final volume = map['volume'];
    if (volume is! num || volume < 0 || volume > 1) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.args.volume',
          'setVolume needs a volume between 0 and 1',
        ),
      );
    }
  }
}

/// A number given directly, rather than looked up in a map.
void _uiNumber(
  String path,
  Object? value, {
  required double min,
  required double max,
  required List<Issue> issues,
}) {
  if (value == null) return;
  if (value is! num) {
    issues.add(Issue(Severity.error, path, 'must be a number'));
    return;
  }
  final number = value.toDouble();
  if (!number.isFinite || number < min || number > max) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'outside $min..$max — the host clamps it',
        resolved: number.clamp(min, max).toDouble(),
      ),
    );
  }
}

/// A list of ids from a closed set.
void _idList(
  Map<String, dynamic> map,
  String path,
  List<String> allowed,
  List<Issue> issues, {
  bool allowScreens = false,
}) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list'));
    return;
  }
  if (value.length > 20) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'more than 20 entries — the extras are dropped',
        resolved: 20,
      ),
    );
  }
  for (final entry in value) {
    final validScreen =
        allowScreens &&
        entry is String &&
        RegExp(r'^screen:[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$').hasMatch(entry);
    if (entry is! String || (!allowed.contains(entry) && !validScreen)) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          allowScreens
              ? 'unknown id — the host drops it (entries may also be screen:<id>)'
              : 'unknown id — the host drops it',
        ),
      );
    }
  }
}

/// A map of custom tokens.
void _customTokens(Map<String, dynamic> map, String path, List<Issue> issues) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  final tokens = value.cast<String, dynamic>();
  if (tokens.length > maxCustomTokens) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'more than $maxCustomTokens tokens — the extras are dropped',
        resolved: maxCustomTokens,
      ),
    );
  }
  for (final entry in tokens.entries) {
    final token = entry.value;
    if (token is! num) {
      issues.add(
        Issue(Severity.error, '$path.${entry.key}', 'must be a number'),
      );
      continue;
    }
    final number = token.toDouble();
    if (!number.isFinite || number < 0 || number > 1000) {
      issues.add(
        Issue(
          Severity.warning,
          '$path.${entry.key}',
          'outside 0..1000 — the host clamps it',
          resolved: number.clamp(0.0, 1000.0).toDouble(),
        ),
      );
    }
  }
}

/// A number inside a range.
void _number(
  Map<String, dynamic> map,
  String path, {
  required double min,
  required double max,
  required List<Issue> issues,
}) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! num) {
    issues.add(Issue(Severity.error, path, 'must be a number'));
    return;
  }
  final number = value.toDouble();
  if (!number.isFinite || number < min || number > max) {
    issues.add(
      Issue(
        Severity.warning,
        path,
        'outside $min..$max — the host clamps it',
        resolved: number.clamp(min, max).toDouble(),
      ),
    );
  }
}

/// A colour, either hex or a role reference.
void _colorOrRole(String path, Object? value, List<Issue> issues) {
  if (value is! String) {
    issues.add(Issue(Severity.error, path, 'must be a color string'));
    return;
  }
  if (value.startsWith('@')) {
    if (!roleNames.contains(value.substring(1))) {
      issues.add(
        Issue(
          Severity.warning,
          path,
          'unknown role reference — the host falls back',
        ),
      );
    }
    return;
  }
  if (!_isHex(value)) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'must be a #RRGGBB color or a @role reference',
      ),
    );
  }
}

/// Whether a value parses as a color the host accepts.
bool _isHex(String value) {
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
}

/// An asset path, which has to stay inside the plugin's own directory.
void _assetPath(String path, Object? value, List<Issue> issues) {
  if (value is! String) {
    issues.add(Issue(Severity.error, path, 'must be an asset path'));
    return;
  }
  if (!value.startsWith('asset://')) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'must start with asset:// — only the plugin\'s own assets are reachable',
      ),
    );
    return;
  }
  final rest = value.substring('asset://'.length);
  if (rest.isEmpty ||
      rest.startsWith('/') ||
      rest.contains('..') ||
      rest.contains('\\')) {
    issues.add(
      Issue(
        Severity.error,
        path,
        'must be a relative path inside the plugin directory',
      ),
    );
  }
}
