import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

Map<String, dynamic> _palette(String background, String foreground) {
  final palette = <String, dynamic>{
    for (final role in colorRoles) role: background,
  };
  palette.addAll({
    'foreground': foreground,
    'cardForeground': foreground,
    'primaryForeground': background,
    'secondaryForeground': foreground,
    'mutedForeground': foreground,
    'accentForeground': foreground,
    'destructiveForeground': background,
  });
  return palette;
}

Map<String, dynamic> _payload({
  Map<String, dynamic>? layout,
  List<Map<String, dynamic>>? children,
}) {
  return {
    'specVersion': 4,
    'light': _palette('#ffffff', '#121212'),
    'dark': _palette('#121212', '#ffffff'),
    if (layout != null) 'layout': layout,
    'ui': {
      'slots': {
        'sidebar.content': {
          'children':
              children ??
              [
                {'type': 'text', 'text': 'ok'},
              ],
        },
      },
    },
  };
}

List<String> _errors(ValidationReport report) => [
  for (final issue in report.issues)
    if (issue.severity == Severity.error) issue.path,
];

List<String> _warnings(ValidationReport report) => [
  for (final issue in report.issues)
    if (issue.severity == Severity.warning) issue.path,
];

void main() {
  test('the layout-regions fixture validates cleanly', () {
    final payload =
        jsonDecode(
              File(
                'conformance/draft/v4-layout-regions.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final report = validateThemePayload(payload);

    expect(
      report.issues,
      isEmpty,
      reason: report.issues.map((issue) => issue.toString()).join('\n'),
    );
  });

  group('layout keys', () {
    test('accepts the four region keys and their values', () {
      final report = validateThemePayload(
        _payload(
          layout: {
            'sidebar': 'theme',
            'sidebarWidth': 240,
            'aside': 'theme',
            'asideWidth': 340,
            'responsive': {
              'compact': {
                'sidebar': 'host',
                'aside': 'none',
                'asideWidth': 260,
              },
            },
          },
        ),
      );

      expect(_errors(report), isEmpty);
      expect(_warnings(report), isEmpty);
    });

    test('rejects unknown region names and out-of-range widths', () {
      final report = validateThemePayload(
        _payload(
          layout: {
            'sidebar': 'left',
            'aside': 'right',
            'sidebarWidth': 5000,
            'asideWidth': -1,
            'responsive': {
              'compact': {'sidebar': 'both', 'asideWidth': 1001},
            },
          },
        ),
      );

      expect(_errors(report), contains('layout.sidebar'));
      expect(_errors(report), contains('layout.aside'));
      expect(_errors(report), contains('layout.sidebarWidth'));
      expect(_errors(report), contains('layout.asideWidth'));
      expect(_errors(report), contains('layout.responsive.compact.sidebar'));
      expect(_errors(report), contains('layout.responsive.compact.asideWidth'));
    });
  });

  group('resizable', () {
    ValidationReport resize(Map<String, dynamic> props, {int panes = 2}) {
      return validateThemePayload(
        _payload(
          children: [
            {
              'type': 'resizable',
              ...props,
              'children': [
                for (var i = 0; i < panes; i++) {'type': 'text', 'text': '$i'},
              ],
            },
          ],
        ),
      );
    }

    test('accepts an axis, a range and a storage key', () {
      final report = resize({
        'direction': 'vertical',
        'initial': 240,
        'min': 120,
        'max': 480,
        'storageKey': 'shelf.one',
      });

      expect(_errors(report), isEmpty);
      expect(_warnings(report), isEmpty);
    });

    test('rejects an unknown axis', () {
      expect(
        _errors(resize({'direction': 'diagonal'})),
        contains(endsWith('.direction')),
      );
    });

    test('warns when it does not get exactly two panes', () {
      expect(
        _warnings(resize(const {}, panes: 3)),
        contains(endsWith('.children')),
      );
      expect(
        _warnings(resize(const {}, panes: 1)),
        contains(endsWith('.children')),
      );
    });

    test('rejects an inverted range and an initial outside it', () {
      expect(
        _errors(resize({'min': 400, 'max': 200})),
        contains(endsWith('.min')),
      );
      expect(
        _errors(resize({'initial': 100, 'min': 120, 'max': 480})),
        contains(endsWith('.initial')),
      );
      expect(
        _errors(resize({'initial': 500, 'min': 120, 'max': 480})),
        contains(endsWith('.initial')),
      );
    });

    test('warns on sizes the host would clamp', () {
      final report = resize({'initial': 5000, 'min': -1, 'max': 9000});

      expect(_warnings(report), contains(endsWith('.initial')));
      expect(_warnings(report), contains(endsWith('.min')));
      expect(_warnings(report), contains(endsWith('.max')));
    });

    test('rejects a storage key the host cannot namespace', () {
      for (final key in ['Shelf', '9shelf', 'a' * 65, 'sp ace']) {
        expect(
          _errors(resize({'storageKey': key})),
          contains(endsWith('.storageKey')),
          reason: key,
        );
      }
    });
  });
}
