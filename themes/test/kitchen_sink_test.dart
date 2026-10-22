import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/v3_validator.dart';
import 'package:test/test.dart';

/// The kitchen sink is the contract's reference example: it has to carry
/// every field the contract has.
///
/// When a field is added to the payload and not to the kitchen sink, this
/// test fails — which is the point. A contract nobody exercises is a contract
/// nobody notices breaking.
void main() {
  final payload = jsonDecode(
    File('conformance/kitchen-sink.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final schema = jsonDecode(
    File('schemas/theme.v3.schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('the kitchen sink', () {
    test('carries every top-level field the schema has', () {
      final properties = (schema['properties'] as Map).keys.toSet();
      for (final key in properties) {
        expect(payload.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('carries every colour role the schema has', () {
      final defs = schema['definitions'] as Map<String, dynamic>;
      final palette = defs['palette'] as Map<String, dynamic>;
      final properties = (palette['properties'] as Map).keys.toSet();
      for (final scheme in ['light', 'dark']) {
        final colors = payload[scheme] as Map<String, dynamic>;
        for (final role in properties) {
          expect(colors.containsKey(role), isTrue,
              reason: '$scheme.$role is missing');
        }
      }
    });

    test('styles every component group the app knows', () {
      final components = payload['components'] as Map<String, dynamic>;
      for (final group in componentGroups) {
        expect(components.containsKey(group), isTrue, reason: 'missing $group');
      }
      final buttons = components['buttons'] as Map<String, dynamic>;
      for (final variant in buttonVariants) {
        expect(buttons.containsKey(variant), isTrue,
            reason: 'missing buttons.$variant');
      }
    });

    test('names every id the shell knows', () {
      final layout = payload['layout'] as Map<String, dynamic>;
      expect(layout['navItems'], containsAll(navIds));
      expect(layout['navbarItems'], containsAll(navbarIds));
      expect(layout['libraryItems'], containsAll(libraryIds));
      expect(
        (layout['home'] as Map)['sections'],
        containsAll(homeSectionIds),
      );
      expect(
        (layout['settings'] as Map)['sections'],
        containsAll(settingsSectionIds),
      );
    });

    test('carries the stage and its own UI version', () {
      expect((payload['layout'] as Map)['player']['dock'], 'stage');
      expect((payload['ui'] as Map)['specVersion'], 2);
    });

    test('carries a tiled background at whole-number magnification', () {
      final background = payload['background'] as Map<String, dynamic>;
      expect(background['tile'], isTrue);
      expect(background['scale'], isA<int>());
    });

    test('carries a pixel bevel', () {
      // Component groups are either a style (card) or a map of variants
      // (buttons), so the walk has to be recursive rather than one level.
      final styles = <String>[];
      void walk(Object? value) {
        if (value is Map) {
          final style = value['borderStyle'];
          if (style is String) styles.add(style);
          for (final child in value.values) {
            if (child is Map) walk(child);
          }
        }
      }

      walk(payload['components']);
      expect(styles, contains('pixel'));
    });

    test('exercises every node type', () {
      final found = <String>{};
      void walk(Object? node) {
        if (node is Map) {
          final type = node['type'];
          if (type is String) found.add(type);
          for (final child in (node['children'] as List?) ?? const []) {
            walk(child);
          }
        }
      }

      final ui = payload['ui'] as Map<String, dynamic>;
      for (final slot in (ui['slots'] as Map).values) {
        for (final child in (slot['children'] as List?) ?? const []) {
          walk(child);
        }
      }
      for (final screen in (ui['screens'] as Map).values) {
        for (final child in (screen['children'] as List?) ?? const []) {
          walk(child);
        }
      }
      expect(found, containsAll(uiNodeTypes));
    });

    test('exercises every prop a node type declares', () {
      final used = <String, Set<String>>{};
      void walk(Object? node) {
        if (node is! Map) return;
        final type = node['type'];
        if (type is String) {
          used.putIfAbsent(type, () => <String>{});
          for (final key in node.keys) {
            if (key != 'type' && key != 'children' && key != 'action' &&
                key != 'actions' && key != 'props') {
              used[type]!.add(key);
            }
          }
        }
        for (final child in (node['children'] as List?) ?? const []) {
          walk(child);
        }
      }

      final ui = payload['ui'] as Map<String, dynamic>;
      for (final slot in (ui['slots'] as Map).values) {
        for (final child in (slot['children'] as List?) ?? const []) {
          walk(child);
        }
      }
      for (final screen in (ui['screens'] as Map).values) {
        for (final child in (screen['children'] as List?) ?? const []) {
          walk(child);
        }
      }

      for (final entry in uiNodeProps.entries) {
        expect(used[entry.key], isNotNull,
            reason: 'no ${entry.key} node in the kitchen sink');
        for (final prop in entry.value) {
          expect(
            used[entry.key],
            contains(prop),
            reason: 'the kitchen sink does not exercise ${entry.key}.$prop',
          );
        }
      }
    });

    test('fills slots the host publishes', () {
      final ui = payload['ui'] as Map<String, dynamic>;
      final slots = ui['slots'] as Map<String, dynamic>;
      for (final slot in slots.keys) {
        expect(slotNames, contains(slot), reason: '$slot is not a slot');
      }
    });
  });

  group('the registries', () {
    test('the slot names are the ones the host publishes', () {
      // A slot name is a promise about where content ends up. The list is
      // closed, and this test is what keeps the docs and the code agreeing.
      for (final slot in slotNames) {
        expect(slot, matches(RegExp(r'^[a-z]+\.[a-z_.]+$')),
            reason: '$slot is not a slot name');
      }
    });

    test('the component groups are the ones the app knows', () {
      expect(componentGroups, isNotEmpty);
      expect(componentGroups.toSet().length, componentGroups.length,
          reason: 'a group is listed twice');
    });

    test('the bindings are namespaced', () {
      for (final binding in uiBindings) {
        expect(binding, contains('.'), reason: binding);
      }
    });
  });
}
