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
const libraryIds = <String>['playlists', 'artists', 'albums', 'local_library'];
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
  'app.overlay',
  'shell.before',
  'shell.after',
  'home.before_sections',
  'home.after_sections',
  'lyrics.header',
  'lyrics.after_tabs',
  'settings.before',
  'settings.after',
];

/// The layout keys a theme may take ownership of.
const enforceIds = <String>[
  'nav',
  'navItems',
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
  'divider',
  'spacer',
  'gap',
  'conditional',
  'template',
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
];

/// The data a theme's UI can bind to.
const uiBindings = <String>[
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
  'clock.now',
];

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
    issues.add(Issue(
      Severity.error,
      'specVersion',
      'must be 3 or more to declare the v3 blocks',
    ));
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
      issues.add(Issue(
        Severity.error,
        '$path.$role',
        'must be a #RRGGBB or #AARRGGBB color',
      ));
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
      issues.add(Issue(
        Severity.warning,
        'typography.$key',
        'must be a family name of at most 64 characters — dropped',
      ));
    }
  }

  final styles = block['styles'];
  if (styles != null) {
    if (styles is! Map) {
      issues.add(
          const Issue(Severity.error, 'typography.styles', 'must be an object'));
    } else {
      final map = styles.cast<String, dynamic>();
      if (map.length > 32) {
        issues.add(Issue(
          Severity.warning,
          'typography.styles',
          'more than 32 style overrides — the extras are dropped',
          resolved: 32,
        ));
      }
      for (final entry in map.entries) {
        _textStyle('typography.styles.${entry.key}', entry.value, issues);
      }
    }
  }

  final fonts = block['fonts'];
  if (fonts != null) {
    if (fonts is! List) {
      issues.add(const Issue(Severity.error, 'typography.fonts', 'must be a list'));
    } else {
      if (fonts.length > 8) {
        issues.add(Issue(
          Severity.warning,
          'typography.fonts',
          'more than 8 font files — the extras are dropped',
          resolved: 8,
        ));
      }
      for (var i = 0; i < fonts.length && i < 8; i++) {
        final font = fonts[i];
        if (font is! Map) {
          issues.add(Issue(
              Severity.error, 'typography.fonts[$i]', 'must be an object'));
          continue;
        }
        final family = font['family'];
        if (family is! String || family.isEmpty || family.length > 64) {
          issues.add(Issue(
            Severity.error,
            'typography.fonts[$i].family',
            'must be a family name of at most 64 characters',
          ));
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
    issues.add(Issue(
      Severity.warning,
      '$path.fontFamily',
      'must be a family name of at most 64 characters — dropped',
    ));
  }

  final fontStyle = style['fontStyle'];
  if (fontStyle != null && fontStyle != 'normal' && fontStyle != 'italic') {
    issues.add(Issue(
      Severity.warning,
      '$path.fontStyle',
      'must be normal or italic — dropped',
    ));
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
    issues.add(Issue(
      Severity.warning,
      'motion.easing',
      'must be one of ${easings.join(', ')} — the host falls back',
      resolved: 'easeOutCubic',
    ));
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
        issues.add(Issue(
            Severity.error, 'icons.overrides.${entry.key}', 'must be an object'));
        continue;
      }
      final icon = value.cast<String, dynamic>();
      if (icon['asset'] != null) {
        _assetPath('icons.overrides.${entry.key}.asset', icon['asset'], issues);
      }
      _number(icon, 'icons.overrides.${entry.key}.size',
          min: 8, max: 64, issues: issues);
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
      issues.add(Issue(
        Severity.warning,
        'components.${entry.key}',
        'not a component the app knows — ignored',
      ));
      continue;
    }

    if (entry.key == 'buttons') {
      final buttons = entry.value;
      if (buttons is! Map) {
        issues.add(
            const Issue(Severity.error, 'components.buttons', 'must be an object'));
        continue;
      }
      for (final button in buttons.entries) {
        if (!buttonVariants.contains(button.key)) {
          issues.add(Issue(
            Severity.warning,
            'components.buttons.${button.key}',
            'not a button variant the app knows — ignored',
          ));
          continue;
        }
        _componentStyle('components.buttons.${button.key}', button.value, issues);
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
    issues.add(Issue(
      Severity.warning,
      '$path.fontFamily',
      'must be a family name of at most 64 characters — dropped',
    ));
  }

  final fontStyle = style['fontStyle'];
  if (fontStyle != null && fontStyle != 'normal' && fontStyle != 'italic') {
    issues.add(Issue(
      Severity.warning,
      '$path.fontStyle',
      'must be normal or italic — dropped',
    ));
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

  _idList(block, 'layout.navItems', navIds, issues);
  _idList(block, 'layout.navbarItems', navbarIds, issues);
  _idList(block, 'layout.libraryItems', libraryIds, issues);

  final enforce = block['enforce'];
  if (enforce != null) {
    if (enforce is! List) {
      issues.add(const Issue(Severity.error, 'layout.enforce', 'must be a list'));
    } else {
      for (final value in enforce) {
        if (value is! String || !enforceIds.contains(value)) {
          issues.add(Issue(
            Severity.warning,
            'layout.enforce',
            'unknown key — the host ignores it',
          ));
        }
      }
    }
  }

  final player = block['player'];
  if (player is Map) {
    final flags = player.cast<String, dynamic>();
    const docks = ['full', 'compact', 'floating'];
    final dock = flags['dock'];
    if (dock != null && (dock is! String || !docks.contains(dock))) {
      issues.add(Issue(
        Severity.warning,
        'layout.player.dock',
        'must be one of ${docks.join(', ')} — the host falls back',
        resolved: 'full',
      ));
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
        issues.add(Issue(
            Severity.warning, 'layout.player.$key', 'must be a boolean'));
      }
    }
  }

  final home = block['home'];
  if (home is Map) {
    _idList(home.cast<String, dynamic>(), 'layout.home.sections', homeSectionIds,
        issues);
  }

  final settings = block['settings'];
  if (settings is Map) {
    _idList(settings.cast<String, dynamic>(), 'layout.settings.sections',
        settingsSectionIds, issues);
  }

  final titlebar = block['titlebar'];
  if (titlebar is Map) {
    final bar = titlebar.cast<String, dynamic>();
    _number(bar, 'layout.titlebar.height', min: 0, max: 200, issues: issues);
    _number(bar, 'layout.titlebar.padding', min: 0, max: 48, issues: issues);
    final showBack = bar['showBack'];
    if (showBack != null && showBack is! bool) {
      issues.add(const Issue(
          Severity.warning, 'layout.titlebar.showBack', 'must be a boolean'));
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
    if (spec['text'] != null && (spec['text'] is! String || (spec['text'] as String).length > 80)) {
      issues.add(const Issue(
          Severity.warning, 'layout.splash.text', 'must be a short string'));
    }
  }

  final responsive = block['responsive'];
  if (responsive is Map) {
    final map = responsive.cast<String, dynamic>();
    if (map.length > 4) {
      issues.add(Issue(
        Severity.warning,
        'layout.responsive',
        'more than four variants — the extras are dropped',
        resolved: 4,
      ));
    }
    for (final entry in map.entries) {
      if (entry.value is! Map) {
        issues.add(Issue(
            Severity.error, 'layout.responsive.${entry.key}', 'must be an object'));
        continue;
      }
      final override = (entry.value as Map).cast<String, dynamic>();
      _idList(override, 'layout.responsive.${entry.key}.navItems', navIds, issues);
      _idList(override, 'layout.responsive.${entry.key}.navbarItems', navbarIds,
          issues);
      _idList(override, 'layout.responsive.${entry.key}.libraryItems',
          libraryIds, issues);
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
            issues.add(Issue(
              Severity.warning,
              'layout.responsive.${entry.key}.player.$key',
              'must be a boolean',
            ));
          }
        }
      }
      final home = override['home'];
      if (home is Map) {
        _idList(home.cast<String, dynamic>(),
            'layout.responsive.${entry.key}.home.sections', homeSectionIds,
            issues);
      }
      final settings = override['settings'];
      if (settings is Map) {
        _idList(settings.cast<String, dynamic>(),
            'layout.responsive.${entry.key}.settings.sections', settingsSectionIds,
            issues);
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
      issues.add(Issue(
        Severity.warning,
        'branding.${entry.key}',
        'must be a string of at most ${entry.value} characters — dropped',
      ));
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
      issues.add(const Issue(
          Severity.warning, 'branding.wordmark.text', 'must be a short string'));
    }
    final family = mark['fontFamily'];
    if (family != null && (family is! String || family.length > 64)) {
      issues.add(const Issue(
          Severity.warning, 'branding.wordmark.fontFamily', 'must be a family name'));
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
      issues.add(Issue(
        Severity.warning,
        'assets.$key',
        'more than 64 assets — the extras are dropped',
        resolved: 64,
      ));
    }
    for (var i = 0; i < entries.length && i < 64; i++) {
      final entry = entries[i];
      if (entry is! Map) {
        issues.add(Issue(
            Severity.error, 'assets.$key[$i]', 'must be an object'));
        continue;
      }
      final asset = entry.cast<String, dynamic>();
      _assetPath('assets.$key[$i].path', asset['path'], issues);
      final kind = asset['kind'];
      if (kind != null && (kind is! String || !kinds.contains(kind))) {
        issues.add(Issue(
          Severity.warning,
          'assets.$key[$i].kind',
          'must be one of ${kinds.join(', ')}',
        ));
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
  if (specVersion != 1) {
    issues.add(const Issue(
      Severity.error,
      'ui.specVersion',
      'must be 1 — the host reads no other version',
    ));
  }

  var total = 0;

  final slots = block['slots'];
  if (slots is Map) {
    final map = slots.cast<String, dynamic>();
    if (map.length > 32) {
      issues.add(Issue(
        Severity.warning,
        'ui.slots',
        'more than 32 slots — the extras are dropped',
        resolved: 32,
      ));
    }
    for (final entry in map.entries) {
      if (!slotNames.contains(entry.key)) {
        issues.add(Issue(
          Severity.error,
          'ui.slots.${entry.key}',
          'not a slot the host publishes — the content would never appear',
        ));
        continue;
      }
      final slot = entry.value;
      if (slot is! Map) {
        issues.add(Issue(
            Severity.error, 'ui.slots.${entry.key}', 'must be an object'));
        continue;
      }
      final children = slot.cast<String, dynamic>()['children'];
      total += _uiNodes('ui.slots.${entry.key}', children, maxUiNodesPerSlot,
          issues);
    }
  }

  final screens = block['screens'];
  if (screens is Map) {
    final map = screens.cast<String, dynamic>();
    if (map.length > 16) {
      issues.add(Issue(
        Severity.warning,
        'ui.screens',
        'more than 16 screens — the extras are dropped',
        resolved: 16,
      ));
    }
    for (final entry in map.entries) {
      final screen = entry.value;
      if (screen is! Map) {
        issues.add(Issue(
            Severity.error, 'ui.screens.${entry.key}', 'must be an object'));
        continue;
      }
      final title = screen.cast<String, dynamic>()['title'];
      if (title != null && (title is! String || title.length > 80)) {
        issues.add(Issue(
          Severity.warning,
          'ui.screens.${entry.key}.title',
          'must be a string of at most 80 characters',
        ));
      }
      total += _uiNodes(
        'ui.screens.${entry.key}',
        screen.cast<String, dynamic>()['children'],
        500,
        issues,
      );
    }
  }

  final templates = block['templates'];
  if (templates is Map) {
    final map = templates.cast<String, dynamic>();
    if (map.length > 32) {
      issues.add(Issue(
        Severity.warning,
        'ui.templates',
        'more than 32 templates — the extras are dropped',
        resolved: 32,
      ));
    }
    for (final entry in map.entries) {
      final template = entry.value;
      if (template is! Map) {
        issues.add(Issue(
            Severity.error, 'ui.templates.${entry.key}', 'must be an object'));
        continue;
      }
      final children = template.cast<String, dynamic>()['children'];
      total += _uiNodes('ui.templates.${entry.key}', children, maxUiNodesPerSlot,
          issues);
    }
  }

  if (total > maxUiNodesTotal) {
    issues.add(Issue(
      Severity.warning,
      'ui',
      'more than $maxUiNodesTotal nodes in total — the extras are dropped',
      resolved: maxUiNodesTotal,
    ));
  }
}

/// A list of nodes, checked for type, depth, size and bindings.
int _uiNodes(String path, Object? raw, int limit, List<Issue> issues) {
  if (raw == null) return 0;
  if (raw is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list of nodes'));
    return 0;
  }
  if (raw.length > limit) {
    issues.add(Issue(
      Severity.warning,
      path,
      'more than $limit nodes — the extras are dropped',
      resolved: limit,
    ));
  }

  var count = 0;
  for (var i = 0; i < raw.length; i++) {
    count += _uiNode('$path[$i]', raw[i], 0, issues);
  }
  return count;
}

/// One node.
int _uiNode(String path, Object? raw, int depth, List<Issue> issues) {
  if (raw is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return 0;
  }
  final node = raw.cast<String, dynamic>();

  if (depth > maxUiDepth) {
    issues.add(Issue(
      Severity.warning,
      path,
      'deeper than $maxUiDepth levels — the subtree is dropped',
    ));
    return 0;
  }

  final type = node['type'];
  if (type is! String || !uiNodeTypes.contains(type)) {
    issues.add(Issue(
      Severity.error,
      path,
      'unknown node type — the host renders nothing for it',
    ));
    return 0;
  }

  var count = 1;

  final props = node['props'];
  if (props is Map) {
    final map = props.cast<String, dynamic>();
    for (final entry in map.entries) {
      if (entry.key == 'bind') {
        final bind = entry.value;
        if (bind is! String || !uiBindings.contains(bind)) {
          issues.add(Issue(
            Severity.warning,
            '$path.props.bind',
            'unknown binding — the node renders empty',
          ));
        }
        continue;
      }
      if (entry.key == 'text' && entry.value is String) {
        final text = entry.value as String;
        if (text.length > maxUiTextLength) {
          issues.add(Issue(
            Severity.warning,
            '$path.props.text',
            'longer than $maxUiTextLength characters — truncated',
          ));
        }
        continue;
      }
      if (entry.key == 'src' || entry.key == 'icon') {
        final value = entry.value;
        if (value is String && value.startsWith('asset://')) {
          _assetPath('$path.props.${entry.key}', value, issues);
        }
      }
    }
  }

  final actions = node['actions'];
  if (actions is List) {
    if (actions.length > maxUiActionsPerNode) {
      issues.add(Issue(
        Severity.warning,
        '$path.actions',
        'more than $maxUiActionsPerNode actions — the extras are dropped',
        resolved: maxUiActionsPerNode,
      ));
    }
    for (var i = 0; i < actions.length; i++) {
      final action = actions[i];
      if (action is! Map) {
        issues.add(
            Issue(Severity.error, '$path.actions[$i]', 'must be an object'));
        continue;
      }
      final actionType = action.cast<String, dynamic>()['type'];
      if (actionType is! String || !uiActionTypes.contains(actionType)) {
        issues.add(Issue(
          Severity.error,
          '$path.actions[$i].type',
          'unknown action — the host ignores it',
        ));
      }
    }
  }

  final children = node['children'];
  if (children is List) {
    for (var i = 0; i < children.length; i++) {
      count += _uiNode('$path.children[$i]', children[i], depth + 1, issues);
    }
  }

  return count;
}

/// A list of ids from a closed set.
void _idList(
  Map<String, dynamic> map,
  String path,
  List<String> allowed,
  List<Issue> issues,
) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! List) {
    issues.add(Issue(Severity.error, path, 'must be a list'));
    return;
  }
  if (value.length > 20) {
    issues.add(Issue(
      Severity.warning,
      path,
      'more than 20 entries — the extras are dropped',
      resolved: 20,
    ));
  }
  for (final entry in value) {
    if (entry is! String || !allowed.contains(entry)) {
      issues.add(Issue(
        Severity.warning,
        path,
        'unknown id — the host drops it',
      ));
    }
  }
}

/// A map of custom tokens.
void _customTokens(
  Map<String, dynamic> map,
  String path,
  List<Issue> issues,
) {
  final value = map[path.split('.').last];
  if (value == null) return;
  if (value is! Map) {
    issues.add(Issue(Severity.error, path, 'must be an object'));
    return;
  }
  final tokens = value.cast<String, dynamic>();
  if (tokens.length > maxCustomTokens) {
    issues.add(Issue(
      Severity.warning,
      path,
      'more than $maxCustomTokens tokens — the extras are dropped',
      resolved: maxCustomTokens,
    ));
  }
  for (final entry in tokens.entries) {
    final token = entry.value;
    if (token is! num) {
      issues.add(Issue(
          Severity.error, '$path.${entry.key}', 'must be a number'));
      continue;
    }
    final number = token.toDouble();
    if (!number.isFinite || number < 0 || number > 1000) {
      issues.add(Issue(
        Severity.warning,
        '$path.${entry.key}',
        'outside 0..1000 — the host clamps it',
        resolved: number.clamp(0.0, 1000.0).toDouble(),
      ));
    }
  }
}

/// A number inside a range.
void _number(
  Map<String, dynamic> map,
  String path,
  {
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
    issues.add(Issue(
      Severity.warning,
      path,
      'outside $min..$max — the host clamps it',
      resolved: number.clamp(min, max).toDouble(),
    ));
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
      issues.add(Issue(
        Severity.warning,
        path,
        'unknown role reference — the host falls back',
      ));
    }
    return;
  }
  if (!_isHex(value)) {
    issues.add(Issue(
      Severity.error,
      path,
      'must be a #RRGGBB color or a @role reference',
    ));
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
    issues.add(Issue(
      Severity.error,
      path,
      'must start with asset:// — only the plugin\'s own assets are reachable',
    ));
    return;
  }
  final rest = value.substring('asset://'.length);
  if (rest.isEmpty ||
      rest.startsWith('/') ||
      rest.contains('..') ||
      rest.contains('\\')) {
    issues.add(Issue(
      Severity.error,
      path,
      'must be a relative path inside the plugin directory',
    ));
  }
}
