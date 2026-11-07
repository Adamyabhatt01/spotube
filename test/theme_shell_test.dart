import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/resolved_layout.dart';
import 'package:spotube/modules/theme_shell/theme_branding.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/modules/theme_shell/theme_shell.dart';

const _palette = {
  'background': '#000000',
  'foreground': '#ffffff',
  'card': '#111111',
  'cardForeground': '#ffffff',
  'primary': '#ff0000',
  'primaryForeground': '#ffffff',
  'secondary': '#222222',
  'secondaryForeground': '#ffffff',
  'muted': '#333333',
  'mutedForeground': '#999999',
  'accent': '#444444',
  'accentForeground': '#ffffff',
  'destructive': '#550000',
  'destructiveForeground': '#ffffff',
  'border': '#666666',
  'input': '#777777',
  'ring': '#888888',
};

ThemeDefinition _definition(Map<String, dynamic> branding) =>
    ThemeDefinition.fromJson({
      'light': _palette,
      'dark': _palette,
      'branding': branding,
    });

void main() {
  group('responsive layout', () {
    test('picks the tier at the host breakpoints', () {
      expect(themeBreakpointForWidth(480), ThemeBreakpoint.compact);
      expect(themeBreakpointForWidth(820), ThemeBreakpoint.compact);
      expect(themeBreakpointForWidth(900), ThemeBreakpoint.medium);
      expect(themeBreakpointForWidth(1024), ThemeBreakpoint.medium);
      expect(themeBreakpointForWidth(1280), ThemeBreakpoint.expanded);
    });

    test('merges a variant over the base and keeps unset fields', () {
      const base = ThemeLayout(
        nav: ThemeNav.labels,
        progress: ThemeProgress.inlinePlacement,
        player: ThemePlayerLayout(showVolume: true),
        home: {
          'sections': ['recent', 'featured'],
        },
      );
      const layout = ThemeLayout(
        nav: ThemeNav.labels,
        progress: ThemeProgress.inlinePlacement,
        player: ThemePlayerLayout(showVolume: true),
        home: {
          'sections': ['recent', 'featured'],
        },
        responsive: {
          'sm': {
            'nav': 'rail',
            'player': {'showVolume': false},
          },
        },
      );

      final compact = applyResponsiveLayout(layout, 600);
      expect(compact.nav, ThemeNav.rail);
      expect(compact.player.showVolume, isFalse);
      expect(compact.player.showTrackDetails, isTrue);
      expect(compact.home, base.home);

      // Above the tier the base layout is untouched.
      final wide = applyResponsiveLayout(layout, 1400);
      expect(wide.nav, base.nav);
      expect(wide.progress, base.progress);
      expect(wide.player.showVolume, isTrue);
      expect(wide.home, base.home);
      expect(wide.responsive, layout.responsive);
    });

    test('unknown variants and malformed values are ignored', () {
      const layout = ThemeLayout(
        responsive: {
          'huge': {'nav': 'rail'},
          'compact': {
            'nav': 'nonsense',
            'progress': 'sideways',
          },
        },
      );

      final wide = applyResponsiveLayout(layout, 1400);
      expect(wide.nav, ThemeNav.labels);
      expect(wide.progress, ThemeProgress.inlinePlacement);

      final compact = applyResponsiveLayout(layout, 400);
      expect(compact.nav, ThemeNav.labels);
      expect(compact.progress, ThemeProgress.inlinePlacement);
    });
  });

  group('responsive regions', () {
    test('a variant can hand the sidebar to the theme and drop the aside', () {
      const base = ThemeLayout(
        sidebar: ThemeSidebar.theme,
        sidebarWidth: 240,
        aside: ThemeAside.theme,
        asideWidth: 360,
        responsive: {
          'compact': {
            'sidebar': 'host',
            'sidebarWidth': 180,
            'aside': 'none',
          },
          'expanded': {
            'asideWidth': 400,
          },
        },
      );

      final compact = applyResponsiveLayout(base, 600);
      expect(compact.sidebar, ThemeSidebar.host);
      expect(compact.sidebarWidth, 180);
      expect(compact.aside, ThemeAside.none);
      // Unset in this variant: the base width carries over.
      expect(compact.asideWidth, 360);

      final medium = applyResponsiveLayout(base, 900);
      expect(medium.sidebar, ThemeSidebar.theme);
      expect(medium.sidebarWidth, 240);
      expect(medium.aside, ThemeAside.theme);

      final expanded = applyResponsiveLayout(base, 1400);
      expect(expanded.sidebar, ThemeSidebar.theme);
      expect(expanded.sidebarWidth, 240);
      expect(expanded.asideWidth, 400);
    });

    test('unknown region names and malformed widths are ignored', () {
      const layout = ThemeLayout(
        sidebar: ThemeSidebar.theme,
        sidebarWidth: 220,
        responsive: {
          'compact': {
            'sidebar': 'left',
            'aside': 'right',
            'sidebarWidth': 'wide',
            'asideWidth': double.nan,
          },
        },
      );

      final compact = applyResponsiveLayout(layout, 600);
      expect(compact.sidebar, ThemeSidebar.theme);
      expect(compact.aside, ThemeAside.none);
      expect(compact.sidebarWidth, 220);
      expect(compact.asideWidth, isNull);
    });

    test('variant widths are clamped to the contract range', () {
      const layout = ThemeLayout(
        responsive: {
          'compact': {'sidebarWidth': -5, 'asideWidth': 5000},
        },
      );

      final compact = applyResponsiveLayout(layout, 600);
      expect(compact.sidebarWidth, 0);
      expect(compact.asideWidth, 1000);
    });
  });

  group('resolved regions', () {
    test('the merged layout answers ownership and widths', () {
      const layout = ThemeLayout(
        sidebar: ThemeSidebar.theme,
        sidebarWidth: 240,
        aside: ThemeAside.theme,
        asideWidth: 360,
        responsive: {
          'compact': {'aside': 'none'},
        },
      );

      final compact = resolveLayout(
        layout,
        width: 600,
        userDock: PlayerDock.fullWidth,
      );
      expect(compact.sidebarOwned, isTrue);
      expect(compact.asideEnabled, isFalse, reason: 'compact drops the aside');
      expect(compact.sidebarWidth, 240);
      expect(compact.asideWidth, 360);

      final wide = resolveLayout(
        layout,
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );
      expect(wide.sidebarOwned, isTrue);
      expect(wide.asideEnabled, isTrue);
      expect(wide.sidebarWidth, 240);
      expect(wide.asideWidth, 360);
    });

    test('the host defaults are reported when the theme says nothing', () {
      final resolved = resolveLayout(
        const ThemeLayout(),
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );

      expect(resolved.sidebarOwned, isFalse);
      expect(resolved.asideEnabled, isFalse);
      expect(resolved.sidebarWidth, isNull);
      expect(resolved.asideWidth, isNull);
    });
  });

  group('resolved layout', () {
    test('a compact dock asks for the docked bar', () {
      const layout = ThemeLayout(
        player: ThemePlayerLayout(dock: ThemePlayerDock.compact),
      );
      final resolved = resolveLayout(
        layout,
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );
      expect(resolved.playerDock, PlayerDock.docked);
    });

    test('every other dock name defers to the user', () {
      for (final dock in [
        ThemePlayerDock.full,
        ThemePlayerDock.floating,
        ThemePlayerDock.stage,
      ]) {
        final resolved = resolveLayout(
          ThemeLayout(player: ThemePlayerLayout(dock: dock)),
          width: 1400,
          userDock: PlayerDock.docked,
        );
        expect(resolved.playerDock, PlayerDock.docked, reason: '$dock');
      }
    });

    test('a v3 enforce claim is ignored', () {
      const layout = ThemeLayout(
        player: ThemePlayerLayout(dock: ThemePlayerDock.full),
        enforce: ['playerDock'],
      );
      final resolved = resolveLayout(
        layout,
        width: 1400,
        userDock: PlayerDock.docked,
      );
      expect(resolved.playerDock, PlayerDock.docked);
    });

    test('a hidden volume control is a theme override; visible defers', () {
      final hidden = resolveLayout(
        const ThemeLayout(
          player: ThemePlayerLayout(showVolume: false),
        ),
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );
      expect(hidden.volumeOverride, isFalse);

      final visible = resolveLayout(
        const ThemeLayout(),
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );
      expect(visible.volumeOverride, isNull);
    });

    test('the breakpoint variant is applied before resolution', () {
      const layout = ThemeLayout(
        player: ThemePlayerLayout(showVolume: true, dock: ThemePlayerDock.full),
        responsive: {
          'compact': {
            'player': {'showVolume': false, 'dock': 'compact'},
          },
        },
      );
      final compact = resolveLayout(
        layout,
        width: 600,
        userDock: PlayerDock.fullWidth,
      );
      expect(compact.breakpoint, ThemeBreakpoint.compact);
      expect(compact.volumeOverride, isFalse);
      expect(compact.playerDock, PlayerDock.docked);

      final wide = resolveLayout(
        layout,
        width: 1400,
        userDock: PlayerDock.fullWidth,
      );
      expect(wide.breakpoint, ThemeBreakpoint.expanded);
      expect(wide.volumeOverride, isNull);
      expect(wide.playerDock, PlayerDock.fullWidth);
    });
  });

  group('navigation entries', () {
    const host = ['home', 'radio', 'stats'];

    test('a non-empty list is the whole surface', () {
      expect(
        resolveThemeItems(
          hostIds: host,
          themeIds: ['stats', 'home'],
          screens: const {},
        ),
        ['stats', 'home'],
      );
    });

    test('an empty list keeps the host surface', () {
      expect(
        resolveThemeItems(
          hostIds: host,
          themeIds: const [],
          screens: const {},
        ),
        host,
      );
    });

    test('unknown ids are dropped and duplicates collapse', () {
      expect(
        resolveThemeItems(
          hostIds: host,
          themeIds: ['radio', 'radio', 'nope', 'home'],
          screens: const {},
        ),
        ['radio', 'home'],
      );
    });

    test('a theme screen is a valid destination', () {
      expect(
        resolveThemeItems(
          hostIds: host,
          themeIds: ['screen:studio', 'home'],
          screens: {'studio'},
        ),
        ['screen:studio', 'home'],
      );
    });

    test('a list of only unknown ids falls back to the host', () {
      expect(
        resolveThemeItems(
          hostIds: host,
          themeIds: ['nope', 'screen:missing'],
          screens: const {},
        ),
        host,
      );
    });

    test('a theme screen survives the prefixed screen map', () {
      // The navigation surface keys screens by `screen:<id>`; the resolver
      // matches bare ids, so this is the wiring that used to drop them.
      final playlists = SideBarTiles(
        id: 'playlists',
        title: 'Playlists',
        pathPrefix: '/library/playlists',
        icon: SpotubeIcons.playlist,
      );
      final studio = SideBarTiles.screen(id: 'studio', title: 'Studio');

      final entries = themeEntriesFor(
        host: [playlists],
        themeIds: const ['screen:studio', 'playlists'],
        screens: {'screen:studio': studio},
      );

      expect(entries.map((entry) => entry.id), ['screen:studio', 'playlists']);
      expect(entries.first.screenId, 'studio');
    });
  });

  group('section lists', () {
    const defaults = ['recent', 'featured', 'new_releases', 'browse'];

    test('without a list the host order stands', () {
      expect(
        resolveThemeSections(defaults: defaults, block: const {}),
        defaults,
      );
    });

    test('a list filters unknown ids and collapses duplicates', () {
      expect(
        resolveThemeSections(
          defaults: defaults,
          block: const {
            'sections': ['browse', 'bogus', 'browse', 'recent'],
          },
        ),
        ['browse', 'recent'],
      );
    });

    test('an empty or malformed list keeps the host order', () {
      expect(
        resolveThemeSections(
          defaults: defaults,
          block: const {'sections': <String>[]},
        ),
        defaults,
      );
      expect(
        resolveThemeSections(
          defaults: defaults,
          block: const {'sections': 'browse'},
        ),
        defaults,
      );
    });
  });

  group('titlebar fields', () {
    test('values are clamped, booleans are only booleans', () {
      const layout = ThemeLayout(
        titlebar: {'height': 900, 'padding': -4, 'showBack': 'yes'},
      );
      expect(themeTitlebarHeight(layout), 200);
      expect(themeTitlebarPadding(layout), 0);
      expect(themeTitlebarShowBack(layout), isNull);
    });

    test('absent fields are null so the host keeps its own geometry', () {
      expect(themeTitlebarHeight(const ThemeLayout()), isNull);
      expect(themeTitlebarPadding(const ThemeLayout()), isNull);
      expect(themeTitlebarShowBack(const ThemeLayout()), isNull);
    });
  });

  group('branding', () {
    test('defaults to the host when a theme says nothing', () {
      final branding = ThemeBranding.from(null);
      expect(branding.appName, 'Spotube');
      expect(branding.wordmark, 'Spotube');
      expect(branding.windowTitle, 'Spotube');
    });

    test('reads names and marks, falling back per field', () {
      final branding = ThemeBranding.from(
        _definition({
          'appName': 'Aurora',
          'windowTitle': 'Aurora Music',
          'wordmark': {
            'text': 'AURORA',
            'fontFamily': 'Silkscreen',
            'asset': 'asset://images/wordmark.png',
          },
          'logo': 'asset://images/logo.png',
        }),
      );

      expect(branding.shortName, 'Aurora');
      expect(branding.aboutName, 'Aurora');
      expect(branding.notificationName, 'Aurora');
      expect(branding.windowTitle, 'Aurora Music');
      expect(branding.wordmark, 'AURORA');
      expect(branding.wordmarkFont, 'Silkscreen');
      expect(branding.wordmarkAsset, 'asset://images/wordmark.png');
      expect(branding.logoAsset, 'asset://images/logo.png');
    });

    test('rejects values that could not be rendered safely', () {
      final branding = ThemeBranding.from(
        _definition({
          'appName': 'x' * 100,
          'wordmark': {
            'fontFamily': 'bad family!',
            'asset': '/etc/passwd',
          },
        }),
      );

      expect(branding.appName, 'Spotube');
      expect(branding.wordmarkFont, 'Cookie');
      expect(branding.wordmarkAsset, isNull);
      expect(branding.logoAsset, isNull);
    });
  });
}
