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

    test('declares exactly the top-level keys the validator accepts', () {
      // The schema is what an editor offers an author. If the two sets drift,
      // an author is told a key exists that the build then rejects, or the
      // reverse — and neither shows up as a failing theme.
      expect(
        (document['properties'] as Map<String, dynamic>).keys.toSet(),
        v4TopLevelKeys.toSet(),
      );
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

    test('declares exactly the props the validator accepts', () {
      // The prop table is what a build is checked against; the schema is what
      // an editor offers an author. Each disagreement is a prop a theme can
      // write in one of the two and have rejected by the other.
      final variants =
          (document['definitions'] as Map<String, dynamic>)['uiNode']
              as Map<String, dynamic>;
      for (final variant in variants['oneOf'] as List) {
        final properties = (variant as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
        final type = properties['type']['const'] as String;
        final accepted = v4UiNodeProps[type]!.toSet();
        // `props` is structural for every node — the legacy nested shape — and
        // a real prop of `hostWidget`. The type's own list decides which.
        final declared = properties.keys
            .toSet()
            .difference(uiStructuralKeys.difference(accepted));
        expect(
          declared.difference(accepted),
          isEmpty,
          reason: '$type: the schema declares a prop the validator rejects',
        );
        expect(
          accepted.difference(declared),
          isEmpty,
          reason: '$type: the schema hides a prop the validator accepts',
        );
      }
    });

    test('names the host widgets the host mounts', () {
      // `hostWidget.id` is the one node prop that selects a whole surface, and
      // the closed list lives in the code that mounts them.
      final variants =
          (document['definitions'] as Map<String, dynamic>)['uiNode']
              as Map<String, dynamic>;
      final branch = (variants['oneOf'] as List).cast<Map<String, dynamic>>().firstWhere(
          (variant) =>
              (variant['properties'] as Map<String, dynamic>)['type']['const'] ==
              'hostWidget');
      expect(
        (branch['properties']['id'] as Map<String, dynamic>)['enum'],
        unorderedEquals(v4HostWidgetProps.keys),
      );
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

    test(
      'accepts exactly the bindings the validator resolves, and no others',
      () {
        // A binding the schema rejects but the host resolves hides from an
        // author's editor while working in the shipped theme, and the reverse
        // builds clean then fails at runtime. `setting.*` did exactly that: the
        // validator and the host both resolved it, and nothing compared the
        // schema's branches to `isV4UiBinding` until a real theme tripped it.
        final anyOf =
            (document['definitions']
                    as Map<String, dynamic>)['uiBinding']['anyOf']
                as List;
        final exact = ((anyOf.first as Map<String, dynamic>)['enum']
                as List)
            .cast<String>();
        final patterns = <RegExp>[
          for (final branch in anyOf.skip(1))
            RegExp((branch as Map<String, dynamic>)['pattern'] as String),
        ];

        bool schemaAccepts(String name) =>
            exact.contains(name) || patterns.any((p) => p.hasMatch(name));

        final corpus = <String>{
          ...v4UiBindings,
          ...exact,
          // Open-ended scopes, the two shapes a settings page and a shell
          // descriptor rely on.
          'item.title',
          'item.artists.0.name',
          'home.row.title',
          'stats.week.count',
          'library.playlist.name',
          'setting.crt',
          'setting.waveshaper.enabled',
          'setting.a-b',
          'app.region.sidebar.collapsed',
          'app.region.player.size',
          'app.region.custom.my-panel.collapsed',
          // Nothing outside those grammars is a v4 binding.
          'unknown.binding',
          'player.titleTwo',
          'setting.',
          'setting.1abc',
          'item.a.b.c.d.e.f',
          'app.region.sidebar.width',
          'app.region.1x.collapsed',
        };

        for (final name in corpus) {
          expect(
            schemaAccepts(name),
            isV4UiBinding(name),
            reason: '$name: schema and validator disagree',
          );
        }
      },
    );

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
