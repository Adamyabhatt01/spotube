// The v4 conformance fixtures are the contract's source of truth.
//
// One fixture per feature family keeps the docs honest: if a node, binding or
// capability is described in AUTHORING but is absent here, the feature has no
// executable example. Validation alone is not enough — a fixture can be valid
// and still never touch the palette, the sidebar, an input, a page or audio.

import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File('$repoRoot/$path').readAsStringSync())
          as Map<String, dynamic>;

  final kitchenSink = readJson('conformance/draft/v4-kitchen-sink.json');
  final ui = kitchenSink['ui'] as Map<String, dynamic>;
  final slots = ui['slots'] as Map<String, dynamic>;

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

  test('the feature fixture is a clean v4 payload', () {
    final report = validateThemePayload(kitchenSink);
    expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    expect(report.warningCount, 0, reason: report.issues.join('\n'));
    expect(kitchenSink['specVersion'], 4);
  });

  test('every draft fixture validates cleanly', () {
    for (final entry in Directory('$repoRoot/conformance/draft').listSync()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final payload =
          jsonDecode(entry.readAsStringSync()) as Map<String, dynamic>;
      // The v3 fixture stays for the migration tests; it is not a v4 target.
      if (payload['specVersion'] != 4) continue;
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: entry.path);
      expect(report.warningCount, 0, reason: entry.path);
    }
  });

  test('the palette feature has a fixture', () {
    final hasPaletteBinding = nodes(ui).any(
      (node) => node.values.any(
        (value) => value is String && value.startsWith('palette.'),
      ),
    );
    final hasPaletteToken = nodes(ui).any(
      (node) => node.values.any(
        (value) => value is String && value.startsWith('@palette.'),
      ),
    );
    expect(hasPaletteBinding, isTrue);
    expect(hasPaletteToken, isTrue);
  });

  test('the sidebar feature has a fixture', () {
    expect(slots, contains('sidebar.content'));
    expect(slots, contains('aside.content'));
    expect((kitchenSink['layout'] as Map)['sidebar'], 'theme');
    expect((kitchenSink['layout'] as Map)['aside'], 'theme');
  });

  test('the input feature has a fixture', () {
    final types = nodes(ui).map((node) => node['type']).toSet();
    expect(
      types,
      containsAll([
        'slider',
        'textField',
        'checkbox',
        'radioGroup',
        'select',
        'textArea',
        'segmented',
        'switch',
      ]),
    );
  });

  test('the pages feature has a fixture', () {
    final pages = (ui['pages'] as List).cast<Map>();
    expect(pages, isNotEmpty);
    expect(kitchenSink['pages'], isNotEmpty);
    for (final page in pages) {
      expect(slots, contains('page.${page['id']}'));
    }
  });

  test('the audio feature has a fixture', () {
    final bindings = nodes(ui)
        .map((node) => node['bind'])
        .whereType<String>()
        .where((binding) => binding.startsWith('audio.'))
        .toSet();
    expect(bindings, containsAll(['audio.bass', 'audio.normalization']));
    expect((kitchenSink['capabilities'] as List), contains('audio.effects'));
  });
}
