// Test suite for the Neon Maximalist theme.
//
// Neon Maximalist is the v4 contract stress-test: it exercises all 8 capabilities,
// all 12 host widgets, all 19 render points, all 8 context-menu targets, full
// audio-effects rig, library write, routed pages, nested shell, resizable panes,
// and theme settings.

import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/v4_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final payload =
      jsonDecode(
            File(
              '$repoRoot/conformance/neon-maximalist.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final ui = payload['ui'] as Map<String, dynamic>;
  final slots = ui['slots'] as Map<String, dynamic>;
  final templates = ui['templates'] as Map<String, dynamic>;
  final renderPoints = ui['renderPoints'] as Map<String, dynamic>;
  final menus = ui['menus'] as Map<String, dynamic>;
  final layout = payload['layout'] as Map<String, dynamic>;

  Iterable<Map> nodes(Object? node) sync* {
    if (node is Map) {
      if (node['type'] is String) yield node;
      for (final child in node.values) {
        yield* nodes(child);
      }
    } else if (node is List) {
      for (final child in node) {
        yield* nodes(child);
      }
    }
  }

  Iterable<String> allStrings(Object? obj) sync* {
    if (obj is String) {
      yield obj;
    } else if (obj is Map) {
      for (final value in obj.values) {
        yield* allStrings(value);
      }
    } else if (obj is List) {
      for (final item in obj) {
        yield* allStrings(item);
      }
    }
  }

  test('is a clean v4 payload', () {
    final report = validateThemePayload(payload);
    expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    expect(report.warningCount, 0, reason: report.issues.join('\n'));

    expect(payload['specVersion'], 4);
    expect(payload['uiKit'], 'shadcn');
    expect(layout.containsKey('enforce'), isFalse);
  });

  test('declares all 8 capabilities', () {
    final capabilities = (payload['capabilities'] as List).cast<String>();
    expect(
      capabilities,
      containsAll([
        'library.read',
        'library.write',
        'player.control',
        'audio.effects',
        'ui.pages',
        'ui.hostWidgets',
        'settings.write',
        'clipboard.write',
      ]),
    );
  });

  test('ships all 4 routed pages and their slots', () {
    final topLevel = (payload['pages'] as List).cast<Map>();
    final document = (ui['pages'] as List).cast<Map>();

    final expectedPages = [
      'neon-dashboard',
      'audio-lab',
      'library-mixer',
      'settings-lab',
    ];

    expect(topLevel.map((p) => p['id']), containsAll(expectedPages));
    expect(document.map((p) => p['id']), containsAll(expectedPages));

    for (final pageId in expectedPages) {
      expect(
        slots,
        contains('page.$pageId'),
        reason: 'page.$pageId slot must exist to render the routed page',
      );
    }
  });

  test('mounts all 12 host widgets across the theme', () {
    final hostWidgetIds = nodes(ui)
        .where((node) => node['type'] == 'hostWidget')
        .map((node) => node['id'] as String)
        .toSet();

    expect(
      hostWidgetIds,
      containsAll(v4HostWidgetIds),
      reason: 'Neon Maximalist must exercise all 12 host widgets',
    );
  });

  test('declares all 19 render points with valid templates', () {
    expect(
      renderPoints.keys,
      containsAll(v4RenderPoints),
      reason: 'All 19 v4 render points must be mapped',
    );

    for (final entry in renderPoints.entries) {
      final point = entry.key;
      final templateName = entry.value as String;
      expect(
        templates,
        contains(templateName),
        reason: 'Render point $point maps to missing template $templateName',
      );
    }
  });

  test('declares all 8 context-menu targets', () {
    expect(
      menus.keys,
      containsAll(v4ContextMenuTargets),
      reason: 'All 8 context menu targets must be declared',
    );

    for (final target in v4ContextMenuTargets) {
      final items = (menus[target] as List).cast<Map>();
      expect(items, isNotEmpty, reason: 'Target $target must have menu rows');
      for (final item in items) {
        expect(
          (item['id'] as String).startsWith('theme.'),
          isTrue,
          reason: 'Menu items must be namespaced with theme.',
        );
      }
    }
  });

  test('uses artwork-palette tokens and theme settings', () {
    final paletteTokens = allStrings(ui)
        .where((value) => value.startsWith('@palette.'))
        .toSet();

    expect(paletteTokens, isNotEmpty);
    expect(
      paletteTokens,
      containsAll(['@palette.dominant', '@palette.darkMuted']),
    );

    final settingBindings = allStrings(ui)
        .where((value) => value.startsWith('setting.'))
        .toSet();

    expect(settingBindings, containsAll(['setting.crt', 'setting.bloom']));

    final toggleActions = nodes(ui)
        .map((node) => node['action'])
        .whereType<Map>()
        .where((action) => action['type'] == 'toggleSetting')
        .toList();

    expect(toggleActions, isNotEmpty);
  });

  test('the audio lab page uses effects controls and bindings', () {
    final page = slots['page.audio-lab'];
    final bindings = nodes(page)
        .map((node) => node['bind'])
        .whereType<String>()
        .toSet();

    expect(bindings, containsAll(['audio.bass', 'audio.treble']));

    final actions = nodes(page)
        .map((node) => node['action'])
        .whereType<Map>()
        .map((action) => action['type'])
        .toSet();

    expect(actions, containsAll(['setBass', 'setTreble']));
  });
}
