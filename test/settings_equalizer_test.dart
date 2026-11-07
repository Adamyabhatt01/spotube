import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/pages/settings/equalizer.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

/// Keeps the page off the native audio backend in widget tests.
class _FakeVolumeNotifier extends VolumeProvider {
  @override
  double build() => 0.5;

  @override
  Future<void> setVolume(double volume) async {
    state = volume;
  }
}

/// Captures equalizer writes instead of hitting Drift.
class _RecordingPrefsNotifier extends StubPrefsNotifier {
  _RecordingPrefsNotifier(super.stub);

  List<double>? lastGains;
  EqualizerPreset? lastPreset;

  @override
  void setEqualizerGains(List<double> gains) {
    lastGains = List<double>.of(gains);
    stub = stub.copyWith(
      equalizerGains: EqualizerSettings.normalizeGains(gains),
      equalizerPreset: EqualizerPreset.custom,
    );
    state = stub;
  }

  @override
  void setEqualizerPreset(EqualizerPreset preset) {
    lastPreset = preset;
    final gains = equalizerGainsForPreset(
      preset,
      current: state.equalizerGains,
    );
    stub = stub.copyWith(
      equalizerGains: EqualizerSettings.normalizeGains(gains),
      equalizerPreset: preset,
    );
    state = stub;
  }
}

Future<_RecordingPrefsNotifier> _pumpPage(
  WidgetTester tester, {
  bool enabled = true,
  EqualizerPreset preset = EqualizerPreset.flat,
  List<double> gains = const [],
  Size surfaceSize = const Size(900, 1200),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final prefs = _RecordingPrefsNotifier(
    PreferencesTable.defaults().copyWith(
      equalizerEnabled: enabled,
      equalizerPreset: preset,
      equalizerGains: gains,
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userPreferencesProvider.overrideWith(() => prefs),
        volumeProvider.overrideWith(_FakeVolumeNotifier.new),
      ],
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: [Locale('en')],
        home: Scaffold(child: SettingsEqualizerView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  AppLogger.initialize(false);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  testWidgets('dragging a curve node persists the whole band set',
      (tester) async {
    final prefs = await _pumpPage(tester);

    await tester.drag(
      find.byKey(const ValueKey('equalizer-node-5')),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();

    expect(prefs.lastGains, isNotNull);
    expect(prefs.lastGains![5], greaterThan(0));
    expect(prefs.lastGains!.where((gain) => gain != 0), hasLength(1));
    expect(prefs.stub.equalizerPreset, EqualizerPreset.custom);
  });

  testWidgets('dragging works while the equalizer is bypassed', (tester) async {
    final prefs = await _pumpPage(tester, enabled: false);

    expect(find.text('Bypassed'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('equalizer-node-0')),
      const Offset(0, -30),
    );
    await tester.pumpAndSettle();

    expect(prefs.lastGains, isNotNull);
    expect(prefs.lastGains![0], greaterThan(0));
    expect(prefs.stub.equalizerEnabled, isFalse);
  });

  testWidgets('reset clears every band even while bypassed', (tester) async {
    final prefs = await _pumpPage(
      tester,
      enabled: false,
      preset: EqualizerPreset.bassBoost,
      gains: kEqualizerPresetGains[EqualizerPreset.bassBoost]!,
    );

    await tester.tap(find.byIcon(SpotubeIcons.refresh));
    await tester.pumpAndSettle();

    expect(prefs.lastPreset, EqualizerPreset.flat);
    expect(prefs.stub.equalizerPreset, EqualizerPreset.flat);
    expect(prefs.stub.equalizerGains, everyElement(0));
    expect(find.text('Bypassed'), findsOneWidget);
  });

  testWidgets('selecting a preset applies its complete gain table',
      (tester) async {
    final prefs = await _pumpPage(
      tester,
      preset: EqualizerPreset.flat,
      gains: List<double>.filled(kEqualizerBandCount, 0),
    );

    await tester.tap(
      find.byKey(const ValueKey('equalizer-preset-bassBoost')),
    );
    await tester.pumpAndSettle();

    expect(prefs.lastPreset, EqualizerPreset.bassBoost);
    expect(
      prefs.stub.equalizerGains,
      kEqualizerPresetGains[EqualizerPreset.bassBoost],
    );
  });

  testWidgets('a single click on a node does not rewrite the preset',
      (tester) async {
    final prefs = await _pumpPage(
      tester,
      preset: EqualizerPreset.rock,
      gains: kEqualizerPresetGains[EqualizerPreset.rock]!,
    );

    await tester.tap(find.byKey(const ValueKey('equalizer-node-5')));
    await tester.pumpAndSettle();

    expect(prefs.lastGains, isNull);
    expect(prefs.lastPreset, isNull);
    expect(prefs.stub.equalizerPreset, EqualizerPreset.rock);
  });

  testWidgets('double-clicking a node resets that band only', (tester) async {
    final prefs = await _pumpPage(
      tester,
      preset: EqualizerPreset.vocal,
      gains: kEqualizerPresetGains[EqualizerPreset.vocal]!,
    );

    final node = find.byKey(const ValueKey('equalizer-node-5'));
    await tester.tap(node);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(node);
    await tester.pumpAndSettle();

    expect(prefs.lastGains, isNotNull);
    expect(prefs.lastGains![5], 0);
    final expected = [...kEqualizerPresetGains[EqualizerPreset.vocal]!];
    expected[5] = 0;
    expect(prefs.lastGains, expected);
    expect(prefs.stub.equalizerPreset, EqualizerPreset.custom);
  });

  testWidgets('lays out on a phone-sized viewport without overflowing',
      (tester) async {
    await _pumpPage(
      tester,
      surfaceSize: const Size(390, 844),
      preset: EqualizerPreset.rock,
      gains: kEqualizerPresetGains[EqualizerPreset.rock]!,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('equalizer-node-0')), findsOneWidget);
    expect(find.text('Virtual surround'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
  });
}
