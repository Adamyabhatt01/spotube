import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';
import 'package:spotube/services/theme_definition_cache.dart';

import 'support/common_fakes.dart';

/// Plugin-driven contract for `background.transparent`:
/// - `true`: the theme requests real transparency; active only while the
///   user allows it (the `transparentWindow` opt-out) on Linux past load;
/// - `false`: explicit veto, always opaque;
/// - absent (or malformed): no opinion means opaque — only an explicit
///   request unlocks the compositor (strict; old themes stay fake until
///   flagged);
/// - no theme plugin at all: opaque stock (real transparency is a theme
///   feature).
void main() {
  ThemeBackground decode(Map<String, dynamic> background) =>
      ThemeBackground.fromJson(background);

  group('decode', () {
    test('true stays true, false stays false', () {
      expect(decode({'transparent': true}).transparent, isTrue);
      expect(decode({'transparent': false}).transparent, isFalse);
    });

    test('absent reads as no opinion', () {
      expect(decode({}).transparent, isNull);
    });

    test('malformed reads as no opinion, never throws', () {
      for (final bad in ['yes', 1, 0, [], {}]) {
        expect(
          decode({'transparent': bad}).transparent,
          isNull,
          reason: 'input: $bad',
        );
      }
    });
  });

  group('sanitizer', () {
    test('passes the tri-state through untouched', () {
      for (final value in [true, false, null]) {
        final sanitized = sanitizeThemeDefinition(
          ThemeDefinition(
            light: _colors(),
            dark: _colors(),
            background: ThemeBackground(
              source: ThemeBackgroundSource.none,
              transparent: value,
            ),
          ),
        );
        expect(sanitized.background.transparent, value);
      }
    });
  });

  group('predicate', () {
    Future<bool> predicate({
      required bool allow,
      bool? transparent,
      bool themeNull = false,
      bool neverLoads = false,
      ThemeDefinition? cachedTheme,
    }) async {
      final db = newMemoryDatabase();
      final gate = Completer<ThemeDefinition?>();
      ThemeDefinition? themed;
      if (!themeNull && !neverLoads) {
        themed = ThemeDefinition(
          light: _colors(),
          dark: _colors(),
          background: ThemeBackground(
            source: ThemeBackgroundSource.none,
            transparent: transparent,
          ),
        );
      }
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userPreferencesProvider.overrideWith(
            () => StubPrefsNotifier(
              PreferencesTable.defaults().copyWith(transparentWindow: allow),
            ),
          ),
          themeDefinitionProvider.overrideWith(
            (ref) => neverLoads ? gate.future : Future.value(themed),
          ),
          // The gate falls back to the cached flag while live reloads; the
          // real cached provider needs SharedPreferences plus the app
          // logger, so hermetic tests pin it explicitly (null = cold start
          // unless a case passes a cached theme).
          cachedThemeDefinitionProvider.overrideWith(
            (ref) => Future.value(cachedTheme),
          ),
          cachedThemeDefinitionProvider.overrideWith(
            (ref) => Future.value(cachedTheme),
          ),
        ],
      );
      try {
        if (!neverLoads) {
          // Settle the overridden future first: a synchronous first read
          // still sees AsyncLoading, which the predicate reads as opaque.
          await c.read(themeDefinitionProvider.future);
        }
        await c.read(cachedThemeDefinitionProvider.future);
        final active = c.read(realTransparencyActiveProvider);
        if (neverLoads) gate.complete(themed);
        return active;
      } finally {
        c.dispose();
        await db.close();
      }
    }

    ThemeDefinition cachedDef({bool? transparent}) => ThemeDefinition(
          light: _colors(),
          dark: _colors(),
          background: ThemeBackground(
            source: ThemeBackgroundSource.none,
            transparent: transparent,
          ),
        );

    test('explicit request + allow means transparent', () async {
      expect(
        await predicate(allow: true, transparent: true),
        isTrue,
      );
    });

    test('explicit request + user veto means opaque', () async {
      expect(
        await predicate(allow: false, transparent: true),
        isFalse,
      );
    });

    test('explicit veto wins over allow', () async {
      expect(
        await predicate(allow: true, transparent: false),
        isFalse,
      );
    });

    test('absent flag stays opaque even when allowed (strict)', () async {
      expect(
        await predicate(allow: true, transparent: null),
        isFalse,
      );
    });

    test('absent flag + veto means opaque', () async {
      expect(
        await predicate(allow: false, transparent: null),
        isFalse,
      );
    });

    test('no theme plugin means opaque stock even when allowed', () async {
      expect(
        await predicate(allow: true, themeNull: true),
        isFalse,
      );
    });

    test('loading theme means opaque until resolved', () async {
      expect(
        await predicate(allow: true, transparent: true, neverLoads: true),
        isFalse,
      );
    });

    test('reloading theme keeps the cached flag (no opaque blip)', () async {
      // Theme switch: live still loading, cache holds an explicit request.
      expect(
        await predicate(
          allow: true,
          transparent: true,
          neverLoads: true,
          cachedTheme: cachedDef(transparent: true),
        ),
        isTrue,
      );
    });

    test('reloading theme keeps the cached veto', () async {
      expect(
        await predicate(
          allow: true,
          transparent: true,
          neverLoads: true,
          cachedTheme: cachedDef(transparent: false),
        ),
        isFalse,
      );
    });

    test('reloading with no cache stays opaque', () async {
      expect(
        await predicate(
          allow: true,
          transparent: true,
          neverLoads: true,
          cachedTheme: null,
        ),
        isFalse,
      );
    });
  });
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
