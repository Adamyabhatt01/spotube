// PR5: startup/reliability failure-path contracts.
//
// Locked behavior:
//  - Optional startup steps never fail startup ([startupGateAllowsApp],
//    guarded inits complete normally and attribute failures).
//  - Providers with async init expose it explicitly: loading -> ready,
//    or degraded (reported, still usable) — never permanent silent
//    defaults masquerading as success.
//  - Untrusted inputs (Caelestia scheme, theme numerics) degrade to null
//    or clamped values instead of throwing.
//
// Hermetic: databases are in-memory (or pre-closed to simulate failure),
// Caelestia reads from temp dirs, no media_kit, no network.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/main.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_theme_source.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/theme.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

class _SyncOnlyAudioNotifier extends AudioPlayerNotifier {
  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
      );
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

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('startupGateAllowsApp', () {
    test('themed frame releases immediately', () {
      expect(
        startupGateAllowsApp(
          themeReady: true,
          elapsed: Duration.zero,
        ),
        isTrue,
      );
    });

    test('waits while resolving under the cap', () {
      expect(
        startupGateAllowsApp(
          themeReady: false,
          elapsed: const Duration(seconds: 5, milliseconds: 999),
        ),
        isFalse,
      );
    });

    test('cap releases even on total theme failure (never hangs)', () {
      expect(
        startupGateAllowsApp(
          themeReady: false,
          elapsed: const Duration(seconds: 6),
        ),
        isTrue,
      );
      expect(
        startupGateAllowsApp(
          themeReady: false,
          elapsed: const Duration(minutes: 10),
        ),
        isTrue,
      );
    });
  });

  group('guarded startup inits', () {
    test('failure completes normally and is attributed', () async {
      Object? seenError;
      StackTrace? seenStack;
      var completed = false;

      await guardedStartupInit(
        'test-init',
        () async => throw StateError('backend down'),
        onError: (e, stack) async {
          seenError = e;
          seenStack = stack;
        },
      ).then((_) => completed = true);

      expect(completed, isTrue);
      expect(seenError, isStateError);
      expect(seenStack, isNotNull);
    });

    test('success runs without error callback', () async {
      var ran = false;
      var errored = false;
      await guardedStartupInit(
        'test-init',
        () async => ran = true,
        onError: (e, stack) async => errored = true,
      );
      expect(ran, isTrue);
      expect(errored, isFalse);
    });
  });

  group('userPreferences init status', () {
    test('seeded row loads to ready', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.into(database.preferencesTable).insert(
            PreferencesTableCompanion.insert(
              id: const Value(0),
              downloadLocation: const Value('test-dir'),
            ),
          );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          userPreferencesProvider.overrideWith(
            () => UserPreferencesNotifier(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      // Triggers build; load completes asynchronously.
      container.read(userPreferencesProvider);
      AsyncValue<void>? status;
      for (var i = 0; i < 100; i++) {
        status = container.read(userPreferencesStatusProvider);
        if (status is! AsyncLoading) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(status, isA<AsyncData<void>>());
      expect(
        container.read(userPreferencesProvider).downloadLocation,
        'test-dir',
      );
    });

    test('unreadable database degrades explicitly (no silent defaults)',
        () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.close();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          userPreferencesProvider.overrideWith(
            () => UserPreferencesNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(userPreferencesProvider);
      AsyncValue<void>? status;
      for (var i = 0; i < 100; i++) {
        status = container.read(userPreferencesStatusProvider);
        if (status is! AsyncLoading) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Degraded AND reported — but the app still has usable defaults.
      // (Field-wise: drift DataClass == compares list fields by identity,
      // so whole-object equality is not a stable assertion here.)
      expect(status, isA<AsyncError<void>>());
      final fallback = container.read(userPreferencesProvider);
      final modelDefaults = PreferencesTable.defaults();
      expect(fallback.id, modelDefaults.id);
      expect(fallback.downloadLocation, modelDefaults.downloadLocation);
      expect(fallback.themeMode, modelDefaults.themeMode);
    });
  });

  group('audioPlayer init status', () {
    test('restore failure degrades, queue stays usable', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.close();
      final notifier = _SyncOnlyAudioNotifier();
      final container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWith(() => notifier),
          databaseProvider.overrideWithValue(database),
        ],
      );
      addTearDown(container.dispose);

      container.read(audioPlayerProvider);
      await notifier.syncSavedState();

      final status = container.read(audioPlayerInitStatusProvider);
      expect(status, isA<AsyncError<void>>());
      expect(notifier.state.tracks, isEmpty);
    });
  });

  group('Caelestia theme source', () {
    test('missing state dir yields null (no shell installed)', () async {
      const source = CaelestiaThemeSource(
        stateDir: '/definitely/not/caelestia-state',
      );
      expect(await source.getTheme(), isNull);
    });

    test('malformed scheme yields null instead of throwing', () async {
      final dir = await Directory.systemTemp.createTemp('caelestia-bad');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/scheme.json').writeAsString('{nope');

      expect(
        await CaelestiaThemeSource(stateDir: dir.path).getTheme(),
        isNull,
      );
    });

    test('valid scheme maps roles mode-aware', () async {
      final dir = await Directory.systemTemp.createTemp('caelestia-good');
      addTearDown(() => dir.delete(recursive: true));
      const roles = {
        'background': '111111',
        'onBackground': 'eeeeee',
        'surface': '222222',
        'onSurface': 'dddddd',
        'primary': '333333',
        'onPrimary': 'cccccc',
        'secondary': '444444',
        'onSecondary': 'bbbbbb',
        'surfaceContainer': '555555',
        'onSurfaceVariant': 'aaaaaa',
        'tertiary': '666666',
        'onTertiary': '999999',
        'error': 'ff0000',
        'onError': 'ffffff',
        'outline': '777777',
        'outlineVariant': '888888',
      };
      await File('${dir.path}/scheme.json').writeAsString(
        jsonEncode({'mode': 'dark', 'colours': roles}),
      );

      final definition =
          await CaelestiaThemeSource(stateDir: dir.path).getTheme();
      expect(definition, isNotNull);
      // Active (dark) side comes from the shell file...
      expect(definition!.dark.background, '#111111');
      expect(definition.dark.primary, '#333333');
      // ...while the inactive side falls back to built-ins.
      expect(definition.light.background,
          builtInLightThemeColors().background);
    });
  });

  group('sanitizeThemeDefinition', () {
    test('clamps untrusted numerics to render-safe ranges', () {
      final sanitized = sanitizeThemeDefinition(
        ThemeDefinition(
          light: _colors('#ffffff'),
          dark: _colors('#000000'),
          surfaces: const ThemeSurfaces(opacity: 2.5, blur: -4.0),
          background: const ThemeBackground(opacity: -1.0, blur: -2.0),
          radius: const ThemeRadius(
              small: -1.0, medium: -2.0, large: -3.0, pill: -4.0),
          density: -3.0,
        ),
      );

      expect(sanitized.surfaces.opacity, 1.0);
      expect(sanitized.surfaces.blur, 0.0);
      expect(sanitized.background.opacity, 0.0);
      expect(sanitized.background.blur, 0.0);
      expect(sanitized.radius.small, 0.0);
      expect(sanitized.radius.medium, 0.0);
      expect(sanitized.radius.large, 0.0);
      expect(sanitized.radius.pill, 0.0);
      expect(sanitized.density, 1.0);
    });

    test('keeps in-range intent untouched', () {
      final sanitized = sanitizeThemeDefinition(
        ThemeDefinition(
          light: _colors('#ffffff'),
          dark: _colors('#000000'),
          surfaces: const ThemeSurfaces(opacity: 0.85, blur: 12.0),
          density: 1.25,
        ),
      );

      expect(sanitized.surfaces.opacity, 0.85);
      expect(sanitized.surfaces.blur, 12.0);
      expect(sanitized.density, 1.25);
    });
  });
}
