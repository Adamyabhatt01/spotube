// `ui.menus` and theme-owned `contextMenu` contracts: a theme may append
// namespaced rows to every published target, the validator rejects anything
// the host cannot dispatch, and the schema carries the same target set.
import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:spotube_themes/validator.dart';
import 'package:spotube_themes/v4_validator.dart';
import 'package:test/test.dart';

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
  Object? menus,
  List<String> capabilities = const [],
  Map<String, dynamic> uiExtra = const {},
}) {
  return {
    'specVersion': 4,
    'light': _palette('#ffffff', '#121212'),
    'dark': _palette('#121212', '#ffffff'),
    if (capabilities.isNotEmpty) 'capabilities': capabilities,
    'ui': {
      'specVersion': 2,
      if (menus != null) 'menus': menus,
      ...uiExtra,
    },
  };
}

Map<String, dynamic> _row({
  String id = 'theme.row',
  String label = 'Theme row',
  String type = 'toast',
  String? capability,
  String? when,
  bool? destructive,
  Map<String, dynamic>? action,
}) {
  return {
    'id': id,
    'label': label,
    'action': action ?? {'type': type},
    if (capability != null) 'capability': capability,
    if (when != null) 'when': when,
    if (destructive != null) 'destructive': destructive,
  };
}

List<String> _errorPaths(Map<String, dynamic> payload) => [
      for (final issue in validateThemePayload(payload).issues)
        if (issue.severity == Severity.error) issue.path,
    ];

void main() {
  group('ui.menus', () {
    test('accepts a theme row on every published target', () {
      final report = validateThemePayload(
        _payload(
          menus: {
            for (final target in v4ContextMenuTargets)
              target: [_row(id: 'theme.$target')],
          },
        ),
      );

      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('rejects an unknown target', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [_row()],
          'not-a-target': [_row(id: 'theme.other')],
        }),
      );

      expect(errors, contains('ui.menus.not-a-target'));
    });

    test('rejects non-theme and empty ids', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [
            _row(id: 'host.play'),
            _row(id: 'theme.'),
          ],
        }),
      );

      expect(errors, contains('ui.menus.playlist[0].id'));
      expect(errors, contains('ui.menus.playlist[1].id'));
    });

    test('rejects duplicate ids inside one target', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [
            _row(id: 'theme.same'),
            _row(id: 'theme.same'),
          ],
        }),
      );

      expect(errors, contains('ui.menus.playlist[1].id'));
    });

    test('rejects malformed labels, icons, whens and flags', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [
            _row(label: ''),
            _row(id: 'theme.icon')..['icon'] = 'x' * 33,
            _row(id: 'theme.when', when: 'x' * 161),
            _row(id: 'theme.destructive', destructive: null)
              ..['destructive'] = 'yes',
          ],
        }),
      );

      expect(errors, contains('ui.menus.playlist[0].label'));
      expect(errors, contains('ui.menus.playlist[1].icon'));
      expect(errors, contains('ui.menus.playlist[2].when'));
      expect(errors, contains('ui.menus.playlist[3].destructive'));
    });

    test('rejects unknown keys, actions and verbs', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [
            _row()..['nope'] = true,
            _row(id: 'theme.no-action')..['action'] = 'toast',
            _row(id: 'theme.bad-verb', type: 'notAVerb'),
          ],
        }),
      );

      expect(errors, contains('ui.menus.playlist[0].nope'));
      expect(errors, contains('ui.menus.playlist[1].action'));
      expect(errors, contains('ui.menus.playlist[2].action.type'));
    });

    test('an action verb that mutates the library needs its capability', () {
      final denied = _errorPaths(
        _payload(menus: {
          'playlist': [_row(type: 'deletePlaylist')],
        }),
      );
      expect(denied, contains('ui.menus.playlist[0].action.type'));

      final granted = validateThemePayload(
        _payload(
          menus: {
            'playlist': [_row(type: 'deletePlaylist')],
          },
          capabilities: const ['library.write'],
        ),
      );
      expect(granted.hasErrors, isFalse, reason: granted.issues.join('\n'));
    });

    test('a declared capability must exist and be granted', () {
      final unknown = _errorPaths(
        _payload(menus: {
          'playlist': [_row(capability: 'not.a.capability')],
        }),
      );
      expect(unknown, contains('ui.menus.playlist[0].capability'));

      final denied = _errorPaths(
        _payload(menus: {
          'playlist': [_row(capability: 'library.write')],
        }),
      );
      expect(denied, contains('ui.menus.playlist[0].capability'));

      final granted = validateThemePayload(
        _payload(
          menus: {
            'playlist': [_row(capability: 'library.write')],
          },
          capabilities: const ['library.write'],
        ),
      );
      expect(granted.hasErrors, isFalse, reason: granted.issues.join('\n'));
    });

    test('rejects more than 32 rows', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': [
            for (var i = 0; i < 33; i++)
              _row(id: 'theme.row$i', label: 'Row $i'),
          ],
        }),
      );

      expect(errors, contains('ui.menus.playlist'));
    });

    test('rejects a non-list target and a non-object row', () {
      final errors = _errorPaths(
        _payload(menus: {
          'playlist': 'nope',
          'track': ['nope'],
        }),
      );

      expect(errors, contains('ui.menus.playlist'));
      expect(errors, contains('ui.menus.track[0]'));
    });
  });

  group('theme-owned contextMenu', () {
    test('a target prop opts the node into host user configuration', () {
      final report = validateThemePayload(
        _payload(
          uiExtra: {
            'slots': {
              'home.content': {
                'children': [
                  {
                    'type': 'contextMenu',
                    'target': 'playlist',
                    'items': [
                      {
                        'id': 'theme.row',
                        'label': 'Theme row',
                        'action': {
                          'type': 'toast',
                          'args': {'message': 'hi'},
                        },
                      },
                    ],
                  },
                ],
              },
            },
          },
        ),
      );

      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('the schema accepts the same node and the radio target', () {
      final document = jsonDecode(
        File('schemas/theme.v4.schema.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final schema = JsonSchema.create(document);

      final results = schema.validate(
        _payload(
          menus: {
            'radio': [_row(id: 'theme.radio')],
          },
          uiExtra: {
            'slots': {
              'home.content': {
                'children': [
                  {
                    'type': 'contextMenu',
                    'target': 'playlist',
                    'items': [
                      {
                        'id': 'theme.row',
                        'label': 'Theme row',
                        'action': {
                          'type': 'toast',
                          'args': {'message': 'hi'},
                        },
                      },
                    ],
                  },
                ],
              },
            },
          },
        ),
      );

      expect(
        results.errors,
        isEmpty,
        reason: results.errors
            .map((error) => '${error.instancePath}: ${error.message}')
            .join('\n'),
      );
    });
  });
}
