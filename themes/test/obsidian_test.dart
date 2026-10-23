import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:spotube_themes/v3_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// The obsidian theme is the v3 contract under load: a stage, a gated
/// animation, a tiled asset background, shipped fonts, a pixel icon set and
/// two palettes that are not variants of the same hue.
///
/// These tests check the things a validator cannot: that the files are really
/// there, that the text is readable, and that the record is the thing the
/// theme says it is.
void main() {
  final repoRoot = Directory.current.path;
  final themeDir = '$repoRoot/themes/obsidian';
  final payload = jsonDecode(
    File('$repoRoot/conformance/obsidian.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final ui = payload['ui'] as Map<String, dynamic>;

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

  double channel(int value) {
    final c = value / 255.0;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
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

  group('the obsidian payload', () {
    test('validates with no errors and no warnings', () {
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(
        report.issues.where((issue) => issue.severity == Severity.warning),
        isEmpty,
        reason: 'a published theme should be clean, not merely valid:\n'
            '${report.issues.join('\n')}',
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
      expect(withProps, isEmpty,
          reason: 'the legacy props object is accepted, not used');
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
  });

  group('the record', () {
    test('the player is a stage with both stage slots', () {
      expect((payload['layout'] as Map)['player']['dock'], 'stage');
      expect((ui['slots'] as Map).keys, containsAll(['stage.center', 'stage.below']));
    });

    test('turns only while the player is playing', () {
      final animate = nodes((ui['slots'] as Map)['stage.center'])
          .firstWhere((node) => node['type'] == 'animate');
      expect(animate['kind'], 'rotate');
      expect(animate['curve'], 'linear');
      expect(animate['bind'], 'player.playing');
      expect(animate['duration'], 24000);
      expect(animate['reverse'], isFalse);
    });

    test('is a circular, nearest-sampled record', () {
      final image = nodes((ui['slots'] as Map)['stage.center'])
          .firstWhere((node) => node['type'] == 'image');
      expect(image['src'], 'player.artwork');
      expect(image['shape'], 'circle');
      expect(image['filter'], 'nearest');
      expect(image['radius'], 999);
      expect(image['width'], image['height']);
    });

    test('carries the song name on the label inside the turning subtree', () {
      final animate = nodes((ui['slots'] as Map)['stage.center'])
          .firstWhere((node) => node['type'] == 'animate');
      final title = nodes(animate).where(
        (node) => node['type'] == 'text' && node['bind'] == 'player.title',
      );
      expect(title, isNotEmpty,
          reason: 'the title has to turn with the record, not sit outside it');
    });

    test('also prints the song below the record, unrotated', () {
      final below = nodes((ui['slots'] as Map)['stage.below']);
      expect(
        below.where(
            (node) => node['type'] == 'text' && node['bind'] == 'player.title'),
        isNotEmpty,
      );
    });
  });

  group('the palettes', () {
    test('both schemes carry the v2 roles and all the v3 extras', () {
      const v2 = [
        'background', 'foreground', 'card', 'cardForeground', 'primary',
        'primaryForeground', 'secondary', 'secondaryForeground', 'muted',
        'mutedForeground', 'accent', 'accentForeground', 'destructive',
        'destructiveForeground', 'border', 'input', 'ring',
      ];
      for (final scheme in ['light', 'dark']) {
        final palette = payload[scheme] as Map<String, dynamic>;
        expect(palette.keys, containsAll([...v2, ...v3PaletteRoles]),
            reason: '$scheme is missing a role');
        for (final entry in palette.entries) {
          expect(entry.value, isA<String>(),
              reason: '$scheme.${entry.key} must be a colour');
          expect(
            RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$')
                .hasMatch(entry.value as String),
            isTrue,
            reason: '$scheme.${entry.key} is not a hex colour',
          );
        }
      }
    });

    test('the dark scheme is obsidian and the light scheme is end stone', () {
      final dark = payload['dark'] as Map<String, dynamic>;
      final light = payload['light'] as Map<String, dynamic>;
      expect(luminance(dark['background'] as String), lessThan(0.05));
      expect(luminance(light['background'] as String), greaterThan(0.75));
    });

    test('body text is readable in both schemes', () {
      for (final scheme in ['light', 'dark']) {
        final palette = payload[scheme] as Map<String, dynamic>;
        expect(
          contrast(palette['foreground'] as String,
              palette['background'] as String),
          greaterThanOrEqualTo(7.0),
          reason: '$scheme foreground on background',
        );
        expect(
          contrast(palette['cardForeground'] as String,
              palette['card'] as String),
          greaterThanOrEqualTo(7.0),
          reason: '$scheme card text',
        );
        expect(
          contrast(palette['primaryForeground'] as String,
              palette['primary'] as String),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme primary button text',
        );
        expect(
          contrast(palette['mutedForeground'] as String,
              palette['background'] as String),
          greaterThanOrEqualTo(4.5),
          reason: '$scheme muted text',
        );
      }
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
      expect(declared.length, (payload['assets'] as Map).values
          .fold<int>(0, (sum, entries) => sum + (entries as List).length),
          reason: 'an asset is declared twice');

      final shipped = Directory('$themeDir/assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => 'asset://${p.relative(file.path, from: '$themeDir/assets').replaceAll(r'\', '/')}')
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
          File('$themeDir/assets/${path.substring('asset://'.length)}')
              .existsSync(),
          isTrue,
          reason: '$path is pointed at but not shipped',
        );
      }
    });

    test('the fonts are real TrueType files with their licences', () {
      final fonts = (payload['typography'] as Map)['fonts'] as List;
      expect(fonts, hasLength(3));
      for (final font in fonts.cast<Map>()) {
        final file = File(
          '$themeDir/assets/${(font['asset'] as String).substring('asset://'.length)}',
        );
        expect(file.existsSync(), isTrue);
        final header = file.readAsBytesSync().sublist(0, 4);
        final isTrueType = header[0] == 0x00 &&
            header[1] == 0x01 &&
            header[2] == 0x00 &&
            header[3] == 0x00;
        expect(isTrueType, isTrue, reason: '${font['asset']} is not TrueType');
      }
      for (final name in ['OFL-Silkscreen.txt', 'OFL-VT323.txt']) {
        final licence = File('$themeDir/assets/fonts/$name');
        expect(licence.existsSync(), isTrue);
        expect(
          licence.readAsStringSync().toLowerCase(),
          contains('open font license'),
        );
      }
    });

    test('every icon is a 16px PNG', () {
      final icons = (payload['icons'] as Map)['overrides'] as Map;
      expect(icons, hasLength(20));
      for (final entry in icons.entries) {
        final icon = entry.value as Map;
        final bytes = File(
          '$themeDir/assets/${(icon['asset'] as String).substring('asset://'.length)}',
        ).readAsBytesSync();
        expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
            reason: '${entry.key} is not a PNG');
        final view = ByteData.sublistView(bytes);
        expect(view.getUint32(16), 16, reason: '${entry.key} width');
        expect(view.getUint32(20), 16, reason: '${entry.key} height');
      }
    });
  });

  group('the pixel surface', () {
    test('tiles a background at whole-number magnification', () {
      final background = payload['background'] as Map;
      expect(background['source'], 'asset');
      expect(background['tile'], isTrue);
      expect(background['scale'], 4);
      expect(background['blur'], 0);
    });

    test('squares every corner it owns', () {
      final radius = payload['radius'] as Map;
      expect(radius.values, everyElement(0));
      final components = payload['components'] as Map;
      expect((components['card'] as Map)['borderStyle'], 'pixel');
      expect(
        ((components['buttons'] as Map)['primary'] as Map)['borderStyle'],
        'pixel',
      );
    });

    test('ships a brand manifest that points at the same plugin', () {
      final manifest = jsonDecode(
        File('$themeDir/plugin.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifest['entryPoint'], 'ObsidianTheme');
      expect(manifest['abilities'], contains('theme'));
      expect(manifest['version'], '1.0.0');
      expect((payload['branding'] as Map)['logo'], 'asset://images/logo.png');
    });
  });
}
