// The app's glass is derived from the same config the desktop draws with:
// foot's `[colors-*] alpha`/`blur` and Caelestia's `shell.json` transparency,
// veiled in the live scheme's `surface`. Locked behavior:
//  - Absent foot config means no opinion — the plugin's authored numbers stand.
//  - The veil is emitted #AARRGGBB, because that is what the theme parser reads
//    an 8-digit string as; CSS order would trade alpha for the red channel.
//  - Unparseable input degrades to a default, never a throw.
//
// Hermetic: temp dirs only, no shell installed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_glass_config.dart';

void main() {
  group('parseFootIniTreatment', () {
    test('reads alpha and blur from the dark section', () {
      const ini = '''
font=JetBrains Mono Nerd Font:size=12

[colors-dark]
alpha=0.78
alpha-mode=matching
blur=yes
''';
      final treatment = parseFootIniTreatment(ini);
      expect(treatment.alpha, 0.78);
      expect(treatment.blur, isTrue);
    });

    test('comments and blank lines never become keys', () {
      const ini = '''
; alpha=0.1
# blur=yes

[colors-dark]
  alpha = 0.5
''';
      final treatment = parseFootIniTreatment(ini);
      expect(treatment.alpha, 0.5);
      expect(treatment.blur, isFalse);
    });

    test('light mode falls back to the dark alpha, which is all dots declares',
        () {
      const ini = '[colors-dark]\nalpha=0.78\nblur=yes\n';
      final treatment = parseFootIniTreatment(ini, mode: 'light');
      expect(treatment.alpha, 0.78);
      expect(treatment.blur, isTrue);
    });

    test('an explicit light section beats the dark fallback', () {
      const ini = '[colors-dark]\nalpha=0.78\n[colors-light]\nalpha=0.9\n';
      expect(
        parseFootIniTreatment(ini, mode: 'light').alpha,
        0.9,
      );
      // ...without leaking into dark.
      expect(parseFootIniTreatment(ini, mode: 'dark').alpha, 0.78);
    });

    test('the prelude and the pre-1.28 [colors] section both resolve', () {
      expect(parseFootIniTreatment('alpha=0.4\n').alpha, 0.4);
      expect(parseFootIniTreatment('[colors]\nalpha=0.3\n').alpha, 0.3);
    });

    test('a later section wins over an earlier one for the same key', () {
      const ini = '[main]\nalpha=0.2\n[colors-dark]\nalpha=0.6\n';
      expect(parseFootIniTreatment(ini).alpha, 0.6);
    });

    test('missing, malformed and out-of-range alpha all stay render-safe', () {
      expect(parseFootIniTreatment('[colors-dark]\n').alpha, 1.0);
      expect(parseFootIniTreatment('[colors-dark]\nalpha=sharp\n').alpha, 1.0);
      expect(parseFootIniTreatment('[colors-dark]\nalpha=4\n').alpha, 1.0);
      expect(parseFootIniTreatment('[colors-dark]\nalpha=-1\n').alpha, 0.0);
    });

    test('blur accepts only foot\'s own spellings', () {
      expect(parseFootIniTreatment('[colors-dark]\nblur=no\n').blur, isFalse);
      expect(
        parseFootIniTreatment('[colors-dark]\nblur=TRUE\n').blur,
        isTrue,
      );
      expect(parseFootIniTreatment('[colors-dark]\nblur=1\n').blur, isTrue);
    });
  });

  group('parseShellTransparency', () {
    test('reads the enabled flag and an explicit base', () {
      final transparency = parseShellTransparency(
        jsonEncode({
          'appearance': {
            'transparency': {'enabled': true, 'base': 0.6},
          },
        }),
      );
      expect(transparency.enabled, isTrue);
      expect(transparency.base, 0.6);
    });

    test('the shell\'s compiled-in defaults stand when nothing is set', () {
      // shell.json ships `{"enabled": true}` alone, so base must match
      // appearanceconfig.hpp rather than inventing a softer number.
      final transparency = parseShellTransparency(
        jsonEncode({
          'appearance': {
            'transparency': {'enabled': true},
          },
        }),
      );
      expect(transparency.base, 0.85);

      const absent = '';
      expect(parseShellTransparency(null).enabled, isFalse);
      expect(parseShellTransparency(absent).enabled, isFalse);
      expect(parseShellTransparency('{nope').enabled, isFalse);
      expect(
        parseShellTransparency(jsonEncode({'appearance': 'junk'})).base,
        0.85,
      );
    });

    test('base is clamped into an alpha range', () {
      final transparency = parseShellTransparency(
        jsonEncode({
          'appearance': {
            'transparency': {'enabled': true, 'base': 12.0},
          },
        }),
      );
      expect(transparency.base, 1.0);
    });
  });

  group('veilOverlay', () {
    test('emits AARRGGBB so the surface hue survives', () {
      expect(
        veilOverlay(surfaceHex: '0c0e12', alpha: 0.78),
        '#c70c0e12',
      );
      // AA=ff, RGB=fafafa: eight digits, alpha first.
      expect(
        veilOverlay(surfaceHex: '#fafafa', alpha: 1.0),
        '#fffafafa',
      );
      expect(veilOverlay(surfaceHex: '0c0e12', alpha: 0.0), '#000c0e12');
    });

    test('rejects anything that is not a bare or hashed 6-digit hex', () {
      expect(veilOverlay(surfaceHex: '0c0e1', alpha: 0.78), isNull);
      expect(veilOverlay(surfaceHex: 'zzzzzz', alpha: 0.78), isNull);
      expect(veilOverlay(surfaceHex: 'c70c0e12', alpha: 0.78), isNull);
    });
  });

  group('deriveGlass', () {
    const footIni = '[colors-dark]\nalpha=0.78\nblur=yes\n';
    final shellJson = jsonEncode({
      'appearance': {
        'transparency': {'enabled': true},
      },
    });

    test('no foot config means no opinion, so the plugin keeps authoring', () {
      expect(
        deriveGlass(
          footIni: null,
          shellJson: shellJson,
          surfaceHex: '0c0e12',
        ),
        isNull,
      );
    });

    test(
        'reproduces the terminal composite: full wallpaper, alpha-bearing veil',
        () {
      final glass = deriveGlass(
        footIni: footIni,
        shellJson: shellJson,
        surfaceHex: '0c0e12',
      );

      final background = glass!.background!;
      expect(background.source, ThemeBackgroundSource.shell);
      // Group opacity stays 1.0: the veil carries the alpha, so the result
      // cannot shift with whatever the app paints underneath.
      expect(background.opacity, 1.0);
      expect(background.blur, kShellBlurSigma);
      expect(background.overlay, '#c70c0e12');
      expect(glass.surfacesOpacity, 0.85);
    });

    test('a terminal without compositor blur gets an unblurred backdrop', () {
      final glass = deriveGlass(
        footIni: '[colors-dark]\nalpha=0.78\nblur=no\n',
        shellJson: shellJson,
        surfaceHex: '0c0e12',
      );
      expect(glass!.background!.blur, 0.0);
    });

    test('transparency off solidifies panels but not the terminal backdrop',
        () {
      final glass = deriveGlass(
        footIni: footIni,
        shellJson: jsonEncode({
          'appearance': {
            'transparency': {'enabled': false},
          },
        }),
        surfaceHex: '0c0e12',
      );
      expect(glass!.surfacesOpacity, 1.0);
      expect(glass.background!.overlay, '#c70c0e12');
    });

    test('an unusable surface role yields no glass rather than a wrong veil',
        () {
      expect(
        deriveGlass(
          footIni: footIni,
          shellJson: shellJson,
          surfaceHex: 'not-a-color',
        ),
        isNull,
      );
    });
  });

  group('readDerivedGlass', () {
    test('reads both config files off the XDG config root', () async {
      final dir = await Directory.systemTemp.createTemp('glass-config');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/foot').create();
      await Directory('${dir.path}/caelestia').create();
      await File('${dir.path}/foot/foot.ini')
          .writeAsString('[colors-dark]\nalpha=0.78\nblur=yes\n');
      await File('${dir.path}/caelestia/shell.json').writeAsString(
        jsonEncode({
          'appearance': {
            'transparency': {'enabled': true, 'base': 0.7},
          },
        }),
      );

      final glass = await readDerivedGlass(
        surfaceHex: '0c0e12',
        mode: 'dark',
        configDir: dir.path,
      );

      expect(glass!.surfacesOpacity, 0.7);
      expect(glass.background!.overlay, '#c70c0e12');
    });

    test('a bare config root degrades to null instead of guessing', () async {
      final dir = await Directory.systemTemp.createTemp('glass-empty');
      addTearDown(() => dir.delete(recursive: true));

      expect(
        await readDerivedGlass(
          surfaceHex: '0c0e12',
          mode: 'dark',
          configDir: dir.path,
        ),
        isNull,
      );
    });
  });
}
