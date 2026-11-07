// Palette-transition contracts.
//
// The app already crossfades its theme — `ShadcnLayer` does it unconditionally
// at `shadcn_app.dart:659-661` of shadcn_flutter 0.0.47, on a hardcoded
// `kDefaultDuration` (150ms) with a linear curve, and `enableThemeAnimation` is
// accepted but never read. What this feature adds is *control* over that fade,
// from a nested `Theme` at the `ShadcnApp.builder` seam, so every test here is
// about who is in charge of the clock:
//   - off (Duration.zero) must be a true snap: no colour crossfade left over
//     from the package's own 150ms animation, including on inherited text;
//   - on must interpolate, land exactly on the target, and take the length the
//     preference says — not a constant that would pass either way;
//   - changing the length mid-fade must keep moving forward, never step back;
//   - the endpoint must be the same scaled palette the package would have shown,
//     for every ThemeMode x platform brightness, so switching the feature on can
//     neither resize the UI nor pick the wrong side;
//   - a palette-only change must not move surface blur/opacity, because those
//     feed `BackdropFilter` sigmas and re-rastering them is the costly part.
//
// Hermetic: in-memory drift, no media_kit, no network. The two migration tests
// use a throwaway temp file, because reopening the same database is the only
// way to drive drift's real `onUpgrade`.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/adaptive/adaptive_select_tile.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/palette_transition_scope.dart';
import 'package:spotube/pages/settings/sections/appearance.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/theme_converter.dart';

/// The two sides of a palette swap, differing in colour only — which is what a
/// shell sync or a plugin switch produces.
ThemeData _appTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  return ThemeData(
    colorScheme: ThemeConverter.toColorScheme(
      _colors(
        light ? '#ffffff' : '#0a0a0a',
        light ? '#111111' : '#eeeeee',
      ),
      brightness: brightness,
      // Every role the test's palette does not name falls back to the
      // built-in scheme, role by role.
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

final _lightBackground = _light.colorScheme.background;
final _darkBackground = _dark.colorScheme.background;
final _lightForeground = _light.colorScheme.foreground;
final _darkForeground = _dark.colorScheme.foreground;

ThemeColors _colors(String background, String foreground) => ThemeColors(
      background: background,
      foreground: foreground,
      card: background,
      cardForeground: foreground,
      primary: foreground,
      primaryForeground: background,
      secondary: background,
      secondaryForeground: foreground,
      muted: background,
      mutedForeground: foreground,
      accent: background,
      accentForeground: foreground,
      destructive: '#ff0000',
      destructiveForeground: background,
      border: background,
      input: background,
      ring: foreground,
    );

/// Read out of the tree on every build of the probed subtree. `ThemeData` here
/// is shadcn's: the barrel deliberately does not re-export Material's.
class _Palette {
  Color background = const Color.fromARGB(0, 0, 0, 0);
  Color foreground = const Color.fromARGB(0, 0, 0, 0);
  Color? textColor;
  double? scaling;
  double? blur;
  double? opacity;

  bool get onLight =>
      background == _lightBackground && foreground == _lightForeground;
  bool get onDark =>
      background == _darkBackground && foreground == _darkForeground;
}

class _Probe extends StatelessWidget {
  const _Probe({required this.out});

  final _Palette out;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    out
      ..background = theme.colorScheme.background
      ..foreground = theme.colorScheme.foreground
      ..textColor = DefaultTextStyle.of(context).style.color
      ..scaling = theme.scaling
      ..blur = theme.surfaceBlur
      ..opacity = theme.surfaceOpacity;
    return const SizedBox.shrink();
  }
}

/// The layering `Spotube.build` produces: `ShadcnApp` with its own 150ms theme
/// animation, and the scope installed at the `builder:` seam underneath it.
Widget _harness({
  required ThemeMode themeMode,
  required Brightness brightness,
  required Duration duration,
  required _Palette out,
  AdaptiveScaling scaling = const AdaptiveScaling.only(),
}) {
  return ShadcnApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    scaling: scaling,
    theme: _light,
    darkTheme: _dark,
    themeMode: themeMode,
    builder: (context, child) => PaletteTransitionScope(
      theme: _light,
      darkTheme: _dark,
      scaling: scaling,
      brightness: brightness,
      duration: duration,
      child: _Probe(out: out),
    ),
    home: const SizedBox.shrink(),
  );
}

