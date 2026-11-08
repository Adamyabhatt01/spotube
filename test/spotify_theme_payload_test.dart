import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/endpoints/theme.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// Pins the `getTheme()` payload of `themes/themes/spotify-shell-v4/theme.ht`,
/// the reference theme for the v4 contract.
///
/// The theme-side suite already checks the Hetu source against its generated
/// golden; this test is the app's side of the same contract. It asserts the
/// values the host *reads* — the palette the renderer paints with, the shell
/// switches, the UI slots it mounts — rather than a full copy of the payload,
/// so adding a page to the theme does not require editing this file. The one
/// invariant worth spelling out is that sanitizing the payload changes nothing:
/// a value the app clamps is a value the theme did not actually ship.
const spotifyLight = ThemeColors(
  background: '#ffffff',
  foreground: '#000000',
  card: '#f6f6f6',
  cardForeground: '#000000',
  primary: '#1ed760',
  primaryForeground: '#000000',
  secondary: '#f0f0f0',
  secondaryForeground: '#000000',
  muted: '#f6f6f6',
  mutedForeground: '#6a6a6a',
  accent: '#ededed',
  accentForeground: '#000000',
  destructive: '#e91429',
  destructiveForeground: '#ffffff',
  border: '#e5e5e5',
  input: '#f0f0f0',
  ring: '#1ed760',
  popover: '#ffffff',
  popoverForeground: '#000000',
  sidebar: '#f6f6f6',
  sidebarForeground: '#5c5c5c',
  sidebarPrimary: '#000000',
  sidebarPrimaryForeground: '#ffffff',
  sidebarAccent: '#e9e9e9',
  sidebarAccentForeground: '#000000',
  sidebarBorder: '#e5e5e5',
  sidebarRing: '#1ed760',
  success: '#0f9d58',
  successForeground: '#ffffff',
  warning: '#b26a00',
  warningForeground: '#ffffff',
  info: '#0b57d0',
  infoForeground: '#ffffff',
  chart1: '#1ed760',
  chart2: '#0b57d0',
  chart3: '#e91429',
  chart4: '#b26a00',
  chart5: '#7c3aed',
  chart6: '#0891b2',
);

const spotifyDark = ThemeColors(
  background: '#121212',
  foreground: '#ffffff',
  card: '#181818',
  cardForeground: '#ffffff',
  primary: '#1ed760',
  primaryForeground: '#000000',
  secondary: '#1f1f1f',
  secondaryForeground: '#ffffff',
  muted: '#181818',
  mutedForeground: '#a7a7a7',
  accent: '#2a2a2a',
  accentForeground: '#ffffff',
  destructive: '#e91429',
  destructiveForeground: '#ffffff',
  border: '#292929',
  input: '#292929',
  ring: '#1ed760',
  popover: '#282828',
  popoverForeground: '#ffffff',
  sidebar: '#000000',
  sidebarForeground: '#b3b3b3',
  sidebarPrimary: '#ffffff',
  sidebarPrimaryForeground: '#000000',
  sidebarAccent: '#1a1a1a',
  sidebarAccentForeground: '#ffffff',
  sidebarBorder: '#000000',
  sidebarRing: '#1ed760',
  success: '#1ed760',
  successForeground: '#000000',
  warning: '#ffa42b',
  warningForeground: '#000000',
  info: '#4cb3ff',
  infoForeground: '#000000',
  chart1: '#1ed760',
  chart2: '#4cb3ff',
  chart3: '#e91429',
  chart4: '#ffa42b',
  chart5: '#b49bff',
  chart6: '#3ad5d5',
);

/// Where the theme lives: the in-repo `themes/` package, packaged by `tools/build.dart`.
final _pluginDir = Directory('${Directory.current.path}/themes');
final _golden = File('${_pluginDir.path}/conformance/spotify-shell-v4.json');
final _archive = File('${_pluginDir.path}/dist/spotify-shell-v4-1.0.2.smplug');

ThemeDefinition _decode(Map<String, dynamic> json) =>
    sanitizeThemeDefinition(ThemeDefinition.fromJson(json));

