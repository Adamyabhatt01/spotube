import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/endpoints/theme.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// The two ways a theme may ship a UI: inline in `getTheme()` (obsidian), or
/// from the optional `getUi()` method (ui-demo). The host has to accept both,
/// and a broken tree must cost the UI only, never the palette.
Future<MetadataPluginThemeEndpoint> _endpoint(
  File archive,
  String entryPoint,
) async {
  final zip = ZipDecoder().decodeBytes(archive.readAsBytesSync());
  final byteCode = Uint8List.fromList(
    zip
        .firstWhere((file) => file.isFile && file.name == 'plugin.out')
        .content as List<int>,
  );
  final hetu = Hetu();
  hetu.init();
  hetu.loadBytecode(bytes: byteCode, moduleName: 'plugin');
  hetu.eval('''
import "module:plugin" as plugin

var Plugin = plugin.$entryPoint

var metadataPlugin = Plugin()
''');
  return MetadataPluginThemeEndpoint(hetu);
}

void main() {
  final obsidianArchive = File('themes/dist/obsidian-1.0.0.smplug');
  final uiDemoArchive = File('themes/dist/ui-demo-1.0.0.smplug');
  final obsidianGolden = File('themes/conformance/obsidian.json');

  group('obsidian carries its UI inline', () {
    late MetadataPluginThemeEndpoint endpoint;

    setUpAll(() async {
      endpoint = await _endpoint(obsidianArchive, 'ObsidianTheme');
    });

    test('the tree arrives with the palette', () async {
      final definition = await endpoint.getTheme();
      expect(definition, isNotNull);

      final ui = definition!.ui;
      expect(ui, isNotNull);
      expect(ui!.specVersion, 2);
      expect(ui.slots, hasLength(14));
      expect(ui.screens.keys, containsAll(<String>['now-playing', 'colophon']));
      expect(ui.templates, isEmpty);

      final stage = ui.slots['stage.center']!.children;
      expect(stage, isNotEmpty);
      expect(stage.first['type'], 'animate');
      expect(stage.first['kind'], 'rotate');
      expect(stage.first['bind'], 'player.playing');

      expect(
        ui.slots.keys,
        containsAll(<String>[
          'sidebar.header',
          'sidebar.footer',
          'player.controls',
          'stage.center',
          'stage.below',
        ]),
      );
    });

    test('a theme without getUi() answers null, not an error', () async {
      expect(await endpoint.getUi(), isNull);
    });
  }, skip: !obsidianArchive.existsSync());

  group('ui-demo answers from getUi()', () {
    late MetadataPluginThemeEndpoint endpoint;

    setUpAll(() async {
      endpoint = await _endpoint(uiDemoArchive, 'UiDemoTheme');
    });

    test('getTheme carries no inline tree', () async {
      final definition = await endpoint.getTheme();
      expect(definition, isNotNull);
      expect(definition!.ui, isNull);
    });

    test('slots, screens and templates survive the endpoint', () async {
      final ui = await endpoint.getUi();
      expect(ui, isNotNull);
      expect(ui!.specVersion, 1);
      expect(ui.slots.keys, contains('sidebar.footer'));
      expect(ui.slots['sidebar.footer']!.children, isNotEmpty);

      final screen = ui.screens['now-playing'];
      expect(screen, isNotNull);
      expect(screen!.title, 'Now playing');
      expect(screen.showBack, isTrue);
      expect(screen.children, isNotEmpty);

      final template = ui.templates['trackRow'];
      expect(template, isNotNull);
      expect(template!.params, <String>['title', 'artist']);
      expect(template.children, isNotEmpty);
    });
  }, skip: !uiDemoArchive.existsSync());

  group('the model', () {
    Map<String, dynamic> payload() =>
        jsonDecode(obsidianGolden.readAsStringSync()) as Map<String, dynamic>;

    test('keeps a valid tree through a JSON round trip', () {
      final definition = ThemeDefinition.fromJson(payload());
      final roundTripped =
          ThemeDefinition.fromJson(definition.toJson());

      expect(roundTripped.ui, isNotNull);
      expect(roundTripped.ui!.slots, hasLength(14));
      expect(
        roundTripped.ui!.slots['stage.center']!.children.first['type'],
        'animate',
      );
      expect(
        roundTripped.ui!.screens['colophon']!.children,
        isNotEmpty,
      );
    });

    test('drops a malformed tree and keeps the palette', () {
      final original = ThemeDefinition.fromJson(payload());
      final broken = payload();
      (broken['ui'] as Map<String, dynamic>)['slots'] = 'not a map';

      final definition = ThemeDefinition.fromJson(broken);
      expect(definition.ui, isNull);
      expect(definition.light.primary, original.light.primary);
      expect(definition.dark.background, original.dark.background);
    });

    test('parses the v3 asset background', () {
      final definition = ThemeDefinition.fromJson(payload());
      expect(definition.background.source, ThemeBackgroundSource.asset);
      expect(
        definition.background.asset,
        'asset://textures/obsidian.png',
      );
      expect(definition.background.tile, isTrue);
      expect(definition.background.scale, 4);
    });

    test('clamps a wild tile scale and drops an unknown source', () {
      final raw = payload();
      (raw['background'] as Map<String, dynamic>)['scale'] = 99;
      (raw['background'] as Map<String, dynamic>)['source'] = 'not-a-source';

      final definition = sanitizeThemeDefinition(
        ThemeDefinition.fromJson(raw),
      );
      expect(definition.background.scale, 8);
      expect(definition.background.source, ThemeBackgroundSource.none);
    });
  }, skip: !obsidianGolden.existsSync());
}
