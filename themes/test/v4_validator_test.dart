import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/v3_validator.dart';
import 'package:spotube_themes/v4_validator.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// A complete, minimal v4 payload to mutate in each test.
Map<String, dynamic> validPayload() {
  const roles = <String>[
    'background',
    'foreground',
    'card',
    'cardForeground',
    'primary',
    'primaryForeground',
    'secondary',
    'secondaryForeground',
    'muted',
    'mutedForeground',
    'accent',
    'accentForeground',
    'destructive',
    'destructiveForeground',
    'border',
    'input',
    'ring',
  ];
  Map<String, dynamic> palette(String background, String foreground) => {
    for (final role in roles) role: background,
    'foreground': foreground,
    'cardForeground': foreground,
    'primaryForeground': background,
    'secondaryForeground': foreground,
    'mutedForeground': foreground,
    'accentForeground': foreground,
    'destructiveForeground': background,
  };

  return {
    'specVersion': 4,
    'light': palette('#ffffff', '#121212'),
    'dark': palette('#121212', '#ffffff'),
  };
}

List<String> pathsOf(ValidationReport report, Severity severity) => [
  for (final issue in report.issues)
    if (issue.severity == severity) issue.path,
];

Map<String, dynamic> withUi(
  List<Map<String, dynamic>> children, {
  Map<String, dynamic> extra = const {},
  List<String> slot = const ['home.content'],
}) {
  final payload = validPayload();
  payload['ui'] = {
    'specVersion': 2,
    'slots': {
      for (final name in slot) name: {'children': children},
    },
  };
  payload.addAll(extra);
  return payload;
}

