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

  group('shell layout', () {
    Map<String, dynamic> shellPayload(
      Map<String, dynamic> shell, {
      Map<String, dynamic> layout = const {},
      List<Map<String, dynamic>>? pins,
    }) {
      return _payload(
        layout: {
          'shell': shell,
          if (pins != null) 'pinTargets': pins,
          ...layout,
        },
      );
    }

    test('the shell fixture validates cleanly', () {
      final payload =
          jsonDecode(
                File(
                  'conformance/draft/v4-shell-layout.json',
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

    test('accepts a tree, custom slots and pin targets', () {
      final payload = shellPayload(
        {
          'type': 'row',
          'children': [
            {'region': 'sidebar', 'width': 240, 'slot': 'sidebar.content'},
            {
              'type': 'column',
              'flex': 1,
              'children': [
                {'region': 'content', 'flex': 1},
                {'region': 'player', 'height': 88},
                {
                  'region': 'custom',
                  'id': 'bar.bottom',
                  'slot': 'bar.bottom',
                  'label': 'Bottom bar',
                  'height': '12.5%',
                  'collapsible': true,
                  'resizable': {
                    'edges': ['top'],
                    'storageKey': 'bar.bottom.size',
                    'min': 48,
                    'max': 120,
                  },
                },
              ],
            },
          ],
        },
        layout: {
          'responsive': {
            'compact': {
              'shell': {
                'type': 'column',
                'children': [
                  {'region': 'content', 'flex': 1},
                ],
              },
            },
          },
        },
        pins: [
          {'id': 'sidebar', 'label': 'Sidebar'},
          {'id': 'bar.bottom', 'label': 'Bottom bar'},
        ],
      );
      (payload['ui'] as Map)['slots']['bar.bottom'] = {
        'children': [
          {'type': 'text', 'text': 'Pinned'},
        ],
      };

      final report = validateThemePayload(payload);

      expect(_errors(report), isEmpty);
      expect(_warnings(report), isEmpty);
    });

    test('rejects a shell without exactly one content', () {
      final missing = validateThemePayload(
        shellPayload({
          'type': 'row',
          'children': [
            {'region': 'sidebar'},
          ],
        }),
      );
      expect(_errors(missing), contains('layout.shell'));

      final duplicated = validateThemePayload(
        shellPayload({
          'type': 'row',
          'children': [
            {'region': 'content'},
            {'region': 'content'},
          ],
        }),
      );
      expect(_errors(duplicated), contains('layout.shell.children[1]'));
    });

    test('rejects duplicate regions and ids', () {
      final report = validateThemePayload(
        shellPayload({
          'type': 'row',
          'children': [
            {'region': 'content'},
            {'region': 'sidebar'},
            {'region': 'sidebar'},
            {
              'region': 'custom',
              'id': 'bar.one',
              'slot': 'bar.one',
              'label': 'One',
            },
            {
              'region': 'custom',
              'id': 'bar.one',
              'slot': 'bar.two',
              'label': 'Two',
            },
          ],
        }),
      );

      expect(_errors(report), contains('layout.shell.children[2]'));
      expect(_errors(report), contains('layout.shell.children[4].id'));
    });

    test('rejects malformed nodes, sizes and custom leaves', () {
      final report = validateThemePayload(
        shellPayload({
          'type': 'column',
          'children': [
            {'region': 'content', 'width': '101%', 'flex': 1.5},
            {'region': 'custom', 'label': 'No id or slot'},
            {'region': 'nowhere'},
            {'type': 'grid'},
            {'type': 'row', 'children': 'nope'},
          ],
        }),
      );

      final errors = _errors(report);
      expect(errors, contains('layout.shell.children[0].width'));
      expect(errors, contains('layout.shell.children[0].flex'));
      expect(errors, contains('layout.shell.children[1].id'));
      expect(errors, contains('layout.shell.children[1].slot'));
      expect(errors, contains('layout.shell.children[2].region'));
      expect(errors, contains('layout.shell.children[3].children'));
      expect(errors, contains('layout.shell.children[4].children'));
    });

    test('warns when two regions share a slot', () {
      final report = validateThemePayload(
        shellPayload({
          'type': 'row',
          'children': [
            {'region': 'content'},
            {
              'region': 'custom',
              'id': 'bar.one',
              'slot': 'bar.mirror',
              'label': 'One',
            },
            {
              'region': 'custom',
              'id': 'bar.two',
              'slot': 'bar.mirror',
              'label': 'Two',
            },
          ],
        }),
      );

      expect(_errors(report), isEmpty);
      expect(_warnings(report), contains('layout.shell.children[2].slot'));
    });

    test('reserves unknown custom slots for shell-declared names', () {
      final payload = _payload();
      (payload['ui'] as Map)['slots']['bar.bottom'] = {
        'children': [
          {'type': 'text', 'text': 'Pinned'},
        ],
      };

      expect(
        _errors(validateThemePayload(payload)),
        contains('ui.slots.bar.bottom'),
      );

      final declared = shellPayload({
        'type': 'row',
        'children': [
          {'region': 'content'},
          {
            'region': 'custom',
            'id': 'bar.bottom',
            'slot': 'bar.bottom',
            'label': 'Bottom bar',
          },
        ],
      });
      (declared['ui'] as Map)['slots']['bar.bottom'] = {
        'children': [
          {'type': 'text', 'text': 'Pinned'},
        ],
      };

      final report = validateThemePayload(declared);
      expect(_errors(report), isEmpty);
      expect(_warnings(report), isEmpty);
    });

    test('validates pin target ids and labels', () {
      final report = validateThemePayload(
        shellPayload(
          {
            'type': 'row',
            'children': [
              {'region': 'content'},
            ],
          },
          pins: [
            {'id': 'sidebar', 'label': 'Sidebar'},
            {'id': 'sidebar'},
            {'id': ''},
            {'id': 'bar.bottom', 'label': 3},
            {'id': 'bar.bottom', 'label': 'ok', 'unknown': true},
          ],
        ),
      );

      final errors = _errors(report);
      expect(errors, contains('layout.pinTargets[1].id'));
      expect(errors, contains('layout.pinTargets[2].id'));
      expect(errors, contains('layout.pinTargets[3].label'));
      expect(errors, contains('layout.pinTargets[4].unknown'));
    });
  });
}
