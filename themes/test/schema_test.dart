import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:spotube_themes/v3_validator.dart';
import 'package:test/test.dart';

/// The published schema, enforced.
///
/// Before this test existed the JSON Schema was documentation: the build
/// checked payloads with the Dart validator only, and the two had drifted
/// into shapes that could not both be right — the schema demanded a nested
/// `props` object, every theme wrote its props flat. A schema nobody runs is
/// a schema that is wrong without anyone noticing.
void main() {
  final repoRoot = Directory.current.path;

  late JsonSchema schema;
  setUpAll(() {
    final document =
        jsonDecode(
              File('$repoRoot/schemas/theme.v3.schema.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    schema = JsonSchema.create(document);
  });

  final payloads =
      Directory('$repoRoot/conformance')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  group('the schema', () {
    test('is draft 7, which the Dart validator can enforce', () {
      final document =
          jsonDecode(
                File(
                  '$repoRoot/schemas/theme.v3.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(document[r'$schema'], contains('draft-07'));
      expect(document.containsKey('definitions'), isTrue);
      expect(document.containsKey(r'$defs'), isFalse);
    });

    test('knows every node type the validator knows', () {
      final document =
          jsonDecode(
                File(
                  '$repoRoot/schemas/theme.v3.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
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
        uiNodeTypes.toSet(),
        reason: 'a node type the validator accepts is not in the schema',
      );
    });

    test('closes the slots the validator closes', () {
      final document =
          jsonDecode(
                File(
                  '$repoRoot/schemas/theme.v3.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final slots =
          (document['properties']
                  as Map<
                    String,
                    dynamic
                  >)['ui']['properties']['slots']['propertyNames']['enum']
              as List;
      expect(slots.toSet(), slotNames.toSet());
    });

    test('knows every action the validator dispatches', () {
      final document =
          jsonDecode(
                File(
                  '$repoRoot/schemas/theme.v3.schema.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final actions =
          (document['definitions']
                  as Map<
                    String,
                    dynamic
                  >)['uiAction']['properties']['type']['enum']
              as List;
      expect(
        actions.toSet(),
        uiActionTypes.toSet(),
        reason: 'an action the validator accepts is not in the schema',
      );
    });
  });

  group('every golden payload', () {
    test('there is one to check', () {
      expect(payloads, isNotEmpty);
    });

    for (final file in payloads) {
      final name = file.uri.pathSegments.last;
      test('$name validates against the published schema', () {
        final payload = jsonDecode(file.readAsStringSync());
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
    }
  });
}
