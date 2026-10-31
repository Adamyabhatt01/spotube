import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:spotube_themes/v3_validator.dart';
import 'package:spotube_themes/v4_validator.dart';
import 'package:test/test.dart';

/// The published v4 schema and the reference payload that exercises it.
///
/// The schema is the machine-readable copy of the contract for editors and
/// external tooling. This suite keeps it in step with the Dart validator: a
/// node, action, binding, capability or layout value the validator accepts
/// has to be in the schema, and the v4 kitchen sink has to satisfy both.
void main() {
  final repoRoot = Directory.current.path;

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final document = readJson('$repoRoot/schemas/theme.v4.schema.json');
  late JsonSchema schema;
  late Map<String, dynamic> payload;

  setUpAll(() {
    schema = JsonSchema.create(document);
    payload = readJson('$repoRoot/conformance/draft/v4-kitchen-sink.json');
  });

  group('the v4 schema', () {
    test('is draft 7, which the Dart validator can enforce', () {
      expect(document[r'$schema'], contains('draft-07'));
      expect(document.containsKey('definitions'), isTrue);
      expect(document.containsKey(r'$defs'), isFalse);
    });

    test('declares and requires the v4 payload version', () {
      expect(document['properties']['specVersion']['const'], 4);
      expect(document['required'], contains('specVersion'));
      expect(document['additionalProperties'], isFalse);
    });

    test('knows every node type the validator accepts', () {
      final variants =
          (document['definitions'] as Map<String, dynamic>)['uiNode']
              as Map<String, dynamic>;
      final constants = <String>{
        for (final variant in variants['oneOf'] as List)
          ((variant as Map<String, dynamic>)['properties']
                  as Map<String, dynamic>)['type']['const']
              as String,
      };
      expect(
        constants,
        v4UiNodeTypes.toSet(),
        reason: 'a node type the validator accepts is not in the schema',
      );
      expect(constants.length, 57);
    });

    test('carries the common node envelope on every branch', () {
      final variants =
          (document['definitions'] as Map<String, dynamic>)['uiNode']
              as Map<String, dynamic>;
      for (final variant in variants['oneOf'] as List) {
        final properties =
            (variant as Map<String, dynamic>)['properties']
                as Map<String, dynamic>;
        final type = properties['type']['const'];
        for (final envelope in v4EnvelopeProps) {
          expect(
            properties,
            contains(envelope),
            reason: '$type is missing the $envelope envelope prop',
          );
        }
      }
    });

    test('publishes every slot and the page.<id> pattern', () {
      final anyOf =
          (document['properties']
                  as Map<
                    String,
                    dynamic
                  >)['ui']['properties']['slots']['propertyNames']['anyOf']
              as List;
      final slots = (anyOf[0] as Map<String, dynamic>)['enum'] as List;
      expect(slots.toSet(), v4SlotNames.toSet());
      expect((anyOf[1] as Map<String, dynamic>)['pattern'], isNotNull);
    });

    test('knows every action the validator dispatches', () {
      final actions =
          (document['definitions']
                  as Map<
                    String,
                    dynamic
                  >)['uiAction']['properties']['type']['enum']
              as List;
      expect(actions.toSet(), v4UiActionTypes.toSet());
    });

    test('knows every exact binding, page scope and region binding', () {
      final anyOf =
          (document['definitions']
                  as Map<String, dynamic>)['uiBinding']['anyOf']
              as List;
      final exact = (anyOf[0] as Map<String, dynamic>)['enum'] as List;
      expect(exact.toSet().containsAll(v4UiBindings), isTrue);
      expect((anyOf[1] as Map<String, dynamic>)['pattern'], isNotNull);
      expect((anyOf[2] as Map<String, dynamic>)['pattern'], isNotNull);
    });

    test('declares the closed capability and kit sets', () {
      final capabilities =
          (document['properties']
                  as Map<String, dynamic>)['capabilities']['items']['enum']
              as List;
      expect(capabilities.toSet(), v4Capabilities);

      final kit =
          (document['properties'] as Map<String, dynamic>)['uiKit']['enum']
              as List;
      expect(kit.toSet(), uiKits.toSet());
    });

    test('knows the v4 layout keys and no retired ones', () {
      final layout =
          (document['properties']
                  as Map<String, dynamic>)['layout']['properties']
              as Map<String, dynamic>;
      expect(
        layout.keys.toSet(),
        containsAll([
          'sidebar',
          'sidebarWidth',
          'aside',
          'asideWidth',
          'responsive',
        ]),
      );
      expect(layout, isNot(contains('enforce')));
      expect(layout['sidebar']['enum'], ['host', 'theme']);
      expect(layout['aside']['enum'], ['none', 'theme']);
    });

    test('closes responsive breakpoints and the dock', () {
      final responsive =
          (document['properties']
                  as Map<String, dynamic>)['layout']['properties']['responsive']
              as Map<String, dynamic>;
      expect(responsive['propertyNames']['enum'], [
        'compact',
        'medium',
        'expanded',
      ]);
      final variant =
          responsive['additionalProperties'] as Map<String, dynamic>;
      expect(variant['additionalProperties'], isFalse);
      expect(variant['properties']['player']['properties']['dock']['enum'], [
        'full',
        'compact',
        'stage',
      ]);
    });

    test('publishes the shell descriptor and its pin targets', () {
      final layout =
          (document['properties']
                  as Map<String, dynamic>)['layout']['properties']
              as Map<String, dynamic>;
      expect(layout['shell'][r'$ref'], '#/definitions/shellNode');
      expect(layout['pinTargets']['items'][r'$ref'], '#/definitions/pinTarget');

      final responsive = layout['responsive'] as Map<String, dynamic>;
      final variant =
          responsive['additionalProperties'] as Map<String, dynamic>;
      expect(
        variant['properties']['shell'][r'$ref'],
        '#/definitions/shellNode',
      );

      final shellNode =
          (document['definitions'] as Map<String, dynamic>)['shellNode']
              as Map<String, dynamic>;
      expect(shellNode['additionalProperties'], isFalse);
      expect(shellNode['oneOf'], isNotEmpty);
      expect(shellNode['allOf'], isNotEmpty);
      expect(shellNode['properties']['region']['enum'], [
        'content',
        'sidebar',
        'aside',
        'player',
        'titlebar',
        'navbar',
        'custom',
      ]);
      expect(
        shellNode['properties']['children']['items'][r'$ref'],
        '#/definitions/shellNode',
      );
      expect(
        shellNode['properties']['width'][r'$ref'],
        '#/definitions/shellSize',
      );
    });

    test('publishes theme pages at the top level and under ui', () {
      final top =
          (document['properties'] as Map<String, dynamic>)['pages']
              as Map<String, dynamic>;
      expect(top['items'][r'$ref'], '#/definitions/themePage');

      final uiPages =
          (document['properties']
                  as Map<String, dynamic>)['ui']['properties']['pages']
              as Map<String, dynamic>;
      expect(uiPages['items'][r'$ref'], '#/definitions/themePage');
      expect(
        (document['definitions']
            as Map<String, dynamic>)['themePage']['additionalProperties'],
        isFalse,
      );
    });

    test('publishes per-kit component overrides', () {
      final components =
          (document['properties']
                  as Map<String, dynamic>)['components']['properties']
              as Map<String, dynamic>;
      for (final kit in uiKits) {
        expect(components[kit][r'$ref'], '#/definitions/kitComponents');
      }
    });

    test('keeps the v3 blocks closed', () {
      for (final block in [
        'typography',
        'spacing',
        'motion',
        'scale',
        'icons',
        'components',
        'ui',
        'branding',
      ]) {
        final value =
            (document['properties'] as Map<String, dynamic>)[block]
                as Map<String, dynamic>;
        expect(
          value['additionalProperties'],
          isFalse,
          reason: '$block is open',
        );
      }
    });
  });

  group('the reference payload', () {
    test('validates against the published schema', () {
      final results = schema.validate(payload);
      expect(
        results.errors,
        isEmpty,
        reason: results.errors
            .map(
              (error) =>
                  '${error.instancePath}: ${error.message} '
                  '(schema ${error.schemaPath})',
            )
            .join('\n'),
      );
    });

    test('uses the capability list it declares', () {
      expect(payload['capabilities'], isA<List>());
      expect(
        (payload['capabilities'] as List).toSet(),
        containsAll(['ui.pages', 'ui.hostWidgets', 'audio.effects']),
      );
    });

    test('declares theme pages and routed page slots', () {
      final pages = payload['pages'] as List;
      expect(pages, isNotEmpty);

      final slots = (payload['ui'] as Map)['slots'] as Map;
      for (final page in pages) {
        expect(
          slots,
          contains('page.${page['id']}'),
          reason: '${page['id']} has no page slot',
        );
      }
    });

    test('exercises a kit override', () {
      final components = payload['components'] as Map;
      expect(components.keys, contains('shadcn'));
    });

    test('the shell fixture satisfies the schema too', () {
      final shellPayload = readJson(
        '$repoRoot/conformance/draft/v4-shell-layout.json',
      );
      final results = schema.validate(shellPayload);
      expect(
        results.errors,
        isEmpty,
        reason: results.errors
            .map(
              (error) =>
                  '${error.instancePath}: ${error.message} '
                  '(schema ${error.schemaPath})',
            )
            .join('\n'),
      );
    });
  });
}