/// Loads bytecode and resolves `theme.getTheme()` the way the app does:
/// `MetadataPlugin.create`'s three `eval` lines, then the production endpoint,
/// which is `ThemeDefinition.fromJson` followed by `sanitizeThemeDefinition`.
Future<ThemeDefinition?> _evaluatePluginTheme(Uint8List byteCode) async {
  final hetu = Hetu();
  hetu.init();
  hetu.loadBytecode(bytes: byteCode, moduleName: 'plugin');
  hetu.eval('''
import "module:plugin" as plugin

var Plugin = plugin.SpotifyTheme

var metadataPlugin = Plugin()
''');
  return await MetadataPluginThemeEndpoint(hetu).getTheme();
}

void main() {
  // The theme-side golden is the payload every other assertion reads. Its own
  // suite is what keeps it honest; here it only has to exist.
  final payload =
      jsonDecode(_golden.readAsStringSync()) as Map<String, dynamic>;

  group('Spotify shell v4 payload', () {
    test('is a v4 theme whose UI document the host understands', () {
      final theme = _decode(payload);
      expect(theme.specVersion, 4);
      expect(theme.uiKit, 'shadcn');
      expect(theme.ui, isNotNull);
      // The document format version is a separate axis from the payload
      // contract version: a v4 payload carries a `specVersion: 2` document.
      expect(theme.ui!.specVersion, 2);
      expect(theme.dynamicTheme, isNull);
    });

    test('is Spotify black and green in both schemes', () {
      final theme = _decode(payload);
      expect(theme.dark.background, '#121212');
      expect(theme.dark.card, '#181818');
      expect(theme.dark.primary, '#1ed760');
      expect(theme.dark.primaryForeground, '#000000');
      expect(theme.dark.mutedForeground, '#a7a7a7');
      expect(theme.light.background, '#ffffff');
      expect(theme.light.card, '#f6f6f6');
      expect(theme.light.primary, '#1ed760');
      expect(theme.light.primaryForeground, '#000000');
    });

    test(
        'defines every colour role so the sidebar and status colours are its own',
        () {
      expect(_decode(payload).light, spotifyLight);
      expect(_decode(payload).dark, spotifyDark);
    });

    test('is opaque: no backdrop, blur or translucency', () {
      final theme = _decode(payload);
      expect(theme.surfaces.opacity, 1.0);
      expect(theme.surfaces.blur, 0.0);
      // A `shell` backdrop at opacity 0 still turns the scaffold transparent
      // and decodes a wallpaper nothing paints.
      expect(theme.background.source, ThemeBackgroundSource.none);
      expect(theme.background.opacity, 0.0);
      expect(theme.background.transparent, isFalse);
    });

    test('asks for the inset, labelled, inline-progress shell', () {
      final theme = _decode(payload);
      expect(theme.layout.chrome, ThemeChrome.inset);
      expect(theme.layout.nav, ThemeNav.labels);
      // Spotify keeps the seek line inside the transport block. A full-width
      // line under the bar doubles the footer height and breaks parity.
      expect(theme.layout.progress, ThemeProgress.inlinePlacement);
      expect(theme.layout.player.dock, ThemePlayerDock.full);
      // v4 has no `enforce` list: a theme overrides the user only for the keys
      // it actually sends. It owns the aside instead.
      expect(theme.layout.aside, ThemeAside.theme);
      expect(theme.layout.asideWidth, 300.0);
      expect(theme.layout.navItems, ['home', 'search']);
      expect(theme.layout.navbarItems, ['home', 'search', 'library']);
      expect(
        theme.layout.libraryItems,
        ['playlists', 'albums', 'artists', 'local_library'],
      );
      expect(theme.layout.titlebar['height'], 44.0);
      expect((theme.layout.responsive['compact'] as Map)['nav'], 'labels');
    });

    test('uses Inter from the four weights it ships', () {
      final theme = _decode(payload);
      expect(theme.tokens.fontFamily, 'Inter');
      expect(theme.tokens.cardWidth, 180.0);
      expect(theme.tokens.gutter, 20.0);
      expect(theme.typography['family'], 'Inter');
      expect(theme.typography['brandFamily'], 'Inter');
      expect(
        (theme.typography['fonts'] as List)
            .map((font) => (font as Map)['weight']),
        containsAll(<double>[400.0, 500.0, 700.0, 800.0]),
      );
    });

    test('fills the pages it takes over and leaves the rest to the host', () {
      final theme = _decode(payload);
      final slots = theme.ui!.slots.keys;
      expect(slots, {
        // The theme owns the whole left rail now: Home/Search, the library
        // header, filter chips, Liked Songs and the profile footer.
        'sidebar.content',
        'aside.content',
        'library.content',
        'player.leading',
        'player.controls',
        'player.trailing',
        'home.content',
        'collection.content',
        'artist.content',
        'search.content',
        'queue.content',
        'downloads.content',
        'stats.content',
        'radio.before_sections',
        'radio.after_sections',
        'page.audio',
      });
      expect(theme.ui!.screens, isEmpty);
      // v4 routes a theme page through the host shell instead of an overlay
      // screen, so the audio settings page is a `page.<id>` slot with a
      // declared parent.
      expect(theme.ui!.pages.map((page) => page.id), ['audio']);
      expect(theme.ui!.pages.first.parent, 'settings');
    });

    test('carries a signed-out way back into settings', () {
      final home = _decode(payload).ui!.slots['home.content']!.children;
      final conditional = <Map<String, dynamic>>[];
      void walk(Object? node) {
        if (node is Map<String, dynamic>) {
          if (node['type'] == 'conditional') conditional.add(node);
          node.values.forEach(walk);
        } else if (node is Map) {
          node.values.forEach(walk);
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      home.forEach(walk);
      expect(
        conditional.where(
          (node) => node['bind'] == 'user.name' && node['invert'] == true,
        ),
        isNotEmpty,
        reason: 'home.content replaces the host anonymous fallback',
      );
    });

    test('is already inside every sanitizer range', () {
      // The theme the app draws is the sanitized one, so a value that gets
      // clamped is a value the plugin did not actually send.
      final raw = ThemeDefinition.fromJson(payload);
      expect(_decode(payload), raw);
    });
  });

  // Skipped on machines without the sibling checkout — the group above pins the
  // golden, this one pins the file that has to carry the same payload.
  final built = _archive.existsSync();
  group('built spotify-shell-v4-1.0.2.smplug', () {
    late Archive zip;
    late Uint8List byteCode;

    setUpAll(() async {
      // The root Lint job does not build the themes package, so the artifact
      // may not be there on a clean checkout. The tests themselves are
      // skipped below; just don't throw while setting up for them.
      if (!_archive.existsSync()) return;
      zip = ZipDecoder().decodeBytes(_archive.readAsBytesSync());
      byteCode = Uint8List.fromList(
        zip
            .firstWhere((file) => file.isFile && file.name == 'plugin.out')
            .content as List<int>,
      );
    });

    test(
      'carries the manifest under the names the extractor looks for',
      () {
        expect(
          zip.map((file) => file.name),
          containsAll(<String>['plugin.json', 'plugin.out']),
        );
        final manifest = jsonDecode(
          utf8.decode(
            zip.firstWhere((file) => file.name == 'plugin.json').content
                as List<int>,
          ),
        ) as Map<String, dynamic>;
        expect(manifest['entryPoint'], 'SpotifyTheme');
        expect(manifest['abilities'], ['theme']);
        expect(manifest['pluginApiVersion'], '2.0.0');
        // The extraction directory is `<author>-<name>-<version>`; a row whose
        // triple does not match it gets pruned on startup.
        expect(
          '${manifest['author']}-${manifest['name']}-${manifest['version']}',
          'Adamya Bhatt-Spotify Shell v4-1.0.2',
        );
      },
      skip: !built,
    );

    test(
      'getTheme() decodes to the golden payload',
      () async {
        final theme = await _evaluatePluginTheme(byteCode);
        expect(theme, isNotNull);
        // The endpoint moves the payload-level capability grant onto the UI
        // document so the runtime can read it. The golden stores the payload
        // exactly as the theme shipped it, so the expectation applies the
        // same merge rather than weakening the comparison.
        final expected = withUiCapabilities(
          _decode(payload),
          (payload['capabilities'] as List).cast<String>(),
        );
        expect(theme, expected);
      },
      skip: !built,
    );
  });
}
