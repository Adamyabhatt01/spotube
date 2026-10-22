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
      final defs = schema[r'$defs'] as Map<String, dynamic>;
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
