import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/v4_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// The palette v4 still requires; render points are the only thing under test.
Map<String, dynamic> _palette(String background, String foreground) {
  return {
    for (final role in colorRoles) role: background,
    'foreground': foreground,
    'cardForeground': foreground,
    'primaryForeground': background,
    'secondaryForeground': foreground,
    'mutedForeground': foreground,
    'accentForeground': foreground,
    'destructiveForeground': background,
  };
}

Map<String, dynamic> _payload({
  Map<String, dynamic>? templates,
  Object? renderPoints,
}) {
  return {
    'specVersion': 4,
    'light': _palette('#ffffff', '#121212'),
    'dark': _palette('#121212', '#ffffff'),
    'ui': {
      if (templates != null) 'templates': templates,
      if (renderPoints != null) 'renderPoints': renderPoints,
    },
  };
}

Map<String, dynamic> _text(String value) => {'type': 'text', 'text': value};

/// One chain of templates, each pointing at the next.
Map<String, dynamic> _chain(int length) {
  return {
    for (var i = 0; i < length; i++)
      't$i': {
        'children': [
          if (i == length - 1)
            _text('bottom')
          else
            {'type': 'template', 'name': 't${i + 1}'},
        ],
      },
  };
}

ValidationReport _validate({
  Map<String, dynamic>? templates,
  Object? renderPoints,
}) {
  return validateThemePayload(
    _payload(templates: templates, renderPoints: renderPoints),
  );
}

List<Issue> _at(ValidationReport report, String path) => [
  for (final issue in report.issues)
    if (issue.path == path) issue,
];

void main() {
  group('ui.renderPoints', () {
    test('the catalogue matches the published schema', () {
      final schema =
          jsonDecode(File('schemas/theme.v4.schema.json').readAsStringSync())
              as Map<String, dynamic>;
      final enumValues =
          (schema['properties']
                  as Map)['ui']['properties']['renderPoints']['propertyNames']['enum']
              as List;

      expect(v4RenderPoints, hasLength(19));
      expect(enumValues.toSet(), v4RenderPoints.toSet());
    });

    test('a mapped, well-formed template is clean', () {
      final report = _validate(
        templates: {
          'row': {
            'children': [_text('row')],
          },
        },
        renderPoints: const {'search.suggestion.item': 'row'},
      );

      expect(report.issues, isEmpty);
    });

    test('an unknown render point is a warning, not a rejection', () {
      final report = _validate(
        templates: {
          'row': {
            'children': [_text('row')],
          },
        },
        renderPoints: const {'search.magic': 'row'},
      );

      final issues = _at(report, 'ui.renderPoints.search.magic');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.warning);
      expect(issues.single.message, contains('ignored at runtime'));
      expect(report.hasErrors, isFalse);
    });

    test('a missing template warns because the host keeps its default', () {
      final report = _validate(renderPoints: const {'search.field': 'gone'});

      final issues = _at(report, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.warning);
      expect(issues.single.message, contains('gone'));
      expect(report.hasErrors, isFalse);
    });

    test('hostWidget inside a render-point template is an error', () {
      final report = _validate(
        templates: {
          'chrome': {
            'children': [
              {'type': 'hostWidget', 'id': 'search.field'},
            ],
          },
        },
        renderPoints: const {'search.field': 'chrome'},
      );

      final issues = _at(report, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('hostWidget'));
    });

    test('a self-referencing template is an error', () {
      final report = _validate(
        templates: {
          'loop': {
            'children': [
              {'type': 'template', 'name': 'loop'},
            ],
          },
        },
        renderPoints: const {'search.field': 'loop'},
      );

      final issues = _at(report, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('refers to itself'));
    });

    test('a mutual reference is an error', () {
      final report = _validate(
        templates: {
          'a': {
            'children': [
              {'type': 'template', 'name': 'b'},
            ],
          },
          'b': {
            'children': [
              {'type': 'template', 'name': 'a'},
            ],
          },
        },
        renderPoints: const {'search.field': 'a'},
      );

      final issues = _at(report, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('refers to itself'));
    });

    test('eight nested templates pass and nine fail', () {
      final eight = _validate(
        templates: _chain(8),
        renderPoints: const {'search.field': 't0'},
      );
      final nine = _validate(
        templates: _chain(9),
        renderPoints: const {'search.field': 't0'},
      );

      expect(eight.issues, isEmpty);
      final issues = _at(nine, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('deeper than 8'));
    });

    test('a template reference through props is followed', () {
      final report = _validate(
        templates: {
          'outer': {
            'children': [
              {
                'type': 'template',
                'props': {'name': 'gone'},
              },
            ],
          },
        },
        renderPoints: const {'search.field': 'outer'},
      );

      final issues = _at(report, 'ui.renderPoints.search.field');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('gone'));
    });

    test('an empty or non-string template name is an error', () {
      final empty = _validate(renderPoints: const {'search.field': '  '});
      final number = _validate(renderPoints: const {'search.field': 7});

      for (final report in [empty, number]) {
        final issues = _at(report, 'ui.renderPoints.search.field');
        expect(issues, hasLength(1));
        expect(issues.single.severity, Severity.error);
        expect(issues.single.message, contains('must name a template'));
      }
    });

    test('renderPoints must be an object', () {
      final report = _validate(renderPoints: const ['search.field']);

      final issues = _at(report, 'ui.renderPoints');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(issues.single.message, contains('must be an object'));
    });

    test('an unknown ui key is still rejected', () {
      final report = _validate(
        renderPoints: const {'search.field': 'row'},
        templates: {
          'row': {
            'children': [_text('row')],
          },
        },
      );
      final payload = _payload(
        templates: {
          'row': {
            'children': [_text('row')],
          },
        },
        renderPoints: const {'search.field': 'row'},
      );
      (payload['ui'] as Map)['renderPoint'] = const {};

      final issues = _at(validateThemePayload(payload), 'ui.renderPoint');
      expect(issues, hasLength(1));
      expect(issues.single.severity, Severity.error);
      expect(report.hasErrors, isFalse);
    });
  });
}
