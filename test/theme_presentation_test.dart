import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

Map<String, dynamic> _palette() => {
      'background': '#000000',
      'foreground': '#ffffff',
      'card': '#111111',
      'cardForeground': '#ffffff',
      'primary': '#00ff00',
      'primaryForeground': '#000000',
      'secondary': '#222222',
      'secondaryForeground': '#ffffff',
      'muted': '#333333',
      'mutedForeground': '#999999',
      'accent': '#444444',
      'accentForeground': '#ffffff',
      'destructive': '#ff0000',
      'destructiveForeground': '#ffffff',
      'border': '#555555',
      'input': '#666666',
      'ring': '#00ff00',
    };

ThemeDefinition _theme(Map<String, dynamic> extra) => sanitizeThemeDefinition(
      ThemeDefinition.fromJson({
        'specVersion': 3,
        'light': _palette(),
        'dark': _palette(),
        ...extra,
      }),
    );

void main() {
  final scheme = LegacyColorSchemes.darkSlate();

  group('presentation defaults', () {
    test('a null theme is the app look at scale 1', () {
      final presentation = resolveThemePresentation(null, scheme: scheme);
      expect(presentation.sizeScale, 1);
      expect(presentation.textScale, 1);
      expect(presentation.radiusScale, 1);
      expect(presentation.iconScale, 1);
      expect(presentation.spacingScale, 1);
      expect(presentation.spacing.page, 24);
      expect(presentation.spacing.pageHorizontal, 24);
      expect(presentation.motion.normalDuration,
          const Duration(milliseconds: 200));
      expect(presentation.motion.curve, Curves.easeOutCubic);
      expect(presentation.typography.base.fontSize, 16);
      expect(presentation.iconTheme.small.size, 16);
    });

    test('card gap uses spacing, falling back to the v2 gutter', () {
      final legacy = resolveThemePresentation(
        _theme({
          'tokens': {'gutter': 18}
        }),
        scheme: scheme,
      );
      final v3 = resolveThemePresentation(
        _theme({
          'tokens': {'gutter': 18},
          'spacing': {'cardGap': 24},
        }),
        scheme: scheme,
      );

      expect(legacy.spacing.cardGap, 18);
      expect(v3.spacing.cardGap, 24);
    });
  });

  group('Spotify shell presentation', () {
    final payload = jsonDecode(
      File('themes/conformance/spotify-shell.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final theme = ThemeDefinition.fromJson(payload);
    final presentation = resolveThemePresentation(theme, scheme: scheme);

    test('applies the declared type ladder in Inter', () {
      expect(presentation.typography.h1.fontSize, 32);
      expect(presentation.typography.h1.fontWeight, FontWeight.w800);
      expect(presentation.typography.h1.fontFamily, 'Inter');
      expect(presentation.typography.p.fontSize, 14);
      expect(presentation.typography.xSmall.fontSize, 11);
      expect(presentation.typography.textMuted.fontSize, 13);
      // A role-coloured style resolves against the palette it is drawn on.
      expect(presentation.typography.textMuted.color, scheme.mutedForeground);
    });

    test('applies the icon ladder and the spacing scale', () {
      expect(presentation.iconTheme.small.size, 16);
      expect(presentation.iconTheme.medium.size, 20);
      expect(presentation.iconTheme.large.size, 24);
      expect(presentation.iconTheme.xLarge.size, 32);
      expect(presentation.spacing.page, 24);
      expect(presentation.spacing.section, 32);
      expect(presentation.spacing.cardGap, 20);
    });

    test('applies the motion scale', () {
      expect(
          presentation.motion.fastDuration, const Duration(milliseconds: 120));
      expect(presentation.motion.normalDuration,
          const Duration(milliseconds: 200));
      expect(
          presentation.motion.slowDuration, const Duration(milliseconds: 320));
      expect(presentation.motion.curve, Curves.easeOutCubic);
    });
  });

  group('type family', () {
    test('the declared family reaches roles the theme did not spell out', () {
      final theme = _theme({
        'typography': {
          'family': 'Inter',
          'monoFamily': 'JetBrains Mono',
          'styles': {
            'p': {'fontSize': 14},
          },
        },
      });
      final resolved = resolveThemePresentation(theme, scheme: scheme);

      expect(resolved.typography.sans.fontFamily, 'Inter');
      expect(resolved.typography.h2.fontFamily, 'Inter');
      expect(resolved.typography.blockQuote.fontFamily, 'Inter');
      expect(resolved.typography.base.fontSize, 16);
      expect(resolved.typography.mono.fontFamily, 'JetBrains Mono');
      expect(resolved.typography.inlineCode.fontFamily, 'JetBrains Mono');
    });

    test('a per-style family wins over the ladder default', () {
      final theme = _theme({
        'typography': {
          'family': 'Inter',
          'styles': {
            'h1': {'fontFamily': 'Cookie'},
          },
        },
      });
      final resolved = resolveThemePresentation(theme, scheme: scheme);

      expect(resolved.typography.h1.fontFamily, 'Cookie');
      expect(resolved.typography.h2.fontFamily, 'Inter');
    });
  });

  group('clamping', () {
    final theme = _theme({
      'typography': {
        'family': 'Inter',
        'styles': {
          'h1': {
            'fontSize': 500,
            'fontWeight': 5000,
            'height': 99,
            'letterSpacing': 99,
            'color': '@primary',
          },
          'p': {'fontSize': 1, 'height': 0},
          'brand': {'fontSize': 20},
        },
      },
      'icons': {'sm': 1, 'md': 500, 'lg': 'big'},
      'spacing': {'page': 999, 'sm': -4, 'cardGap': 'wide'},
      'motion': {'fast': 9999, 'normal': -1, 'easing': 'bounce'},
      'scale': {
        'size': 9,
        'text': 0,
        'radius': 2,
        'icon': 0.1,
        'spacing': 1.5,
      },
    });
    final presentation = resolveThemePresentation(theme, scheme: scheme);

    test('type styles stay renderable', () {
      expect(presentation.typography.h1.fontSize, 96);
      expect(presentation.typography.h1.fontWeight, FontWeight.w900);
      expect(presentation.typography.h1.height, 2.4);
      expect(presentation.typography.h1.letterSpacing, 8);
      expect(presentation.typography.h1.color, scheme.primary);
      expect(presentation.typography.p.fontSize, 8);
      expect(presentation.typography.p.height, 0.8);
      // `brand` is not a shadcn slot; it must not be mistaken for one.
      expect(presentation.typography.h1.fontSize, isNot(20));
    });

    test('icon sizes, spacing and motion stay in range', () {
      expect(presentation.iconTheme.small.size, 8);
      expect(presentation.iconTheme.medium.size, 32);
      expect(presentation.iconTheme.large.size, 12);
      expect(presentation.spacing.page, 96);
      expect(presentation.spacing.sm, 0);
      expect(presentation.spacing.cardGap, 12);
      expect(
          presentation.motion.fastDuration, const Duration(milliseconds: 1000));
      expect(presentation.motion.normalDuration, Duration.zero);
      expect(presentation.motion.curve, Curves.easeOutCubic);
    });

    test('scale multipliers stay in range', () {
      expect(presentation.sizeScale, 2);
      expect(presentation.textScale, 0.5);
      expect(presentation.radiusScale, 2);
      expect(presentation.iconScale, 0.5);
      expect(presentation.spacingScale, 1.5);
    });

    test('a non-name is never used as a font family', () {
      final bad = _theme({
        'typography': {
          'family': '../../etc/passwd',
          'styles': {
            'p': {'fontFamily': 'Bad\nFamily'},
          },
        },
      });
      final resolved = resolveThemePresentation(bad, scheme: scheme);
      expect(resolved.typography.p.fontFamily, isNull);
    });
  });
}
