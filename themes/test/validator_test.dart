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

    test('density of zero reads as 1.0 — an unset field must not shrink the UI',
        () {
      final payload = validPayload();
      payload['density'] = 0;
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(report.resolved!['density'], 1.0);
    });

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
    test('are a warning, not an error — that is what makes v3 shippable to v2',
        () {
      final payload = validPayload();
      payload['somethingNew'] = {'a': 1};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning), contains('somethingNew'));
    });

    test('a declared v3 payload knows the v3 blocks', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['typography'] = {'family': 'Inter'};
      payload['branding'] = {'appName': 'Aurora'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning),
          isNot(contains('specVersion')));
      expect(pathsOf(report, Severity.warning), isNot(contains('typography')));
      expect(pathsOf(report, Severity.warning), isNot(contains('branding')));
    });

    test('a v3 block that breaks its own rules is an error', () {
      final payload = validPayload();
      payload['specVersion'] = 3;
      payload['typography'] = {'family': 'Inter', 'styles': {'h1': {'fontSize': 400}}};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(pathsOf(report, Severity.warning),
          contains('typography.styles.h1.fontSize'));
    });
  });

  group('fonts', () {
    test('a family the platform cannot have is dropped', () {
      final payload = validPayload();
      payload['tokens'] = {'fontFamily': 'Inter/../../etc'};
      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect((report.resolved!['tokens'] as Map).containsKey('fontFamily'), isFalse);
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
      expect((report.resolved!['background'] as Map).containsKey('transparent'),
          isFalse);
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
        <String, dynamic>{'light': <String, dynamic>{}, 'dark': <String, dynamic>{}},
        <String, dynamic>{
          'light': <String, dynamic>{'background': '#fff'},
          'dark': <String, dynamic>{'background': '#fff'},
          'radius': 'nope',
          'tokens': 5,
        },
      ];

      for (final input in inputs) {
        expect(() => validateThemePayload(
          input is Map<String, dynamic> ? input : <String, dynamic>{},
        ), returnsNormally);
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
        final payload = jsonDecode(File('${dir.path}/${entry.key}').readAsStringSync())
            as Map<String, dynamic>;
        final report = validateThemePayload(payload);
        expect(report.hasErrors, isTrue, reason: entry.key);
        expect(pathsOf(report, Severity.error), contains(entry.value),
            reason: entry.key);
      }
    });
  });
}