/// Summed 8-bit channel distance, used to tell "2/3 of the way there" from
/// "barely started" without betting on floating-point equality.
int _distance(Color a, Color b) {
  final x = a.toARGB32();
  final y = b.toARGB32();
  int channel(int value, int shift) => (value >> shift) & 0xFF;
  var total = 0;
  for (final shift in [8, 16, 24]) {
    total += (channel(x, shift) - channel(y, shift)).abs();
  }
  return total;
}

/// Polls [done] until it returns true or the deadline passes, then fails.
Future<void> eventually(
  bool Function() done,
  String what, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (!done()) fail('$what did not happen within $budget');
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  group('resolveThemeTransition', () {
    test('off is Duration.zero whatever the stored length says', () {
      expect(resolveThemeTransition(false, 250), Duration.zero);
      expect(resolveThemeTransition(false, 1000), Duration.zero);
    });

    test('on clamps into a range where a fade is meaningful', () {
      expect(
        resolveThemeTransition(true, 250),
        const Duration(milliseconds: 250),
      );
      expect(
        resolveThemeTransition(true, -5),
        const Duration(milliseconds: 50),
      );
      expect(
        resolveThemeTransition(true, 0),
        const Duration(milliseconds: 50),
      );
      expect(
        resolveThemeTransition(true, 999999),
        const Duration(milliseconds: 2000),
      );
    });
  });

  group('off snaps', () {
    testWidgets('a mode flip lands in one frame, no leftover crossfade', (
      tester,
    ) async {
      final palette = _Palette();
      final light = _harness(
        themeMode: ThemeMode.light,
        brightness: Brightness.light,
        duration: Duration.zero,
        out: palette,
      );
      final dark = _harness(
        themeMode: ThemeMode.dark,
        brightness: Brightness.dark,
        duration: Duration.zero,
        out: palette,
      );

      await tester.pumpWidget(light);
      expect(palette.onLight, isTrue);

      await tester.pumpWidget(dark);
      await tester.pump(const Duration(milliseconds: 50));

      expect(palette.onDark, isTrue);
      // The package's own tween is still mid-flight at +50ms; if its inherited
      // text colour reached the probe, "off" would only be half off.
      expect(palette.textColor, _darkForeground);
    });

    test('an identical re-read is not a second animation source', () {
      // What the scope is handed is one ThemeData per resolve, so the freezed
      // equality that keeps a repeated scheme file read quiet has to hold.
      expect(_dark, _appTheme(Brightness.dark));
      expect(ThemeData.lerp(_dark, _appTheme(Brightness.dark), .5), _dark);
    });
  });

  group('on fades', () {
    testWidgets('interpolates mid-flight and converges exactly',
        (tester) async {
      final palette = _Palette();
      Widget app(ThemeMode mode, Brightness brightness) => _harness(
            themeMode: mode,
            brightness: brightness,
            duration: const Duration(milliseconds: 250),
            out: palette,
          );

      await tester.pumpWidget(app(ThemeMode.light, Brightness.light));
      await tester.pumpWidget(app(ThemeMode.dark, Brightness.dark));

      await tester.pump(const Duration(milliseconds: 100));
      expect(palette.onLight, isFalse);
      expect(palette.onDark, isFalse);

      await tester.pumpAndSettle();
      expect(palette.onDark, isTrue);
    });

    testWidgets('the stored length is what sets the pace', (tester) async {
      final palette = _Palette();
      Widget app(Brightness brightness) => _harness(
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            brightness: brightness,
            duration: const Duration(milliseconds: 100),
            out: palette,
          );

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pump(const Duration(milliseconds: 300));

      expect(palette.onDark, isTrue, reason: 'a 0.1s fade is over by +300ms');
    });

    testWidgets('a longer stored length is still fading at +300ms', (
      tester,
    ) async {
      final palette = _Palette();
      Widget app(Brightness brightness) => _harness(
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            brightness: brightness,
            duration: const Duration(seconds: 1),
            out: palette,
          );

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pump(const Duration(milliseconds: 300));

      expect(palette.onDark, isFalse, reason: 'a 1s fade is still running');
      await tester.pumpAndSettle();
      expect(palette.onDark, isTrue);
    });

    testWidgets('an identical re-resolve does not restart the fade', (
      tester,
    ) async {
      final palette = _Palette();
      Widget app(ThemeMode mode) => _harness(
            themeMode: mode,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
            duration: const Duration(milliseconds: 250),
            out: palette,
          );

      await tester.pumpWidget(app(ThemeMode.light));
      await tester.pumpWidget(app(ThemeMode.dark));
      await tester.pump(const Duration(milliseconds: 100));

      // A rebuild that produces an equal theme in a fresh instance: what an
      // unrelated preference write does to `Spotube.build`.
      await tester.pumpWidget(app(ThemeMode.dark));
      await tester.pump(const Duration(milliseconds: 200));

      // 300ms into a 250ms fade. Had the tween restarted at +100ms, the probe
      // would still fall short here.
      expect(palette.onDark, isTrue);
    });

    testWidgets('changing the length mid-fade keeps moving forward', (
      tester,
    ) async {
      final palette = _Palette();
      Widget app({
        required Brightness brightness,
        required Duration duration,
      }) =>
          _harness(
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            brightness: brightness,
            duration: duration,
            out: palette,
          );

      await tester.pumpWidget(
        app(brightness: Brightness.light, duration: Duration.zero),
      );
      expect(palette.onLight, isTrue);
      await tester.pumpWidget(
        app(
          brightness: Brightness.light,
          duration: const Duration(milliseconds: 250),
        ),
      );
      await tester.pumpWidget(
        app(
          brightness: Brightness.dark,
          duration: const Duration(milliseconds: 250),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final before = palette.background;

      await tester.pumpWidget(
        app(brightness: Brightness.dark, duration: const Duration(seconds: 1)),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(palette.background, isNot(before));
      expect(palette.onDark, isFalse);
      expect(
        _distance(palette.background, _darkBackground),
        lessThan(_distance(before, _darkBackground)),
      );
      expect(
        _distance(palette.background, _lightBackground),
        greaterThan(_distance(before, _lightBackground)),
      );

      await tester.pumpAndSettle();
      expect(palette.onDark, isTrue);
    });

    testWidgets('inherited text follows this clock, not the package 150ms one',
        (
      tester,
    ) async {
      final palette = _Palette();
      Widget app(Brightness brightness) => _harness(
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            brightness: brightness,
            duration: const Duration(milliseconds: 1000),
            out: palette,
          );

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpWidget(app(Brightness.dark));
      await tester.pump(const Duration(milliseconds: 100));

      // At +100ms the package's clock is 2/3 of the way to the new foreground
      // while ours has barely started, so whichever one the merged
      // DefaultTextStyle came from is decided by distance alone.
      final text = palette.textColor!;
      expect(
        _distance(text, _lightForeground),
        lessThan(_distance(text, _darkForeground)),
      );
      expect(text, palette.foreground);

      await tester.pumpAndSettle();
      expect(palette.textColor, _darkForeground);
    });

    testWidgets('blur and opacity do not move during the fade', (tester) async {
      final palette = _Palette();
      Widget app(Brightness brightness) => _harness(
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            brightness: brightness,
            duration: const Duration(milliseconds: 1000),
            out: palette,
          );

      await tester.pumpWidget(app(Brightness.light));
      await tester.pumpWidget(app(Brightness.dark));

      for (var step = 1; step <= 6; step++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(palette.blur, 12, reason: 'sigma moved at step $step');
        expect(palette.opacity, .8, reason: 'opacity moved at step $step');
      }
      expect(palette.onDark, isFalse);
    });

    test('a palette-only lerp keeps the surface sigmas constant', () {
      final mid = ThemeData.lerp(_light, _dark, .5);
      expect(mid.surfaceBlur, _light.surfaceBlur);
      expect(mid.surfaceOpacity, _light.surfaceOpacity);
    });
  });

  group('the endpoint is the palette the package would have shown', () {
    testWidgets('every ThemeMode x platform brightness resolves to one side', (
      tester,
    ) async {
      for (final platform in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = platform;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        for (final mode in ThemeMode.values) {
          final brightness = switch (mode) {
            ThemeMode.light => Brightness.light,
            ThemeMode.dark => Brightness.dark,
            ThemeMode.system => platform,
          };
          final expected = brightness == Brightness.dark
              ? _darkBackground
              : _lightBackground;
          final palette = _Palette();

          await tester.pumpWidget(
            _harness(
              themeMode: mode,
              brightness: brightness,
              duration: Duration.zero,
              out: palette,
            ),
          );
          await tester.pump();

          expect(
            palette.background,
            expected,
            reason: '$mode on a $platform platform',
          );
        }
      }
    });

    testWidgets('density is applied to the animated theme', (tester) async {
      final palette = _Palette();
      await tester.pumpWidget(
        _harness(
          themeMode: ThemeMode.light,
          brightness: Brightness.light,
          duration: Duration.zero,
          out: palette,
          scaling: const AdaptiveScaling.only(
            sizeScaling: 1.25,
            textScaling: 1.25,
          ),
        ),
      );
      await tester.pump();

      // Handing the scope the raw theme instead would resize the whole UI the
      // moment the toggle is switched on.
      expect(palette.scaling, 1.25);
    });
  });

  group('preferences', () {
    test('the feature ships off at 250ms', () {
      final defaults = PreferencesTable.defaults();
      expect(defaults.themeTransition, isFalse);
      expect(defaults.themeTransitionMs, 250);
    });

    test('setters round-trip through the real notifier and drift', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.into(database.preferencesTable).insert(
            PreferencesTableCompanion.insert(
              id: const Value(0),
              downloadLocation: const Value('test-dir'),
            ),
          );
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      // The seeded row took the column defaults, not just the Dart ones.
      final seeded = await (database.select(database.preferencesTable)
            ..where((t) => t.id.equals(0)))
          .getSingle();
      expect(seeded.themeTransition, isFalse);
      expect(seeded.themeTransitionMs, 250);

      container.read(userPreferencesProvider);
      final notifier = container.read(userPreferencesProvider.notifier);

      notifier.setThemeTransition(true);
      await eventually(
        () => container.read(userPreferencesProvider).themeTransition,
        'themeTransition write to reach state',
      );

      notifier.setThemeTransitionMs(600);
      await eventually(
        () => container.read(userPreferencesProvider).themeTransitionMs == 600,
        'themeTransitionMs write to reach state',
      );

      final row = await (database.select(database.preferencesTable)
            ..where((t) => t.id.equals(0)))
          .getSingle();
      expect(row.themeTransition, isTrue);
      expect(row.themeTransitionMs, 600);
    });

    test('v14 -> v15 adds both columns without losing the row', () async {
      // Real users are at v14 with data in it, so `m.addColumn` is the only
      // path these defaults travel — the Dart-side `defaults()` never runs.
      // SQLite rejects a NOT NULL ADD COLUMN that arrives without a usable
      // default, so a missing one would break the app on the user's next
      // launch instead of here.
      final directory =
          await Directory.systemTemp.createTemp('spotube-v14-migration');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/db.sqlite';

      final created = AppDatabase.forTesting(NativeDatabase(File(path)));
      await created.into(created.preferencesTable).insert(
            PreferencesTableCompanion.insert(
              id: const Value(0),
              downloadLocation: const Value('test-dir'),
            ),
          );
      // Nothing else in this migration touches the two columns, so dropping
      // them reproduces the shipped v14 shape exactly.
      await created.customStatement(
        'ALTER TABLE preferences_table DROP COLUMN theme_transition',
      );
      await created.customStatement(
        'ALTER TABLE preferences_table DROP COLUMN theme_transition_ms',
      );
      await created.customStatement('PRAGMA user_version = 14');
      await created.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(upgraded.close);
      // Reading is enough to prove the migration ran: drift opens the database
      // and applies onUpgrade before the first statement, and a column the
      // schema is missing would surface here as a drift error.
      final migrated = await (upgraded.select(upgraded.preferencesTable)
            ..where((t) => t.id.equals(0)))
          .getSingle();

      expect(migrated.downloadLocation, 'test-dir');
      expect(migrated.themeTransition, isFalse);
      expect(migrated.themeTransitionMs, 250);
    });

    test('re-running v14 -> v15 on columns that already exist is a no-op',
        () async {
      // `user_version` only moves after the strategy returns, so a process
      // killed mid-migration comes back at v14 with one or both columns
      // already added. An unguarded ALTER would throw "duplicate column name"
      // on every launch after that and the database would never open again.
      final directory =
          await Directory.systemTemp.createTemp('spotube-v15-reentry');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/db.sqlite';

      final created = AppDatabase.forTesting(NativeDatabase(File(path)));
      await created.customStatement('PRAGMA user_version = 14');
      await created.close();

      final reopened = AppDatabase.forTesting(NativeDatabase(File(path)));
      addTearDown(reopened.close);
      final survived = await (reopened.select(reopened.preferencesTable)
            ..where((t) => t.id.equals(0)))
          .getSingleOrNull();

      // No throw, and the schema still holds exactly one of each column.
      expect(survived, isNull);
      final columns = await reopened
          .customSelect(
            'PRAGMA table_info(preferences_table)',
          )
          .get();
      expect(
        columns
            .where((row) => row.read<String>('name') == 'theme_transition')
            .length,
        1,
      );
      expect(
        columns
            .where((row) => row.read<String>('name') == 'theme_transition_ms')
            .length,
        1,
      );
    });
  });

  group('Settings > Appearance', () {
    Future<void> pumpSection(
      WidgetTester tester,
      UserPreferencesNotifier stub, {
      ThemeUiDocument? themeSettings,
    }) async {
      SharedPreferences.setMockInitialValues({});
      // The section is a plain Column, so the default 800x600 test surface
      // reports an overflow that has nothing to do with what is asserted here.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          userPreferencesProvider.overrideWith(() => stub),
          // The section probes whether the active theme answers
          // `showSettings()`. The real future builds the Hetu plugin VM, which
          // completes after this test's container is already gone, so the test
          // hands it the document the plugin would have returned.
          pluginThemeSettingsProvider
              .overrideWith((ref) async => themeSettings),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ShadcnApp(
            localizationsDelegates: [AppLocalizations.delegate],
            home: SettingsAppearanceSection(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the duration row exists only while the transition is on', (
      tester,
    ) async {
      await pumpSection(tester, _StubPrefs(enabled: false));
      expect(find.text('Theme transition'), findsOneWidget);
      expect(find.text('Transition duration'), findsNothing);

      await pumpSection(tester, _StubPrefs(enabled: true));
      expect(find.text('Theme transition'), findsOneWidget);
      expect(find.text('Transition duration'), findsOneWidget);
      // The stored length is what the select shows, and it is one of the six
      // offered values rather than a free-number field.
      expect(
        tester
            .widgetList<AdaptiveSelectTile<int>>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is AdaptiveSelectTile<int> && widget.value == 250,
              ),
            )
            .length,
        1,
      );
    });

    testWidgets('a theme with settings earns an entry, an empty one does not', (
      tester,
    ) async {
      await pumpSection(tester, _StubPrefs(enabled: false));
      expect(find.text('Theme settings'), findsNothing);

      await pumpSection(
        tester,
        _StubPrefs(enabled: false),
        themeSettings: const ThemeUiDocument(
          specVersion: 4,
          slots: {
            'settings.content': ThemeUiSlot(
              children: [
                {'type': 'text', 'text': 'a setting'},
              ],
            ),
          },
        ),
      );
      expect(find.text('Theme settings'), findsOneWidget);
    });
  });
}

/// Drives the real setter shapes without a database: the section only reads the
/// two fields and calls the two setters.
class _StubPrefs extends UserPreferencesNotifier {
  _StubPrefs({required bool enabled})
      : _data = PreferencesTable.defaults().copyWith(
          themeTransition: enabled,
          themeTransitionMs: 250,
        );

  PreferencesTableData _data;

  @override
  PreferencesTableData build() => _data;

  @override
  void setThemeTransition(bool enabled) {
    _data = _data.copyWith(themeTransition: enabled);
    state = _data;
  }

  @override
  void setThemeTransitionMs(int milliseconds) {
    _data = _data.copyWith(themeTransitionMs: milliseconds);
    state = _data;
  }
}
