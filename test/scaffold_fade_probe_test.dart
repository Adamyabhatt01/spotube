// Reproduction probe: does a real shadcn Scaffold ground interpolate under
// PaletteTransitionScope, the way the _Probe in theme_transition_test does?
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/palette_transition_scope.dart';
import 'package:spotube/utils/theme_converter.dart';

ThemeData _appTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  return ThemeData(
    colorScheme: ThemeConverter.toColorScheme(
      ThemeColors(
        background: light ? '#ffffff' : '#0a0a0a',
        foreground: light ? '#111111' : '#eeeeee',
        card: light ? '#ffffff' : '#0a0a0a',
        cardForeground: light ? '#111111' : '#eeeeee',
        primary: light ? '#111111' : '#eeeeee',
        primaryForeground: light ? '#ffffff' : '#0a0a0a',
        secondary: light ? '#ffffff' : '#0a0a0a',
        secondaryForeground: light ? '#111111' : '#eeeeee',
        muted: light ? '#ffffff' : '#0a0a0a',
        mutedForeground: light ? '#111111' : '#eeeeee',
        accent: light ? '#ffffff' : '#0a0a0a',
        accentForeground: light ? '#111111' : '#eeeeee',
        destructive: '#ff0000',
        destructiveForeground: light ? '#ffffff' : '#0a0a0a',
        border: light ? '#ffffff' : '#0a0a0a',
        input: light ? '#ffffff' : '#0a0a0a',
        ring: light ? '#111111' : '#eeeeee',
      ),
      brightness: brightness,
      fallback: light
          ? LegacyColorSchemes.lightSlate()
          : LegacyColorSchemes.darkSlate(),
    ),
    surfaceOpacity: .8,
    surfaceBlur: 12,
  );
}

final _light = _appTheme(Brightness.light);
final _dark = _appTheme(Brightness.dark);

Widget _harness(Brightness brightness, Duration duration) => ShadcnApp(
      theme: _light,
      darkTheme: _dark,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => PaletteTransitionScope(
        theme: _light,
        darkTheme: _dark,
        scaling: const AdaptiveScaling.only(),
        brightness: brightness,
        duration: duration,
        child: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => const Scaffold(child: SizedBox.shrink()),
          ),
        ),
      ),
      home: const SizedBox.shrink(),
    );

/// Find the Scaffold's ground [Container] color by walking the render tree.
Color? _scaffoldGroundColor(WidgetTester tester) {
  Color? found;
  for (final element in find.byType(Container).evaluate()) {
    final w = element.widget as Container;
    final Color? c = w.color ??
        (w.decoration is BoxDecoration
            ? (w.decoration as BoxDecoration).color
            : null);
    if (c != null && c.a > 0.9) found = c;
  }
  return found;
}

void main() {
  testWidgets('real Scaffold ground interpolates mid-fade', (tester) async {
    await tester
        .pumpWidget(_harness(Brightness.light, const Duration(seconds: 1)));
    await tester.pump();
    final start = _scaffoldGroundColor(tester);
    debugPrint('start ground = $start');

    await tester
        .pumpWidget(_harness(Brightness.dark, const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 100));

    final mid = _scaffoldGroundColor(tester);
    debugPrint('mid (+100ms) ground = $mid');

    await tester.pump(const Duration(milliseconds: 400));
    final later = _scaffoldGroundColor(tester);
    debugPrint('later (+500ms) ground = $later');

    await tester.pumpAndSettle();
    final end = _scaffoldGroundColor(tester);
    debugPrint('end ground = $end');

    expect(start, isNotNull);
    expect(end, isNotNull);
    // The interesting question: is `mid` between start and end (fade), or
    // already equal to end (snap)?
    debugPrint('mid == start? ${mid == start}  mid == end? ${mid == end}');
  });
}
