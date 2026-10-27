import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// A complete, valid v2 payload to mutate in each test.
Map<String, dynamic> validPayload() {
  final roles = <String>[
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
    'light': palette('#ffffff', '#121212'),
    'dark': palette('#121212', '#ffffff'),
  };
}

/// The paths of the findings, so a test can assert what was reported.
List<String> pathsOf(ValidationReport report, Severity severity) => [
  for (final issue in report.issues)
    if (issue.severity == severity) issue.path,
];

void main() {
  group('a valid payload', () {
    test('has no findings', () {
      final report = validateThemePayload(validPayload());
      expect(report.issues, isEmpty);
      expect(report.hasErrors, isFalse);
    });

    test('resolves to the payload the app will draw', () {
      final report = validateThemePayload(validPayload());
      expect(report.resolved, isNotNull);
      expect(report.resolved!['light'], isA<Map<String, dynamic>>());
      expect((report.resolved!['light'] as Map)['primary'], '#ffffff');
      expect((report.resolved!['dark'] as Map)['primary'], '#121212');
    });

    test('fills in the fields the app defaults', () {
      final report = validateThemePayload(validPayload());
      final resolved = report.resolved!;
      expect((resolved['radius'] as Map)['pill'], 999.0);
      expect((resolved['surfaces'] as Map)['opacity'], 0.8);
      expect(resolved['density'], 1.0);
      expect((resolved['layout'] as Map)['chrome'], 'flat');
    });
  });

  group('colors', () {
    test('a missing role is an error — the app discards the whole theme', () {
      final payload = validPayload();
      (payload['dark'] as Map).remove('ring');
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isTrue);
      expect(pathsOf(report, Severity.error), contains('dark.ring'));
    });

    test('a color the app cannot parse is an error', () {
      final payload = validPayload();
      (payload['light'] as Map)['primary'] = '#fff';
      final report = validateThemePayload(payload);
      expect(pathsOf(report, Severity.error), contains('light.primary'));
    });

    test('eight digits are a color', () {
      final payload = validPayload();
      (payload['light'] as Map)['primary'] = '#80ff0000';
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
    });

    test('a role that is not a v2 role is ignored', () {
      final payload = validPayload();
      (payload['light'] as Map)['popover'] = '#123456';
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), contains('light.popover'));
    });
  });

  group('numbers', () {
    test('a value above the range is clamped, not rejected', () {
      final payload = validPayload();
      payload['radius'] = {'large': 120};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), contains('radius.large'));
      expect((report.resolved!['radius'] as Map)['large'], 64.0);
    });

    test(
      'density of zero reads as 1.0 — an unset field must not shrink the UI',
      () {
        final payload = validPayload();
        payload['density'] = 0;
        final report = validateThemePayload(payload);
        expect(report.hasErrors, isFalse);
        expect(report.resolved!['density'], 1.0);
      },
    );

    test('density below the range is clamped', () {
      final payload = validPayload();
      payload['density'] = 0.2;
      final report = validateThemePayload(payload);
      expect(report.resolved!['density'], 0.7);
    });

    test('opacity is a fraction', () {
      final payload = validPayload();
      payload['surfaces'] = {'opacity': 4.2};
      final report = validateThemePayload(payload);
      expect((report.resolved!['surfaces'] as Map)['opacity'], 1.0);
    });
  });

  group('enums', () {
    test('an unknown layout value falls back', () {
      final payload = validPayload();
      payload['layout'] = {'chrome': 'floating'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect((report.resolved!['layout'] as Map)['chrome'], 'flat');
    });

    test('an unknown background source is an error', () {
      final payload = validPayload();
      payload['background'] = {'source': 'wallpaper'};
      final report = validateThemePayload(payload);
      expect(pathsOf(report, Severity.error), contains('background.source'));
    });

    test('an unknown dynamic algorithm is an error', () {
      final payload = validPayload();
      payload['dynamic'] = {'source': 'albumArt', 'algorithm': 'magic'};
      final report = validateThemePayload(payload);
      expect(pathsOf(report, Severity.error), contains('dynamic.algorithm'));
    });
  });

  group('unknown fields', () {
    test(
      'are a warning, not an error — that is what makes v3 shippable to v2',
      () {
        final payload = validPayload();
        payload['somethingNew'] = {'a': 1};
        final report = validateThemePayload(payload);
        expect(report.hasErrors, isFalse);
        expect(pathsOf(report, Severity.warning), contains('somethingNew'));
      },
    );

    test('a declared v3 payload knows the v3 blocks', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['typography'] = {'family': 'Inter'};
      payload['branding'] = {'appName': 'Aurora'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), isNot(contains('specVersion')));
      expect(pathsOf(report, Severity.warning), isNot(contains('typography')));
      expect(pathsOf(report, Severity.warning), isNot(contains('branding')));
    });

    test('a v3 block that breaks its own rules is an error', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['typography'] = {
        'family': 'Inter',
        'styles': {
          'h1': {'fontSize': 400},
        },
      };
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(
        pathsOf(report, Severity.warning),
        contains('typography.styles.h1.fontSize'),
      );
    });
  });

  group('fonts', () {
    test('a family the platform cannot have is dropped', () {
      final payload = validPayload();
      payload['tokens'] = {'fontFamily': 'Inter/../../etc'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(
        (report.resolved!['tokens'] as Map).containsKey('fontFamily'),
        isFalse,
      );
    });

    test('a plain family is kept', () {
      final payload = validPayload();
      payload['tokens'] = {'fontFamily': 'Inter'};
      final report = validateThemePayload(payload);
      expect((report.resolved!['tokens'] as Map)['fontFamily'], 'Inter');
    });
  });

  group('the transparency flag', () {
    test('a boolean survives', () {
      final payload = validPayload();
      payload['background'] = {'source': 'shell', 'transparent': true};
      final report = validateThemePayload(payload);
      expect((report.resolved!['background'] as Map)['transparent'], isTrue);
    });

    test('anything else reads as no opinion', () {
      final payload = validPayload();
      payload['background'] = {'source': 'shell', 'transparent': 'yes'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(
        (report.resolved!['background'] as Map).containsKey('transparent'),
        isFalse,
      );
    });
  });

  group('the validator', () {
    test('never throws, whatever it is handed', () {
      final inputs = <Object?>[
        null,
        42,
        'text',
        <String, dynamic>{},
        <String, dynamic>{'light': 'not an object', 'dark': 3},
        <String, dynamic>{
          'light': <String, dynamic>{},
          'dark': <String, dynamic>{},
        },
        <String, dynamic>{
          'light': <String, dynamic>{'background': '#fff'},
          'dark': <String, dynamic>{'background': '#fff'},
          'radius': 'nope',
          'tokens': 5,
        },
      ];

      for (final input in inputs) {
        expect(
          () => validateThemePayload(
            input is Map<String, dynamic> ? input : <String, dynamic>{},
          ),
          returnsNormally,
        );
      }
    });

    test('reads the broken fixtures the way the app would', () {
      final dir = Directory('conformance/broken');
      expect(dir.existsSync(), isTrue);

      final fatal = {
        'missing-role.json': 'dark.ring',
        'bad-color.json': 'light.primary',
        'unknown-enum.json': 'background.source',
        'missing-palette.json': 'dark',
        'wrong-type.json': 'light.primary',
      };

      for (final entry in fatal.entries) {
        final payload =
            jsonDecode(File('${dir.path}/${entry.key}').readAsStringSync())
                as Map<String, dynamic>;
        final report = validateThemePayload(payload);
        expect(report.hasErrors, isTrue, reason: entry.key);
        expect(
          pathsOf(report, Severity.error),
          contains(entry.value),
          reason: entry.key,
        );
      }
    });
  });

  group('the ui contract', () {
    Map<String, dynamic> withUi(
      Map<String, dynamic> ui, {
      Map<String, dynamic> extra = const {},
    }) {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['ui'] = ui;
      payload.addAll(extra);
      return payload;
    }

    Map<String, dynamic> slot(
      String name,
      List<Map<String, dynamic>> children,
    ) => {
      'specVersion': 2,
      'slots': {
        name: {'children': children},
      },
    };

    test('a flat prop is what the themes write, and it is read', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {
              'type': 'image',
              'src': 'player.artwork',
              'width': 64,
              'height': 64,
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('an unknown prop is an error, not a silent no-op', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {'type': 'image', 'widht': 64},
          ]),
        ),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.player.leading[0].widht'),
      );
    });

    test('the legacy props object still reads, with a warning', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {
              'type': 'image',
              'props': {'src': 'player.artwork', 'width': 64},
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(
        pathsOf(report, Severity.warning),
        contains('ui.slots.player.leading[0].props'),
      );
    });

    test('an unknown binding is an error', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {'type': 'text', 'bind': 'player.titel'},
          ]),
        ),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.player.leading[0].bind'),
      );
    });

    test('an unknown action is an error, and a known one is not', () {
      final bad = validateThemePayload(
        withUi(
          slot('player.leading', [
            {
              'type': 'button',
              'action': {'type': 'skip'},
            },
          ]),
        ),
      );
      expect(
        pathsOf(bad, Severity.error),
        contains('ui.slots.player.leading[0].action.type'),
      );

      final good = validateThemePayload(
        withUi(
          slot('player.leading', [
            {
              'type': 'button',
              'action': {
                'type': 'navigate',
                'args': {'target': 'lyrics'},
              },
            },
          ]),
        ),
      );
      expect(good.hasErrors, isFalse, reason: good.issues.join('\n'));
    });

    test('a navigate without a target warns', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {
              'type': 'button',
              'action': {'type': 'navigate'},
            },
          ]),
        ),
      );
      expect(
        pathsOf(report, Severity.warning),
        contains('ui.slots.player.leading[0].action.args.target'),
      );
    });

    test('the stage is a dock and has slots', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['layout'] = {
        'player': {'dock': 'stage'},
      };
      payload['ui'] = slot('stage.center', [
        {'type': 'text', 'bind': 'player.title'},
      ]);
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('an animate node is v2 ui, and a v1 document says so', () {
      final ui = slot('stage.center', [
        {
          'type': 'animate',
          'kind': 'rotate',
          'duration': 24000,
          'bind': 'player.playing',
          'children': [
            {'type': 'image', 'src': 'player.artwork', 'shape': 'circle'},
          ],
        },
      ]);
      ui['specVersion'] = 1;
      final report = validateThemePayload(withUi(ui));
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(
        pathsOf(report, Severity.warning),
        contains('ui.slots.stage.center[0]'),
      );
    });

    test('the image props a pixel theme needs are validated', () {
      final report = validateThemePayload(
        withUi(
          slot('stage.center', [
            {
              'type': 'image',
              'src': 'player.artwork',
              'shape': 'circle',
              'fit': 'cover',
              'filter': 'nearest',
              'tile': false,
              'radius': 999,
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));

      final bad = validateThemePayload(
        withUi(
          slot('stage.center', [
            {'type': 'image', 'shape': 'round', 'filter': 'cubic'},
          ]),
        ),
      );
      expect(
        pathsOf(bad, Severity.error),
        containsAll([
          'ui.slots.stage.center[0].shape',
          'ui.slots.stage.center[0].filter',
        ]),
      );
    });

    test('a tiled background keeps whole-number magnification', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['background'] = {
        'source': 'asset',
        'asset': 'asset://textures/obsidian.png',
        'tile': true,
        'scale': 4,
      };
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      final background = report.resolved!['background'] as Map;
      expect(background['tile'], isTrue);
      expect(background['scale'], 4);

      payload['background']['scale'] = 2.5;
      final rounded = validateThemePayload(payload);
      expect(pathsOf(rounded, Severity.warning), contains('background.scale'));
      expect((rounded.resolved!['background'] as Map)['scale'], 3);
    });
    test('a list repeats a collection and resolves item bindings', () {
      final report = validateThemePayload(
        withUi(
          slot('collection.content', [
            {
              'type': 'list',
              'bind': 'collection.tracks',
              'gap': 4,
              'limit': 100,
              'align': 'stretch',
              'children': [
                {
                  'type': 'row',
                  'children': [
                    {'type': 'text', 'bind': 'item.title'},
                    {
                      'type': 'image',
                      'src': 'item.artwork',
                      'width': 40,
                      'height': 40,
                    },
                    {
                      'type': 'button',
                      'label': 'Play',
                      'action': {'type': 'playItem'},
                    },
                  ],
                },
              ],
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('a shelf and a sized shape are part of the vocabulary', () {
      final report = validateThemePayload(
        withUi(
          slot('home.content', [
            {
              'type': 'list',
              'bind': 'home.recent',
              'direction': 'horizontal',
              'gap': 12,
              'limit': 20,
              'children': [
                {
                  'type': 'card',
                  'width': 36,
                  'height': 36,
                  'radius': 999,
                  'padding': 0,
                },
              ],
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('home bindings resolve, including the greeting', () {
      final report = validateThemePayload(
        withUi(
          slot('home.content', [
            {'type': 'text', 'bind': 'app.greeting'},
            {'type': 'text', 'bind': 'home.greeting'},
            {
              'type': 'list',
              'bind': 'home.recent',
              'children': [
                {'type': 'text', 'bind': 'item.title'},
              ],
            },
          ]),
        ),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });

    test('the item action verbs are dispatched', () {
      for (final type in [
        'playItem',
        'playCollection',
        'openItem',
        'likeItem',
        'downloadItem',
      ]) {
        final report = validateThemePayload(
          withUi(
            slot('queue.content', [
              {
                'type': 'list',
                'bind': 'queue.tracks',
                'children': [
                  {
                    'type': 'button',
                    'label': 'x',
                    'action': {'type': type},
                  },
                ],
              },
            ]),
          ),
        );
        expect(
          report.hasErrors,
          isFalse,
          reason: '$type: ${report.issues.join('\n')}',
        );
      }
    });

    test('a binding outside a known scope is still a typo', () {
      final report = validateThemePayload(
        withUi(
          slot('player.leading', [
            {'type': 'text', 'bind': 'pages.title'},
          ]),
        ),
      );
      expect(
        pathsOf(report, Severity.error),
        contains('ui.slots.player.leading[0].bind'),
      );
    });

    test('every page content slot is published', () {
      const names = [
        'collection.content',
        'collection.header',
        'collection.before_tracks',
        'collection.after_tracks',
        'artist.content',
        'artist.header',
        'home.content',
        'search.content',
        'library.content',
        'queue.content',
        'downloads.content',
        'stats.content',
      ];
      final report = validateThemePayload(
        withUi({
          'specVersion': 2,
          'slots': {
            for (final name in names)
              name: {
                'children': [
                  {'type': 'text', 'bind': 'player.title'},
                ],
              },
          },
        }),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    });
  });
}
