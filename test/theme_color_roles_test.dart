import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';
import 'package:spotube/utils/theme_converter.dart';

/// The v3 colour roles, and the promise they come with: a theme may name
/// them, the host uses them, and a role it does not name falls back to the
/// role it aliases.
void main() {
  final fallback = LegacyColorSchemes.lightSlate();

  ThemeColors paletteWith(Map<String, String> overrides) {
    final base = builtInLightThemeColors();
    return base.copyWith(
      popover: overrides['popover'],
      popoverForeground: overrides['popoverForeground'],
      sidebar: overrides['sidebar'],
      sidebarForeground: overrides['sidebarForeground'],
      sidebarPrimary: overrides['sidebarPrimary'],
      sidebarPrimaryForeground: overrides['sidebarPrimaryForeground'],
      sidebarAccent: overrides['sidebarAccent'],
      sidebarAccentForeground: overrides['sidebarAccentForeground'],
      sidebarBorder: overrides['sidebarBorder'],
      sidebarRing: overrides['sidebarRing'],
      chart1: overrides['chart1'],
      chart2: overrides['chart2'],
      chart3: overrides['chart3'],
      chart4: overrides['chart4'],
      chart5: overrides['chart5'],
      chart6: overrides['chart6'],
      success: overrides['success'],
      successForeground: overrides['successForeground'],
      warning: overrides['warning'],
      warningForeground: overrides['warningForeground'],
      info: overrides['info'],
      infoForeground: overrides['infoForeground'],
    );
  }

  group('the palette', () {
    test('a v2 payload keeps the seventeen roles it has', () {
      final colors = builtInLightThemeColors();
      expect(colors.popover, isNull);
      expect(colors.sidebar, isNull);
      expect(colors.chart1, isNull);
      expect(colors.success, isNull);
    });

    test('a role the theme names reaches the scheme', () {
      final scheme = ThemeConverter.toColorScheme(
        paletteWith({
          'popover': '#123456',
          'sidebar': '#654321',
          'sidebarPrimary': '#0a0b0c',
          'chart1': '#ff0000',
        }),
        brightness: Brightness.light,
        fallback: fallback,
      );

      expect(scheme.popover, const Color(0xff123456));
      expect(scheme.sidebar, const Color(0xff654321));
      expect(scheme.sidebarPrimary, const Color(0xff0a0b0c));
      expect(scheme.chart1, const Color(0xffff0000));
    });

    test('a role the theme does not name falls back to the role it aliases',
        () {
      final base = builtInLightThemeColors();
      final scheme = ThemeConverter.toColorScheme(
        base,
        brightness: Brightness.light,
        fallback: fallback,
      );

      expect(scheme.popover, scheme.card);
      expect(scheme.popoverForeground, scheme.cardForeground);
      expect(scheme.sidebar, scheme.card);
      expect(scheme.sidebarPrimary, scheme.primary);
      expect(scheme.sidebarAccent, scheme.secondary);
      expect(scheme.sidebarBorder, scheme.border);
      expect(scheme.sidebarRing, scheme.ring);
    });

    test('one unreadable colour does not cost the theme its palette', () {
      // Before, one bad colour threw and the whole palette was discarded:
      // the user saw the built-in theme and no explanation.
      final base = builtInLightThemeColors();
      final scheme = ThemeConverter.toColorScheme(
        base.copyWith(primary: '#not-a-colour'),
        brightness: Brightness.light,
        fallback: fallback,
      );

      // The broken role falls back...
      expect(scheme.primary, fallback.primary);
      // ...and everything else is still the theme's.
      expect(scheme.background, ThemeConverter.parseColor(base.background));
      expect(scheme.foreground, ThemeConverter.parseColor(base.foreground));
      expect(scheme.card, ThemeConverter.parseColor(base.card));
    });

    test('a role that is too short falls back too', () {
      final scheme = ThemeConverter.toColorScheme(
        builtInLightThemeColors().copyWith(primary: '#fff'),
        brightness: Brightness.light,
        fallback: fallback,
      );
      expect(scheme.primary, fallback.primary);
    });
  });

  group('the status colours', () {
    test('fall back to the host own when the theme does not name them', () {
      final semantic = ThemeConverter.toSemanticColors(
        builtInLightThemeColors(),
        fallback: builtInLightSemanticColors,
      );
      expect(semantic.success, builtInLightSemanticColors.success);
      expect(semantic.warning, builtInLightSemanticColors.warning);
      expect(semantic.info, builtInLightSemanticColors.info);
    });

    test('come from the theme when it names them', () {
      final semantic = ThemeConverter.toSemanticColors(
        paletteWith({
          'success': '#00ff00',
          'successForeground': '#001100',
          'warning': '#ffaa00',
          'info': '#0000ff',
          'chart6': '#abcdef',
        }),
        fallback: builtInLightSemanticColors,
      );

      expect(semantic.success, '#00ff00');
      expect(semantic.successForeground, '#001100');
      expect(semantic.warning, '#ffaa00');
      expect(semantic.info, '#0000ff');
      expect(semantic.chart6, '#abcdef');
    });

    test('an unreadable one falls back', () {
      final semantic = ThemeConverter.toSemanticColors(
        paletteWith({'success': 'nonsense'}),
        fallback: builtInLightSemanticColors,
      );
      expect(semantic.success, builtInLightSemanticColors.success);
    });

    testWidgets('are published through the layout', (tester) async {
      late BuildContext captured;

      await tester.pumpWidget(
        MaterialApp(
          home: AppLayout(
            semanticColors: builtInDarkSemanticColors,
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(captured.successColor, const Color(0xff4ade80));
      expect(captured.warningColor, const Color(0xfffbbf24));
      expect(captured.infoColor, const Color(0xff60a5fa));
      expect(captured.chart6Color, const Color(0xffa78bfa));
    });
  });

  group('the payload version', () {
    test('a v2 payload decodes as version 2', () {
      final definition = ThemeDefinition.fromJson({
        'light': builtInLightThemeColors().toJson(),
        'dark': builtInDarkThemeColors().toJson(),
      });
      expect(definition.specVersion, 2);
    });

    test('a v3 payload decodes as version 3', () {
      final definition = ThemeDefinition.fromJson({
        'specVersion': 3,
        'light': builtInLightThemeColors().toJson(),
        'dark': builtInDarkThemeColors().toJson(),
      });
      expect(definition.specVersion, 3);
    });
  });
}
