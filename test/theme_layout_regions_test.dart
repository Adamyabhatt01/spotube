// Phase 5 gives the theme two more shell regions: a sidebar body it can draw
// itself, and a right-hand aside. Both are opt-in through `layout`, both carry
// a width a theme may set, and both have to survive an unknown value from a
// plugin built against a different version. The width reaches layout
// constraints, so the same two rules as the card tokens apply: defaults are
// the host literals, and anything outside the contract range is clamped.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ThemeDefinition _theme({ThemeLayout layout = const ThemeLayout()}) {
  return ThemeDefinition(
    light: builtInLightThemeColors(),
    dark: builtInDarkThemeColors(),
    layout: layout,
  );
}

Future<
    ({
      double sidebar,
      double aside,
      bool sidebarOwned,
      bool asideEnabled,
    })> _measure(
  WidgetTester tester, {
  ThemeLayout layout = const ThemeLayout(),
  double scaling = 1,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late final ({
    double sidebar,
    double aside,
    bool sidebarOwned,
    bool asideEnabled,
  }) metrics;
  await tester.pumpWidget(
    ShadcnApp(
      scaling: AdaptiveScaling(scaling),
      home: AppLayout(
        layout: layout,
        child: Builder(
          builder: (context) {
            metrics = (
              sidebar: context.sidebarWidth,
              aside: context.asideWidth,
              sidebarOwned: context.sidebarOwned,
              asideEnabled: context.asideEnabled,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  // The app theme animates to the requested scaling.
  await tester.pump(const Duration(seconds: 1));
  return metrics;
}

void main() {
  group('ThemeLayout regions', () {
    test('defaults keep the host sidebar and no aside', () {
      const layout = ThemeLayout();
      expect(layout.sidebar, ThemeSidebar.host);
      expect(layout.aside, ThemeAside.none);
      expect(layout.sidebarWidth, isNull);
      expect(layout.asideWidth, isNull);
    });

    test('reads every key the validator accepts', () {
      final layout = ThemeLayout.fromJson(const {
        'sidebar': 'theme',
        'sidebarWidth': 240,
        'aside': 'theme',
        'asideWidth': 360.5,
      });

      expect(layout.sidebar, ThemeSidebar.theme);
      expect(layout.sidebarWidth, 240.0);
      expect(layout.aside, ThemeAside.theme);
      expect(layout.asideWidth, 360.5);
    });

    test('an unknown enum value degrades per field', () {
      final layout = ThemeLayout.fromJson(const {
        'sidebar': 'left',
        'aside': 'right',
        'nav': 'rail',
      });

      expect(layout.sidebar, ThemeSidebar.host);
      expect(layout.aside, ThemeAside.none);
      // The sibling field is untouched by the typo.
      expect(layout.nav, ThemeNav.rail);
    });

    test('round-trips over the wire names', () {
      const layout = ThemeLayout(
        sidebar: ThemeSidebar.theme,
        sidebarWidth: 240,
        aside: ThemeAside.theme,
        asideWidth: 360,
      );

      final json = layout.toJson();
      expect(json['sidebar'], 'theme');
      expect(json['sidebarWidth'], 240.0);
      expect(json['aside'], 'theme');
      expect(json['asideWidth'], 360.0);
      expect(ThemeLayout.fromJson(json), layout);
    });
  });

  group('AppLayout widths', () {
    testWidgets('defaults are the host literals', (tester) async {
      final metrics = await _measure(tester);

      expect(metrics.sidebar, 200);
      expect(metrics.aside, 320);
      expect(metrics.sidebarOwned, isFalse);
      expect(metrics.asideEnabled, isFalse);
    });

    testWidgets('a theme width replaces the literal', (tester) async {
      final metrics = await _measure(
        tester,
        layout: const ThemeLayout(
          sidebar: ThemeSidebar.theme,
          sidebarWidth: 260,
          aside: ThemeAside.theme,
          asideWidth: 360,
        ),
      );

      expect(metrics.sidebar, 260);
      expect(metrics.aside, 360);
      expect(metrics.sidebarOwned, isTrue);
      expect(metrics.asideEnabled, isTrue);
    });

    testWidgets('both widths ride the active scaling', (tester) async {
      final metrics = await _measure(
        tester,
        scaling: 2,
        layout: const ThemeLayout(
          sidebarWidth: 260,
          asideWidth: 360,
        ),
      );

      expect(metrics.sidebar, 520);
      expect(metrics.aside, 720);
    });

    testWidgets('the defaults also ride the scaling', (tester) async {
      final metrics = await _measure(tester, scaling: 1.5);

      expect(metrics.sidebar, 300);
      expect(metrics.aside, 480);
    });
  });

  group('sanitizer widths', () {
    test('clamps into the contract range', () {
      final sanitized = sanitizeThemeDefinition(
        _theme(
          layout: const ThemeLayout(
            sidebarWidth: 5000,
            asideWidth: -10,
          ),
        ),
      );

      expect(sanitized.layout.sidebarWidth, 1000);
      expect(sanitized.layout.asideWidth, 0);
    });

    test('non-finite widths fall back to the host default', () {
      final sanitized = sanitizeThemeDefinition(
        _theme(
          layout: const ThemeLayout(
            sidebarWidth: double.infinity,
            asideWidth: double.nan,
          ),
        ),
      );

      expect(sanitized.layout.sidebarWidth, isNull);
      expect(sanitized.layout.asideWidth, isNull);
    });
  });
}
