import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:spotube_themes/v3_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// The Spotify shell is the "no plugin texture, no bitmap" end of the v3
/// contract: a palette, Inter, a labelled inset shell and page bodies drawn
/// with the primitives. These tests pin the things a validator cannot see —
/// that the text stays readable, that the theme is genuinely opaque, that the
/// artwork files are real, and that every page it takes over has a way back
/// for a signed-out user.
void main() {
  final repoRoot = Directory.current.path;
  final themeDir = '$repoRoot/themes/spotify-shell';
  final payload =
      jsonDecode(
            File('$repoRoot/conformance/spotify-shell.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final ui = payload['ui'] as Map<String, dynamic>;
  final slots = ui['slots'] as Map<String, dynamic>;

  /// Every `asset://` string anywhere in a tree.
  Set<String> assetPaths(Object? node) {
    final paths = <String>{};
    void walk(Object? value) {
      if (value is String) {
        if (value.startsWith('asset://')) paths.add(value);
      } else if (value is Map) {
        for (final child in value.values) {
          walk(child);
        }
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    walk(node);
    return paths;
  }

  /// Every node map in a tree, including the root.
  List<Map> nodes(Object? node) {
    final found = <Map>[];
    void walk(Object? value) {
      if (value is Map) {
        if (value['type'] is String) found.add(value);
        for (final child in value.values) {
          walk(child);
        }
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    walk(node);
    return found;
  }

  /// Every binding a tree reads, from both `bind` and nested actions.
  Set<String> bindings(Object? node) {
    final names = <String>{};
    void walk(Object? value) {
      if (value is Map) {
        if (value['bind'] is String) names.add(value['bind'] as String);
        for (final child in value.values) {
          walk(child);
        }
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    walk(node);
    return names;
  }

  double channel(int value) {
    final c = value / 255.0;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(String hex) {
    final value = int.parse(hex.substring(1, 7), radix: 16);
    return 0.2126 * channel((value >> 16) & 0xff) +
        0.7152 * channel((value >> 8) & 0xff) +
        0.0722 * channel(value & 0xff);
  }

  double contrast(String a, String b) {
    final x = luminance(a);
    final y = luminance(b);
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  group('the spotify-shell payload', () {
    test('validates with no errors and no warnings for the migration tools', () {
      final report = validateLegacyThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(
        report.issues.where((issue) => issue.severity == Severity.warning),
        isEmpty,
        reason:
            'a published theme should be clean, not merely valid:\n'
            '${report.issues.join('\n')}',
      );
    });

    test('the v4 host rejects it until Phase 11 migrates it', () {
      final report = validateThemePayload(payload);
      expect(report.issues, hasLength(1));
      expect(
        report.issues.single.message,
        'specVersion 3 is not supported; migrate to 4',
      );
    });

    test('its UI document validates on its own', () {
      final issues = validateUiSpec(ui);
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('is a v3 payload with a v2 UI', () {
      expect(payload['specVersion'], 3);
      expect(ui['specVersion'], 2);
    });

    test('uses only the flat node shape', () {
      final withProps = nodes(ui).where((node) => node.containsKey('props'));
      expect(
        withProps,
        isEmpty,
        reason: 'the legacy props object is accepted, not used',
      );
    });

    test('every button does something', () {
      final silent = nodes(ui).where(
        (node) =>
            node['type'] == 'button' &&
            node['action'] == null &&
            node['actions'] == null,
      );
      expect(silent, isEmpty);
    });

    test('every action names a verb the host implements', () {
      for (final node in nodes(ui)) {
        for (final action in [
          if (node['action'] is Map) node['action'] as Map,
          if (node['actions'] is List)
            ...(node['actions'] as List).whereType<Map>(),
        ]) {
          expect(
            uiActionTypes,
            contains(action['type']),
            reason: '${node['type']} carries an unknown action',
          );
        }
      }
    });
  });

  group('the shell', () {
    test('is a labelled, inset, opaque Spotify frame', () {
      final layout = payload['layout'] as Map;
      expect(layout['chrome'], 'inset');
      expect(layout['nav'], 'labels');
      expect(layout['progress'], 'below');
      expect((layout['player'] as Map)['dock'], 'full');

      final surfaces = payload['surfaces'] as Map;
      expect(surfaces['opacity'], 1.0);
      expect(surfaces['blur'], 0.0);

      final background = payload['background'] as Map;
      // A shell-sourced backdrop at opacity 0 still turns the scaffold
      // transparent and decodes a wallpaper nothing paints.
      expect(background['source'], 'none');
      expect(background['opacity'], 0.0);
      expect(background['transparent'], isFalse);
    });

    test('claims the navigation it draws', () {
      final layout = payload['layout'] as Map;
      expect(
        layout['enforce'],
        containsAll(<String>['nav', 'navItems', 'navbarItems', 'libraryItems']),
      );
      expect(layout['navItems'], ['home', 'search']);
      expect(layout['navbarItems'], ['home', 'search', 'library']);
      expect(layout['libraryItems'], [
        'playlists',
        'albums',
        'artists',
        'local_library',
      ]);
    });

    test('the compact variant keeps the shell but drops the extras', () {
      final compact =
          ((payload['layout'] as Map)['responsive'] as Map)['compact'] as Map;
      expect(compact['nav'], 'labels');
      expect((compact['titlebar'] as Map)['height'], 40.0);
      expect((compact['player'] as Map)['showVolume'], isFalse);
      expect((compact['player'] as Map)['showLyrics'], isFalse);
    });

    test('names Inter and ships the four weights the type scale uses', () {
      final tokens = payload['tokens'] as Map;
      expect(tokens['fontFamily'], 'Inter');
      expect(tokens['cardWidth'], 180.0);
      expect(tokens['gutter'], 20.0);

      final typography = payload['typography'] as Map;
      expect(typography['family'], 'Inter');
      expect(typography['brandFamily'], 'Inter');
      final fonts = typography['fonts'] as List;
      expect(fonts, hasLength(4));
      expect(
        fonts.map((font) => (font as Map)['family']),
        everyElement('Inter'),
      );
      expect(
        fonts.map((font) => (font as Map)['weight']),
        containsAll(<double>[400.0, 500.0, 700.0, 800.0]),
      );
    });
  });

  group('the palettes', () {
    test('both schemes carry the v2 roles and all the v3 extras', () {
      const v2 = [
        'background',
        'foreground',
        'card',
        'cardForeground',
        'primary',
        'primaryForeground',
        'secondary',
        'secondaryForeground',
        'muted',
        'mutedForeground',
        'accent',
        'accentForeground',
        'destructive',
        'destructiveForeground',
        'border',
        'input',
        'ring',
      ];
      for (final scheme in ['light', 'dark']) {
        final palette = payload[scheme] as Map<String, dynamic>;
        expect(
          palette.keys,
          containsAll([...v2, ...v3PaletteRoles]),
          reason: '$scheme is missing a role',
        );
        for (final entry in palette.entries) {
          expect(
            entry.value,
            isA<String>(),
            reason: '$scheme.${entry.key} must be a colour',
          );
          expect(
            RegExp(
              r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$',
            ).hasMatch(entry.value as String),
            isTrue,
            reason: '$scheme.${entry.key} is not a hex colour',
          );
        }
      }
    });

    test('is Spotify black and green, not a Caelestia palette', () {
      final dark = payload['dark'] as Map<String, dynamic>;
      final light = payload['light'] as Map<String, dynamic>;
      expect(dark['background'], '#121212');
      expect(dark['primary'], '#1ed760');
      expect(dark['primaryForeground'], '#000000');
      expect(light['primary'], '#1ed760');
      expect(light['primaryForeground'], '#000000');
    });

    test('body text is readable in both schemes', () {
      for (final scheme in ['light', 'dark']) {
        final palette = payload[scheme] as Map<String, dynamic>;
        expect(
          contrast(
            palette['foreground'] as String,
            palette['background'] as String,
          ),
          greaterThanOrEqualTo(7.0),
          reason: '$scheme foreground on background',
        );
        expect(
          contrast(
            palette['cardForeground'] as String,
            palette['card'] as String,
          ),
          greaterThanOrEqualTo(7.0),
          reason: '$scheme card text',
        );
        expect(
          contrast(
            palette['primaryForeground'] as String,
            palette['primary'] as String,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme primary button text',
        );
        expect(
          contrast(
            palette['mutedForeground'] as String,
            palette['background'] as String,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme muted text',
        );
        expect(
          contrast(
            palette['sidebarForeground'] as String,
            palette['sidebar'] as String,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme sidebar text',
        );
        // The sidebar's primary/fill pair is the one a theme most easily
        // writes as one colour twice — every shadcn legacy scheme keeps the
        // pair at opposite ends of the ramp.
        expect(
          contrast(
            palette['sidebarPrimaryForeground'] as String,
            palette['sidebarPrimary'] as String,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme sidebar primary text',
        );
      }
    });
  });

  group('the page bodies', () {
    test('every primary page the host can hand over is drawn by the theme', () {
      expect(
        slots.keys,
        containsAll(<String>[
          'sidebar.header',
          'sidebar.footer',
          'home.content',
          'collection.content',
          'artist.content',
          'search.content',
          'queue.content',
          'downloads.content',
          'stats.content',
        ]),
      );
    });

    test('draws its own seek line with elapsed and total time', () {
      final progress = slots['player.progress'];
      expect(progress, isNotNull);
      final names = bindings(progress).toSet();
      expect(names, containsAll(<String>['player.position', 'player.duration']));
    });

    test('each page body reads its own scope, never another page\'s', () {
      const scopeOf = <String, String>{
        'home.content': 'home.',
        'collection.content': 'collection.',
        'artist.content': 'artist.',
        'search.content': 'search.',
        'queue.content': 'queue.',
        'downloads.content': 'downloads.',
        'stats.content': 'stats.',
      };
      for (final entry in scopeOf.entries) {
        final found = bindings(slots[entry.key])
            .where((name) => name.contains('.') && !name.startsWith('item.'))
            .where((name) => !name.startsWith('player.'))
            .where((name) => !name.startsWith('user.'))
            .where((name) => !name.startsWith('app.'));
        expect(
          found.where((name) => !name.startsWith(entry.value)),
          isEmpty,
          reason: '${entry.key} reads another page\'s scope',
        );
      }
    });

    test('the home page draws its own top bar and links into the app', () {
      final home = nodes(slots['home.content']);
      expect(
        home.where(
          (node) =>
              node['type'] == 'search' &&
              node['placeholder'] == 'What do you want to play?',
        ),
        isNotEmpty,
        reason: 'the chrome field must focus in place, not navigate',
      );
      expect(
        home.where(
          (node) =>
              node['type'] == 'button' &&
              (node['action'] as Map)['type'] == 'openSettings',
        ),
        isNotEmpty,
      );
    });

    test(
      'a signed-out user is told how to sign in instead of a blank page',
      () {
        final panel = nodes(slots['home.content']).where(
          (node) =>
              node['type'] == 'conditional' &&
              node['bind'] == 'user.name' &&
              node['invert'] == true,
        );
        expect(
          panel,
          isNotEmpty,
          reason: 'home.content replaces the host\'s anonymous fallback',
        );
        expect(
          nodes(panel.first).where(
            (node) =>
                node['type'] == 'button' &&
                (node['action'] as Map)['type'] == 'openSettings',
          ),
          isNotEmpty,
        );
      },
    );

    test('no dead "show all" link points at the page it is already on', () {
      final deadLinks = nodes(slots['home.content']).where(
        (node) =>
            node['type'] == 'button' &&
            node['label'] == 'Show all' &&
            node['action'] is Map &&
            (node['action'] as Map)['type'] == 'navigate' &&
            ((node['action'] as Map)['args'] as Map?)?['target'] == 'home',
      );
      expect(deadLinks, isEmpty);
    });
  });

  group('the assets', () {
    test('declares every file it ships, and ships every file it declares', () {
      final declared = <String>{};
      for (final entries in (payload['assets'] as Map).values) {
        for (final entry in entries as List) {
          declared.add((entry as Map)['path'] as String);
        }
      }
      expect(
        declared.length,
        (payload['assets'] as Map).values.fold<int>(
          0,
          (sum, entries) => sum + (entries as List).length,
        ),
        reason: 'an asset is declared twice',
      );

      final shipped = Directory('$themeDir/assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (file) =>
                'asset://${p.relative(file.path, from: '$themeDir/assets').replaceAll(r'\', '/')}',
          )
          .toSet();

      expect(declared, shipped);
    });

    test('every asset the payload points at is declared and on disk', () {
      final referenced = assetPaths(payload);
      final declared = <String>{};
      for (final entries in (payload['assets'] as Map).values) {
        for (final entry in entries as List) {
          declared.add((entry as Map)['path'] as String);
        }
      }
      for (final path in referenced) {
        expect(declared, contains(path));
        expect(
          File(
            '$themeDir/assets/${path.substring('asset://'.length)}',
          ).existsSync(),
          isTrue,
          reason: '$path is pointed at but not shipped',
        );
      }
    });

    test('the fonts are real TrueType files with their licence', () {
      final fonts = (payload['typography'] as Map)['fonts'] as List;
      for (final font in fonts.cast<Map>()) {
        final file = File(
          '$themeDir/assets/${(font['asset'] as String).substring('asset://'.length)}',
        );
        expect(file.existsSync(), isTrue);
        final header = file.readAsBytesSync().sublist(0, 4);
        final isTrueType =
            header[0] == 0x00 &&
            header[1] == 0x01 &&
            header[2] == 0x00 &&
            header[3] == 0x00;
        expect(isTrueType, isTrue, reason: '${font['asset']} is not TrueType');
      }
      final licence = File('$themeDir/assets/fonts/OFL-Inter.txt');
      expect(licence.existsSync(), isTrue);
      expect(
        licence.readAsStringSync().toLowerCase(),
        contains('open font license'),
      );
    });

    test('ships a manifest that points at the same plugin', () {
      final manifest =
          jsonDecode(File('$themeDir/plugin.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['entryPoint'], 'SpotifyTheme');
      expect(manifest['abilities'], contains('theme'));
      expect(manifest['version'], '1.1.0');
      expect((payload['branding'] as Map)['wordmark'], isA<Map>());
      expect((payload['branding'] as Map)['appName'], 'Spotube');
    });
  });
}
