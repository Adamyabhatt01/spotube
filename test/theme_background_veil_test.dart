// Real-transparency veil: with the compositor as the ground, the layer
// skips the wallpaper image and its blur (painting them would cover the
// desktop; blur would sample nothing) but still paints the theme's overlay
// veil — it is translucent, so the live desktop shows through tinted with
// the theme's background colour instead of losing it. No veil declared
// stays fully clear.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/theme_background_layer.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/utils/theme_converter.dart';

class _ShellSource extends ThemeShellSource {
  @override
  String? getBackgroundPath() => null;

  @override
  Future<ThemeDefinition?> getTheme() async => null;
}

ThemeColors _colors() => const ThemeColors(
      background: '#000000',
      foreground: '#ffffff',
      card: '#111111',
      cardForeground: '#ffffff',
      primary: '#222222',
      primaryForeground: '#ffffff',
      secondary: '#333333',
      secondaryForeground: '#ffffff',
      muted: '#444444',
      mutedForeground: '#ffffff',
      accent: '#555555',
      accentForeground: '#ffffff',
      destructive: '#ff0000',
      destructiveForeground: '#ffffff',
      border: '#666666',
      input: '#777777',
      ring: '#888888',
    );

ThemeDefinition _themed({String? overlay}) => ThemeDefinition(
      light: _colors(),
      dark: _colors(),
      background: ThemeBackground(
        source: ThemeBackgroundSource.shell,
        overlay: overlay,
      ),
    );

/// A 1x1 transparent PNG: the painted-path tests need a decodable image
/// without touching the network or the asset bundle.
final _transparentPng = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 96, 0, 0, 0, 2, //
  0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

Future<void> _pumpLayer(
  WidgetTester tester, {
  required bool realTransparent,
  String? overlay,
  Completer<ThemeDefinition?>? liveGate,
  String? cachedOverlay,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeShellSourceProvider.overrideWithValue(_ShellSource()),
        themeDefinitionProvider.overrideWith(
          (ref) => liveGate?.future ?? Future.value(_themed(overlay: overlay)),
        ),
        // The layer and the gate fall back to the cached theme while live
        // reloads; the real cached provider needs SharedPreferences plus the
        // app logger, so hermetic tests pin it explicitly.
        cachedThemeDefinitionProvider.overrideWith(
          (ref) => Future.value(
            cachedOverlay == null && liveGate == null
                ? null
                : _themed(overlay: cachedOverlay ?? overlay),
          ),
        ),
        cachedThemeDefinitionProvider.overrideWith(
          (ref) => Future.value(
            cachedOverlay == null && liveGate == null
                ? null
                : _themed(overlay: cachedOverlay ?? overlay),
          ),
        ),
        realTransparencyActiveProvider.overrideWithValue(realTransparent),
        chromeBlurFrozen.overrideWithValue(false),
        themeBackgroundImageProvider.overrideWith((ref, side) => null),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: ThemeBackgroundLayer(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('real mode paints the adapted veil, never the image', (
    tester,
  ) async {
    await _pumpLayer(tester, realTransparent: true, overlay: '#80000000');

    final expected = ThemeConverter.adaptOverlayForBrightness(
      ThemeConverter.parseColor('#80000000'),
      Brightness.light,
    );
    final veil = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ThemeBackgroundLayer),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(veil.color, expected);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('real mode with no veil stays fully clear', (tester) async {
    await _pumpLayer(tester, realTransparent: true);

    expect(
      find.descendant(
        of: find.byType(ThemeBackgroundLayer),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('real mode with a malformed veil stays fully clear', (
    tester,
  ) async {
    await _pumpLayer(tester, realTransparent: true, overlay: 'not-a-color');

    expect(
      find.descendant(
        of: find.byType(ThemeBackgroundLayer),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });

  testWidgets('reloading theme keeps the cached veil (no black pop)', (
    tester,
  ) async {
    // Theme switch: the live definition is still loading while the cached
    // one holds the previous veil. The ground must keep painting instead of
    // blanking for the reload duration.
    final liveGate = Completer<ThemeDefinition?>();
    await _pumpLayer(
      tester,
      realTransparent: true,
      liveGate: liveGate,
      cachedOverlay: '#80000000',
    );

    final expected = ThemeConverter.adaptOverlayForBrightness(
      ThemeConverter.parseColor('#80000000'),
      Brightness.light,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(ThemeBackgroundLayer),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      expected,
    );
    expect(find.byType(Image), findsNothing);
    liveGate.complete(null);
    await tester.pump();
  });

  testWidgets('painted image holds its frame across wallpaper swaps', (
    tester,
  ) async {
    // Wallpaper switch: same theme, new image URL. gaplessPlayback keeps
    // the previous decode on screen until the new one lands instead of
    // blanking the ground (raw desktop flashing through unveiled).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_ShellSource()),
          themeDefinitionProvider.overrideWith(
            (ref) => Future.value(_themed(overlay: '#80000000')),
          ),
          realTransparencyActiveProvider.overrideWithValue(false),
          chromeBlurFrozen.overrideWithValue(false),
          themeBackgroundImageProvider.overrideWith(
            (ref, side) => MemoryImage(_transparentPng),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ThemeBackgroundLayer(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Image>(find.byType(Image)).gaplessPlayback,
      isTrue,
    );
  });
}
