// Backdrop decode sizing: the image cache key includes the decode size, so
// backdrops quantize the viewport into fixed bands instead of decoding per
// pixel of resizing. These pin the rounding rule shared by the theme
// background, the track page and the artist footer.
//
// The second group pins who is allowed to paint one at all: the shell glass is
// a Caelestia behavior, so nothing downstream of the backdrop gate — the
// transparent scaffold ground, the sidebar's heading fill, the title bar — may
// switch off for a theme the user chose themselves.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/theme_definition_cache.dart';


void main() {
  test('non-positive sides fall back to one step', () {
    expect(quantizeBackdropSide(0), 256);
    expect(quantizeBackdropSide(-100), 256);
  });

  test('sides round up to the step', () {
    expect(quantizeBackdropSide(100), 256);
    expect(quantizeBackdropSide(256), 256);
    expect(quantizeBackdropSide(300), 512);
    expect(quantizeBackdropSide(908), 1024);
  });

  test('desktop viewports stay in whole steps', () {
    expect(quantizeBackdropSide(1920), 2048);
    expect(quantizeBackdropSide(1828), 2048);
  });

  test('custom steps are honored', () {
    expect(quantizeBackdropSide(300, step: 100), 300);
    expect(quantizeBackdropSide(301, step: 100), 400);
  });

  group('backdrop gate', () {
    test('a shell-sourced backdrop with a wallpaper paints', () async {
      expect(await _backdropActive(shellPath: '/wall.png'), isTrue);
    });

    test('a shell-sourced backdrop on a desktop with no wallpaper does not',
        () async {
      expect(await _backdropActive(shellPath: null), isFalse);
    });

    test('a theme that frosts its own album art paints no backdrop', () async {
      // The transparent scaffold ground exists to show the desktop through.
      // Turning it on for a plugin the user picked themselves would switch
      // off the chrome fill of every page for a backdrop that never renders.
      expect(
        await _backdropActive(
          source: ThemeBackgroundSource.albumArt,
          shellPath: '/wall.png',
        ),
        isFalse,
      );
    });

    test('a theme with no backdrop does not', () async {
      expect(
        await _backdropActive(
          source: ThemeBackgroundSource.none,
          shellPath: '/wall.png',
        ),
        isFalse,
      );
    });
  });

  group('reload fallback', () {
    test('a reloading theme keeps the cached backdrop source', () async {
      // Theme switch: the live definition is still loading while the cache
      // holds the previous shell source. The backdrop must stay active
      // instead of dropping the transparent scaffold for an opaque one.
      final liveGate = Completer<ThemeDefinition?>();
      final container = ProviderContainer(
        overrides: [
          themeShellSourceProvider.overrideWithValue(_ShellSource('/wall.png')),
          themeDefinitionProvider.overrideWith((ref) => liveGate.future),
          cachedThemeDefinitionProvider.overrideWith(
            (ref) => Future.value(
              ThemeDefinition(
                light: _colors('#ffffff'),
                dark: _colors('#000000'),
                background: const ThemeBackground(
                  source: ThemeBackgroundSource.shell,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(cachedThemeDefinitionProvider.future);
      expect(container.read(themeBackdropActiveProvider), isTrue);
      liveGate.complete(null);
    });
  });
}

class _ShellSource extends ThemeShellSource {
  _ShellSource(this.path);

  final String? path;

  @override
  String? getBackgroundPath() => path;

  @override
  Future<ThemeDefinition?> getTheme() async => null;
}

ThemeColors _colors(String fill) => ThemeColors(
      background: fill,
      foreground: fill,
      card: fill,
      cardForeground: fill,
      primary: fill,
      primaryForeground: fill,
      secondary: fill,
      secondaryForeground: fill,
      muted: fill,
      mutedForeground: fill,
      accent: fill,
      accentForeground: fill,
      destructive: fill,
      destructiveForeground: fill,
      border: fill,
      input: fill,
      ring: fill,
    );

/// Reads the one predicate the scope, the sidebar and the title bar all share,
/// for a theme of [source] on a shell whose wallpaper resolves to [shellPath].
Future<bool> _backdropActive({
  ThemeBackgroundSource source = ThemeBackgroundSource.shell,
  String? shellPath,
}) async {
  final container = ProviderContainer(
    overrides: [
      themeShellSourceProvider.overrideWithValue(_ShellSource(shellPath)),
      themeDefinitionProvider.overrideWith(
        (ref) => Future.value(
          ThemeDefinition(
            light: _colors('#ffffff'),
            dark: _colors('#000000'),
            background: ThemeBackground(source: source),
          ),
        ),
      ),
      // The url provider falls back to the cached theme while live reloads;
      // hermetic tests pin it explicitly (the real one needs SharedPreferences
      // plus the app logger, neither of which exists in a bare container).
      cachedThemeDefinitionProvider.overrideWith(
        (ref) => Future.value(null),
      ),
    ],
  );
  addTearDown(container.dispose);

  // The gate reads the definition off `asData`, so it settles only once the
  // theme future has landed.
  await container.read(themeDefinitionProvider.future);
  return container.read(themeBackdropActiveProvider);
}