void main() {
  group('the specVersion gate', () {
    test('a minimal v4 payload is clean', () {
      final report = validateThemePayload(validPayload());
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
      expect(report.resolved, isNotNull);
    });

    test('v3 is rejected before parsing, with the migration message', () {
      final payload = validPayload()..['specVersion'] = 3;
      final report = validateThemePayload(payload);

      expect(report.hasErrors, isTrue);
      expect(report.resolved, isNull);
      expect(report.issues, hasLength(1));
      expect(report.issues.single.severity, Severity.error);
      expect(report.issues.single.path, 'specVersion');
      expect(
        report.issues.single.message,
        'specVersion 3 is not supported; migrate to 4',
      );
    });

    test('the legacy path still reads v3 for the migration tools', () {
      final payload = jsonDecode(
        File('conformance/draft/v3-kitchen-sink.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final report = validateLegacyThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('v2 is still read', () {
      final payload = validPayload()..remove('specVersion');
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.resolved, isNotNull);
    });

    test('any other version is an error and resolves to nothing', () {
      for (final version in <Object>[1, 5, 'four']) {
        final payload = validPayload()..['specVersion'] = version;
        final report = validateThemePayload(payload);
        expect(report.hasErrors, isTrue, reason: 'version $version');
        expect(report.resolved, isNull);
        expect(pathsOf(report, Severity.error), contains('specVersion'));
      }
    });
  });

  group('the top level is closed', () {
    test('an unknown v4 key is an error', () {
      final payload = validPayload()..['somethingNew'] = {'a': 1};
      final report = validateThemePayload(payload);
      expect(pathsOf(report, Severity.error), contains('somethingNew'));
      expect(
        report.issues
            .firstWhere((issue) => issue.path == 'somethingNew')
            .message,
        contains('not a v4 top-level key'),
      );
    });

    test('the retired dynamic block is not a v4 key', () {
      final payload = validPayload()
        ..['dynamic'] = {'source': 'albumArt'};
      expect(
        pathsOf(validateThemePayload(payload), Severity.error),
        contains('dynamic'),
      );
    });

    test('an unknown v2 key stays a warning', () {
      final payload = validPayload()
        ..remove('specVersion')
        ..['somethingNew'] = 1;
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), contains('somethingNew'));
    });
  });

  group('block sweeps', () {
    void expectSwept(String block, Map<String, dynamic> value) {
      final payload = validPayload()..[block] = value;
      final report = validateThemePayload(payload);
      expect(
        pathsOf(report, Severity.error),
        contains('$block.bogus'),
        reason: '$block did not reject an unknown key:\n${report.issues}',
      );
    }

    test('typography, spacing, motion, scale, icons and branding', () {
      for (final block in [
        'typography',
        'spacing',
        'motion',
        'scale',
        'icons',
        'branding',
      ]) {
        expectSwept(block, {'bogus': 1});
      }
    });

    test('layout and its nested blocks', () {
      expectSwept('layout', {'bogus': 1});

      for (final block in ['player', 'home', 'settings', 'titlebar', 'splash']) {
        final payload = validPayload()
          ..['layout'] = {
            block: {'bogus': 1},
          };
        expect(
          pathsOf(validateThemePayload(payload), Severity.error),
          contains('layout.$block.bogus'),
        );
      }
    });

    test('responsive variants and player', () {
      final payload = validPayload()
        ..['layout'] = {
          'responsive': {
            'compact': {
              'bogus': 1,
              'player': {'bogus': 1},
            },
          },
        };
      final errors = pathsOf(validateThemePayload(payload), Severity.error);
      expect(errors, contains('layout.responsive.compact.bogus'));
      expect(errors, contains('layout.responsive.compact.player.bogus'));
    });

    test('components, kit overrides and their styles', () {
      final payload = validPayload()
        ..['components'] = {
          'bogus': {'radius': 4},
          'shadcn': {
            'bogus': {'radius': 4},
            'slider': {'bogus': 4},
          },
        };
      final errors = pathsOf(validateThemePayload(payload), Severity.error);
      expect(errors, contains('components.bogus'));
      expect(errors, contains('components.shadcn.bogus'));
      expect(errors, contains('components.shadcn.slider.bogus'));
    });

    test('assets and their entries', () {
      final payload = validPayload()
        ..['assets'] = {
          'images': [
            {
              'path': 'asset://images/logo.png',
              'kind': 'image',
              'bogus': 1,
            },
          ],
        };
      expect(
        pathsOf(validateThemePayload(payload), Severity.error),
        contains('assets.images[0].bogus'),
      );
    });

    test('ui, slots, screens and templates', () {
      final payload = validPayload()
        ..['ui'] = {
          'specVersion': 2,
          'bogus': 1,
          'slots': {
            'home.content': {'bogus': 1},
          },
          'screens': {
            'player': {'bogus': 1},
          },
          'templates': {
            'card': {'bogus': 1},
          },
        };
      final errors = pathsOf(validateThemePayload(payload), Severity.error);
      expect(errors, contains('ui.bogus'));
      expect(errors, contains('ui.slots.home.content.bogus'));
      expect(errors, contains('ui.screens.player.bogus'));
      expect(errors, contains('ui.templates.card.bogus'));
    });
  });

  group('capabilities', () {
    test('the default set is library.read and player.control', () {
      expect(
        v4GrantedCapabilities(validPayload()),
        containsAll(['library.read', 'player.control', 'theme.assets']),
      );
      expect(
        v4GrantedCapabilities(validPayload()),
        isNot(contains('library.write')),
      );
    });

    test('an unknown capability is an error', () {
      final payload = validPayload()..['capabilities'] = ['root'];
      expect(
        pathsOf(validateThemePayload(payload), Severity.error),
        contains('capabilities[0]'),
      );
    });

    test('a duplicate capability is a warning', () {
      final payload = validPayload()
        ..['capabilities'] = ['library.write', 'library.write'];
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), contains('capabilities[1]'));
    });

    test('pages require ui.pages', () {
      final payload = validPayload()
        ..['pages'] = [
          {'id': 'audio'},
        ];
      final report = validateThemePayload(payload);
      expect(pathsOf(report, Severity.error), contains('pages'));

      payload['capabilities'] = ['ui.pages'];
      expect(validateThemePayload(payload).hasErrors, isFalse);
    });

    test('hostWidget requires ui.hostWidgets', () {
      final node = {'type': 'hostWidget', 'id': 'library.playlists'};
      final report = validateThemePayload(withUi([node]));
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0]'),
      );

      final granted = withUi([node], extra: {
        'capabilities': ['ui.hostWidgets'],
      });
      expect(
        validateThemePayload(granted).hasErrors,
        isFalse,
        reason: validateThemePayload(granted).issues.join('\n'),
      );
    });

    test('audio bindings require audio.effects', () {
      final node = {'type': 'text', 'bind': 'audio.bass'};
      final report = validateThemePayload(withUi([node]));
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0].bind'),
      );

      final granted = withUi([node], extra: {
        'capabilities': ['audio.effects'],
      });
      expect(validateThemePayload(granted).hasErrors, isFalse);
    });

    test('library and item bindings require library.read', () {
      final node = {'type': 'text', 'bind': 'library.playlists'};
      final report = validateThemePayload(
        withUi(
          [node],
          extra: {
            'capabilities': ['player.control'],
          },
        ),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0].bind'),
      );

      final granted = withUi(
        [node],
        extra: {
          'capabilities': ['library.read'],
        },
      );
      expect(validateThemePayload(granted).hasErrors, isFalse);
    });

    test('player actions require player.control', () {
      final node = {
        'type': 'button',
        'label': 'Play',
        'action': {'type': 'playPause'},
      };
      final report = validateThemePayload(
        withUi(
          [node],
          extra: {
            'capabilities': ['library.read'],
          },
        ),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0].action.type'),
      );

      final granted = withUi(
        [node],
        extra: {
          'capabilities': ['player.control'],
        },
      );
      expect(validateThemePayload(granted).hasErrors, isFalse);
    });

    test('actions carry their capability', () {
      Map<String, dynamic> button(String verb) => {
        'type': 'button',
        'label': 'Run',
        'action': {'type': verb},
      };

      const cases = {
        'setBass': 'audio.effects',
        'pinItem': 'library.write',
        'setSetting': 'settings.write',
        'copy': 'clipboard.write',
        'openPage': 'ui.pages',
      };

      for (final entry in cases.entries) {
        final report = validateThemePayload(withUi([button(entry.key)]));
        expect(
          pathsOf(report, Severity.error),
          contains('ui.slots.home.content[0].action.type'),
          reason: '${entry.key} did not require ${entry.value}',
        );

        final granted = withUi(
          [button(entry.key)],
          extra: {
            'capabilities': [entry.value],
          },
        );
        expect(
          validateThemePayload(granted).hasErrors,
          isFalse,
          reason: validateThemePayload(granted).issues.join('\n'),
        );
      }
    });
  });

  group('the v4 layout', () {
    test('sidebar, aside and widths are accepted', () {
      final payload = validPayload()
        ..['layout'] = {
          'sidebar': 'theme',
          'sidebarWidth': 280,
          'aside': 'theme',
          'asideWidth': 320,
        };
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('sidebar and aside are closed enums', () {
      final payload = validPayload()
        ..['layout'] = {'sidebar': 'auto', 'aside': 'left'};
      final errors = pathsOf(validateThemePayload(payload), Severity.error);
      expect(errors, contains('layout.sidebar'));
      expect(errors, contains('layout.aside'));
    });

    test('widths are numbers in range', () {
      final payload = validPayload()
        ..['layout'] = {'sidebarWidth': -1, 'asideWidth': 'wide'};
      final errors = pathsOf(validateThemePayload(payload), Severity.error);
      expect(errors, contains('layout.sidebarWidth'));
      expect(errors, contains('layout.asideWidth'));
    });

    test('the dock is full, compact or stage', () {
      for (final dock in ['full', 'compact', 'stage']) {
        final payload = validPayload()
          ..['layout'] = {
            'player': {'dock': dock},
          };
        expect(validateThemePayload(payload).hasErrors, isFalse);
      }

      final floating = validPayload()
        ..['layout'] = {
          'player': {'dock': 'floating'},
        };
      expect(
        pathsOf(validateThemePayload(floating), Severity.error),
        contains('layout.player.dock'),
      );
    });

    test('responsive breakpoints are compact, medium and expanded', () {
      for (final breakpoint in ['compact', 'medium', 'expanded']) {
        final payload = validPayload()
          ..['layout'] = {
            'responsive': {
              breakpoint: {
                'sidebar': 'theme',
                'aside': 'none',
                'sidebarWidth': 240,
                'asideWidth': 280,
              },
            },
          };
        final report = validateThemePayload(payload);
        expect(
          report.hasErrors,
          isFalse,
          reason: '$breakpoint: ${report.issues.join('\n')}',
        );
      }

      final alias = validPayload()
        ..['layout'] = {
          'responsive': {'xs': {}},
        };
      expect(
        pathsOf(validateThemePayload(alias), Severity.error),
        contains('layout.responsive.xs'),
      );
    });

    test('page visibility is validated per breakpoint', () {
      final good = validPayload()
        ..['layout'] = {
          'responsive': {
            'compact': {
              'pages': {
                'audio': {'visible': false},
              },
            },
          },
        };
      expect(validateThemePayload(good).hasErrors, isFalse);

      final bad = validPayload()
        ..['layout'] = {
          'responsive': {
            'compact': {
              'pages': {
                'audio': {'hidden': true},
              },
            },
          },
        };
      final errors = pathsOf(validateThemePayload(bad), Severity.error);
      expect(
        errors,
        contains('layout.responsive.compact.pages.audio.hidden'),
      );
    });
  });

  group('theme pages', () {
    Map<String, dynamic> withPages(List<Map<String, dynamic>> pages) =>
        validPayload()
          ..['capabilities'] = ['ui.pages']
          ..['pages'] = pages;

    test('a complete page is accepted', () {
      final report = validateThemePayload(
        withPages([
          {
            'id': 'audio',
            'title': 'Audio',
            'icon': 'equalizer',
            'parent': 'library.local',
            'showBack': true,
            'visible': true,
          },
        ]),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('id, title and keys are checked', () {
      final report = validateThemePayload(
        withPages([
          {'title': 'No id', 'bogus': 1},
        ]),
      );
      final errors = pathsOf(report, Severity.error);
      expect(errors, contains('pages[0].id'));
      expect(errors, contains('pages[0].bogus'));
    });

    test('ids are unique', () {
      final report = validateThemePayload(
        withPages([
          {'id': 'audio'},
          {'id': 'audio'},
        ]),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('pages[1].id'),
      );
    });

    test('ui.pages is validated too', () {
      final payload = validPayload()
        ..['ui'] = {
          'specVersion': 2,
          'pages': [
            {'id': 'audio'},
          ],
        };
      expect(
        pathsOf(validateThemePayload(payload), Severity.error),
        contains('ui.pages'),
      );
    });
  });

  group('the v4 UI vocabulary', () {
    test('every new node type is accepted on its own', () {
      for (final type in v4NewUiNodeTypes) {
        final issues = validateUiSpec(
          {
            'specVersion': 2,
            'slots': {
              'home.content': {
                'children': [
                  {'type': type},
                ],
              },
            },
          },
          vocabulary: v4UiVocabulary,
        );
        expect(
          issues,
          isEmpty,
          reason: '$type was rejected: ${issues.join('\n')}',
        );
      }
    });

    test('an unknown prop on a new node is a typo', () {
      final report = validateThemePayload(
        withUi([
          {'type': 'box', 'schmorder': 1},
        ]),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0].schmorder'),
      );
    });

    test('the common envelope works on a v3 node', () {
      final report = validateThemePayload(
        withUi([
          {
            'type': 'text',
            'text': 'Hello',
            'hiddenWhen': '!player.playing',
            'disabledWhen': 'player.muted',
            'kit': 'material',
            'animate': 200,
            'variant': 'spotify',
          },
        ]),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('a condition naming an unknown binding is an error', () {
      final report = validateThemePayload(
        withUi([
          {'type': 'text', 'text': 'Hello', 'hiddenWhen': 'player.mood'},
        ]),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.home.content[0].hiddenWhen'),
      );
    });

    test('hostWidget.props is a prop bag, not the legacy envelope', () {
      final report = validateThemePayload(
        withUi(
          [
            {
              'type': 'hostWidget',
              'id': 'library.playlists',
              'props': {'compact': true, 'limit': 20},
            },
          ],
          extra: {
            'capabilities': ['ui.hostWidgets'],
          },
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('ui.specVersion stays at 2 — v4 does not bump it', () {
      final payload = withUi([
        {'type': 'text', 'text': 'Hello'},
      ]);
      (payload['ui'] as Map)['specVersion'] = 3;
      expect(
        pathsOf(validateThemePayload(payload), Severity.error),
        contains('ui.specVersion'),
      );
    });

    test('the new v4 slots are published and unknown slots are not', () {
      for (final slot in v4SlotNames) {
        final issues = validateUiSpec(
          {
            'specVersion': 2,
            'slots': {
              slot: {'children': []},
            },
          },
          vocabulary: v4UiVocabulary,
        );
        expect(issues, isEmpty, reason: '$slot was rejected');
      }

      final unknown = validateUiSpec(
        {
          'specVersion': 2,
          'slots': {
            'sidebar.sideways': {'children': []},
          },
        },
        vocabulary: v4UiVocabulary,
      );
      expect(unknown, isNotEmpty);
    });
  });

  group('the depth limit', () {
    Map<String, dynamic> chain(int length) {
      Map<String, dynamic> node = {'type': 'text', 'text': 'leaf'};
      for (var i = 1; i < length; i++) {
        node = {
          'type': 'column',
          'children': [node],
        };
      }
      return withUi([node]);
    }

    test('sixteen levels are accepted', () {
      final report = validateThemePayload(chain(16));
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('the seventeenth is dropped with a warning', () {
      final report = validateThemePayload(chain(17));
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 1, reason: report.issues.join('\n'));
      expect(
        report.issues.single.message,
        contains('deeper than $maxUiDepth levels'),
      );
    });
  });

  group('the reference fixture', () {
    late Map<String, dynamic> payload;

    setUpAll(() {
      payload = jsonDecode(
        File('conformance/draft/v4-kitchen-sink.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    });

    test('is a clean v4 payload', () {
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });

    test('its UI document is clean on its own', () {
      final issues = validateUiSpec(
        (payload['ui'] as Map).cast<String, dynamic>(),
        vocabulary: v4UiVocabulary,
      );
      expect(issues, isEmpty, reason: issues.join('\n'));
    });
  });
}
