// Phase 7: audio capabilities.
//
// A theme reaches the mpv effects layer through an explicit verb, and every
// argument is clamped here — a plugin cannot arm an absurd sleep timer or push
// playback speed to a value that warps audio. These tests pin the host's half:
// the action gate accepts the verbs, the handlers write the right band/flag,
// and the `audio.*` bindings read the live values instead of the old stubs.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_demand.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/crossfade_duration_provider.dart';
import 'package:spotube/provider/sleep_timer_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart' as port;
import 'package:spotube/services/kv_store/kv_store.dart';

/// A player that records the audio calls a theme makes and replays a rate
/// stream. Everything the Phase 7 path does not touch falls through
/// [noSuchMethod], so the fake never has to model the whole transport.
class _FakePort implements port.AudioPlayerPort {
  _FakePort({this.currentSpeed = 1.0});

  double currentSpeed;
  double? lastSetVolume;
  double? lastSetSpeed;
  final _speed = StreamController<double>.broadcast();

  @override
  double get speed => currentSpeed;

  @override
  Stream<double> get speedStream => _speed.stream;

  @override
  Future<void> setSpeed(double speed) async {
    lastSetSpeed = speed;
    currentSpeed = speed;
    _speed.add(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    lastSetVolume = volume;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records the effect writes a theme triggers, without touching drift or the
/// real mpv chain.
class _RecordingPrefs extends UserPreferencesNotifier {
  _RecordingPrefs(PreferencesTableData stub) : _stub = stub;

  PreferencesTableData _stub;
  final gainWrites = <int, double>{};
  final enableCalls = <bool>[];
  final normalizeCalls = <bool>[];

  PreferencesTableData get stub => _stub;

  @override
  PreferencesTableData build() => _stub;

  @override
  void setEqualizerEnabled(bool enabled) {
    enableCalls.add(enabled);
    _stub = _stub.copyWith(equalizerEnabled: enabled);
    state = _stub;
  }

  @override
  void setEqualizerGain(int index, double gain) {
    gainWrites[index] = gain;
  }

  @override
  void setNormalizeAudio(bool normalize) {
    normalizeCalls.add(normalize);
    _stub = _stub.copyWith(normalizeAudio: normalize);
    state = _stub;
  }
}

/// Captures sleep-timer commands instead of arming a real shutdown timer,
/// which would leave a pending [Timer] at the end of the widget test.
class _RecordingSleep extends SleepTimerNotifier {
  Duration? armed;
  int cancels = 0;

  @override
  void setSleepTimer(Duration duration) => armed = duration;

  @override
  void cancelSleepTimer() => cancels++;
}

class _StubSleep extends SleepTimerNotifier {
  _StubSleep(Duration? value) {
    state = value;
  }
}

typedef _Harness = ({
  ProviderContainer container,
  WidgetRef ref,
  BuildContext context,
});

Future<_Harness> _pump(
  WidgetTester tester,
  List<Override> overrides,
) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  late BuildContext capturedContext;
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        home: AppLayout(
          layout: const ThemeLayout(),
          child: Consumer(
            builder: (context, ref, _) {
              capturedContext = context;
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (container: container, ref: capturedRef, context: capturedContext);
}

void main() {
  group('action allowlist', () {
    test('the audio verbs and the page verbs reach the dispatcher', () {
      for (final type in const [
        'setBass',
        'setTreble',
        'setNormalization',
        'setCrossfade',
        'setSleepTimer',
        'setSpeed',
        'setMuted',
        'playCollection',
        'openPage',
        'closePage',
      ]) {
        expect(
          ThemeUiAction.knownTypes,
          contains(type),
          reason: '$type must be dispatched from a node',
        );
        final parsed = ThemeUiAction.tryParse({
          'type': type,
          'args': {'value': 1},
        });
        expect(parsed?.type, type);
      }
    });

    test('an unknown verb still never reaches the dispatcher', () {
      expect(ThemeUiAction.tryParse({'type': 'deleteEverything'}), isNull);
      expect(ThemeUiAction.knownTypes, isNot(contains('notARealVerb')));
    });
  });

  group('equalizer actions', () {
    testWidgets('setBass writes band 0 and enables a disabled equalizer',
        (tester) async {
      final prefs = _RecordingPrefs(
        PreferencesTable.defaults().copyWith(
          equalizerEnabled: false,
          normalizeAudio: true,
        ),
      );
      final h = await _pump(tester, [
        userPreferencesProvider.overrideWith(() => prefs),
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setBass', {'value': 6.0}),
      );

      expect(prefs.gainWrites, {0: 6.0});
      expect(prefs.enableCalls, [true], reason: 'EQ must be audible');
      expect(prefs.normalizeCalls, isEmpty, reason: 'normalization untouched');
      expect(prefs.stub.normalizeAudio, isTrue);
    });

    testWidgets('setTreble writes the last band without re-enabling',
        (tester) async {
      final prefs = _RecordingPrefs(
        PreferencesTable.defaults().copyWith(equalizerEnabled: true),
      );
      final h = await _pump(tester, [
        userPreferencesProvider.overrideWith(() => prefs),
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setTreble', {'value': -3.5}),
      );

      expect(prefs.gainWrites, {kEqualizerBandCount - 1: -3.5});
      expect(prefs.enableCalls, isEmpty);
    });

    testWidgets('gains clamp to ±12 dB and reject junk', (tester) async {
      final prefs = _RecordingPrefs(
        PreferencesTable.defaults().copyWith(equalizerEnabled: true),
      );
      final h = await _pump(tester, [
        userPreferencesProvider.overrideWith(() => prefs),
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setBass', {'value': 900}),
      );
      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setBass', {'value': 'loud'}),
      );
      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setBass', {'value': double.nan}),
      );

      expect(prefs.gainWrites, {0: kEqualizerMaxGain});
      expect(prefs.enableCalls, isEmpty, reason: 'junk must not enable EQ');
    });

    testWidgets('setNormalization sets the flag from a bool', (tester) async {
      final prefs = _RecordingPrefs(
        PreferencesTable.defaults().copyWith(normalizeAudio: false),
      );
      final h = await _pump(tester, [
        userPreferencesProvider.overrideWith(() => prefs),
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setNormalization', {'value': true}),
      );

      expect(prefs.normalizeCalls, [true]);
      expect(prefs.stub.normalizeAudio, isTrue);
    });
  });

  group('playback-rate, crossfade and sleep actions', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await KVStoreService.initialize();
    });

    testWidgets('setSpeed clamps to a followable range', (tester) async {
      final fake = _FakePort();
      final h = await _pump(
          tester, [audioPlayerPortProvider.overrideWithValue(fake)]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSpeed', {'value': 12}),
      );
      expect(fake.lastSetSpeed, 4.0);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSpeed', {'value': 0.01}),
      );
      expect(fake.lastSetSpeed, 0.25);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSpeed', {'value': 'fast'}),
      );
      expect(fake.lastSetSpeed, 0.25, reason: 'junk must not change speed');
    });

    testWidgets('setMuted silences then restores the audible level',
        (tester) async {
      final fake = _FakePort();
      final h = await _pump(
          tester, [audioPlayerPortProvider.overrideWithValue(fake)]);

      // volumeProvider.build sets the stored volume (1.0) on first read.
      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setMuted', {'value': true}),
      );
      expect(fake.lastSetVolume, 0);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setMuted', {'value': false}),
      );
      expect(fake.lastSetVolume, 1.0);
    });

    testWidgets('setCrossfade clamps to 0–15 s and persists', (tester) async {
      final h = await _pump(tester, [
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setCrossfade', {'value': 99}),
      );
      expect(h.container.read(crossfadeProvider), 15.0);
      expect(KVStoreService.crossfadeDuration, 15.0);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setCrossfade', {'value': 6}),
      );
      expect(h.container.read(crossfadeProvider), 6.0);
    });

    testWidgets('setSleepTimer arms minutes and cancels on zero or junk',
        (tester) async {
      final sleep = _RecordingSleep();
      final h = await _pump(tester, [
        audioPlayerPortProvider.overrideWithValue(_FakePort()),
        sleepTimerProvider.overrideWith((ref) => sleep),
      ]);

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSleepTimer', {'value': 30}),
      );
      expect(sleep.armed, const Duration(minutes: 30));

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSleepTimer', {'value': 5000}),
      );
      expect(sleep.armed, const Duration(minutes: 720), reason: '12h ceiling');

      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSleepTimer', {'value': 0}),
      );
      await dispatchThemeUiAction(
        h.context,
        h.container,
        const ThemeUiAction('setSleepTimer', {'value': 'soon'}),
      );
      expect(sleep.cancels, 2);
    });
  });

  group('audio bindings', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'crossfadeDuration': 8.0});
      await KVStoreService.initialize();
    });

    testWidgets('audio.* reads live values, not the old zero stubs',
        (tester) async {
      final gains = List<double>.filled(kEqualizerBandCount, 0)
        ..[0] = 4.0
        ..[kEqualizerBandCount - 1] = -2.0;
      final h = await _pump(tester, [
        userPreferencesProvider.overrideWith(
          () => StubPrefs(
            PreferencesTable.defaults().copyWith(
              equalizerEnabled: true,
              equalizerGains: gains,
              normalizeAudio: true,
            ),
          ),
        ),
        audioPlayerPortProvider.overrideWithValue(_FakePort(currentSpeed: 1.5)),
        sleepTimerProvider.overrideWith(
          (ref) => _StubSleep(const Duration(minutes: 45)),
        ),
      ]);

      final demand = ThemeUiBindingDemand(const [
        'audio.bass',
        'audio.treble',
        'audio.normalization',
        'audio.crossfade',
        'audio.sleepTimer',
        'audio.speed',
      ]);
      final bindings = buildThemeUiBindings(
        h.ref,
        brightness: Brightness.dark,
        themeMode: 'dark',
        demand: demand,
        layout: const ThemeLayout(),
      );

      expect(bindings.values['audio.bass'], 4.0);
      expect(bindings.values['audio.treble'], -2.0);
      expect(bindings.values['audio.normalization'], isTrue);
      expect(bindings.values['audio.crossfade'], 8.0);
      expect(bindings.values['audio.sleepTimer'], 45);
      expect(bindings.values['audio.speed'], 1.5);
    });
  });
}

/// Plain prefs stub for the read-only bindings path (no writes expected).
class StubPrefs extends UserPreferencesNotifier {
  StubPrefs(this.stub);
  PreferencesTableData stub;
  @override
  PreferencesTableData build() => stub;
}
