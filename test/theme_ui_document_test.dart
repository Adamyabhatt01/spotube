import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/endpoints/theme.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

/// The two ways a theme may ship a UI: inline in `getTheme()` (the reference
/// v4 theme), or from the optional `getUi()` method (ui-demo). The host has to
/// accept both, and a broken tree must cost the UI only, never the palette.
/// A `specVersion: 3` payload is the third case: its tree is refused and only
/// the palette is kept.
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
  // Obsidian published its tree as a v3 payload until the v4 port; the
  // outgoing artifact and its golden stay pinned so the gate is tested on a
  // real plugin rather than a synthetic one.
  final obsidianArchive = File('themes/dist/legacy/obsidian-1.0.0.smplug');
  final obsidianLegacyGolden = File('themes/conformance/legacy/obsidian.json');
  final uiDemoArchive = File('themes/dist/ui-demo-2.0.0.smplug');
  final referenceArchive = File('themes/dist/spotify-shell-v4-1.0.0.smplug');
  final obsidianGolden = File('themes/conformance/obsidian.json');

  group('the reference v4 theme carries its UI inline', () {
    late MetadataPluginThemeEndpoint endpoint;

    setUpAll(() async {
      endpoint = await _endpoint(referenceArchive, 'SpotifyTheme');
    });

    test('the tree arrives with the palette', () async {
      final definition = await endpoint.getTheme();
      expect(definition, isNotNull);

      final ui = definition!.ui;
      expect(ui, isNotNull);
      expect(definition.specVersion, 4);
      // The document format version and the payload contract version are
      // different axes: a v4 payload carries a `specVersion: 2` document.
      expect(ui!.specVersion, 2);
      // Capabilities are declared once, on the payload. The runtime reads
      // them off the UI document, so the endpoint has to carry them across —
      // without this every host widget mounted as an empty box.
      expect(
        ui.capabilities,
        containsAll(<String>[
          'library.read',
          'player.control',
          'audio.effects',
          'ui.pages',
          'ui.hostWidgets',
        ]),
      );
      expect(ui.slots, hasLength(13));
      expect(ui.templates, isEmpty);
      expect(ui.screens, isEmpty);
      expect(ui.pages.map((page) => page.id), contains('audio'));

      expect(
        ui.slots.keys,
        containsAll(<String>[
          'sidebar.content',
          'aside.content',
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
          'page.audio',
        ]),
      );
      for (final slot in ['home.content', 'aside.content', 'player.leading']) {
        expect(ui.slots[slot]!.children, isNotEmpty, reason: slot);
      }
    });

    test('a theme without getUi() answers null, not an error', () async {
      expect(await endpoint.getUi(), isNull);
    });
  }, skip: !referenceArchive.existsSync());

  group('a v3 theme keeps its palette and loses its UI', () {
    late MetadataPluginThemeEndpoint endpoint;

    setUpAll(() async {
      endpoint = await _endpoint(obsidianArchive, 'ObsidianTheme');
    });

    test('the endpoint refuses the tree and the colours survive', () async {
      final definition = await endpoint.getTheme();
      expect(definition, isNotNull);
      expect(definition!.specVersion, 3);
      expect(definition.ui, isNull);

      final raw = ThemeDefinition.fromJson(
        jsonDecode(obsidianLegacyGolden.readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(definition.light, raw.light);
      expect(definition.dark, raw.dark);
      expect(definition.background, raw.background);
    });
  },
  skip: !obsidianArchive.existsSync() ||
      !obsidianLegacyGolden.existsSync());

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
      expect(roundTripped.ui!.slots, hasLength(15));
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
