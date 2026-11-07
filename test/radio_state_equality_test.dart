// Pins the two mechanisms that stop high-frequency radio playback state from
// rebuilding every station control:
//
//   1. RadioPlaybackState has value equality, and RadioPlaybackNotifier's
//      updateShouldNotify uses it. Riverpod's Notifier default is
//      `!identical(previous, next)`, so a copyWith that changes nothing still
//      fans out unless the notifier opts into `==`.
//   2. Per-station controls read radioStationStatusProvider (a value-comparing
//      record keyed by favoriteKey), not the controller. setVolume writes state
//      on every slider frame and ICY titles arrive many times per station, so an
//      unwatched controller rebuilds ~50 mounted cards per event.
//
// Plus a source guard, because (2) is a property of the call sites and a
// provider-only test cannot see them — the same approach as
// test/engine_call_budget_test.dart.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/services/audio_player/radio_audio_player.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

class _SilentBackend implements RadioPlayerBackend {
  @override
  Future<void> open(String url, {bool play = true}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioFilterChain(String chain) async {}

  @override
  Stream<String> get titleStream => const Stream.empty();

  @override
  Stream<bool> get playingStream => const Stream.empty();

  @override
  Stream<bool> get bufferingStream => const Stream.empty();

  @override
  Stream<String> get errorStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _SilentMusicDelegate implements MusicPlaybackDelegate {
  @override
  Future<void> pauseMusic() async {}

  @override
  Stream<bool> get musicPlayingStream => const Stream.empty();
}

RadioStation _station(String id) => RadioStation(
      id: id,
      provider: 'p',
      name: id,
      streamUrl: 'https://stream/$id',
    );

void main() {
  AppLogger.initialize(false);

  // The radio controller listens to the app-wide audio filter chain, which
  // reads the spatial/mono toggles from the KV store. Production initializes
  // it at startup; without this the whole station-status chain errors out on
  // `sharedPreferences!`.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
  });

  group('RadioPlaybackState value equality', () {
    test('identical content compares equal and hashes alike', () {
      final a = RadioPlaybackState(
        source: PlaybackSource.radio,
        activeStation: _station('A'),
        playing: true,
        buffering: false,
        liveTitle: 'Artist - Track',
        volume: 0.4,
      );
      final b = RadioPlaybackState(
        source: PlaybackSource.radio,
        activeStation: _station('A'),
        playing: true,
        buffering: false,
        liveTitle: 'Artist - Track',
        volume: 0.4,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('the default const instances are equal', () {
      expect(const RadioPlaybackState(), equals(const RadioPlaybackState()));
    });

    test('each field participates', () {
      final base = RadioPlaybackState(
        source: PlaybackSource.radio,
        activeStation: _station('A'),
        playing: true,
        buffering: true,
        liveTitle: 'x',
        error: 'e',
        volume: 0.5,
      );

      expect(base == base.copyWith(source: PlaybackSource.music), isFalse);
      expect(base == base.copyWith(playing: false), isFalse);
      expect(base == base.copyWith(buffering: false), isFalse);
      expect(base == base.copyWith(liveTitle: 'y'), isFalse);
      expect(base == base.copyWith(error: 'f'), isFalse);
      expect(base == base.copyWith(volume: 0.6), isFalse);
      expect(
        base == base.copyWith(clearStation: true),
        isFalse,
        reason: 'activeStation is part of the identity',
      );
    });

    test('a no-op copyWith is equal to its source', () {
      final base = RadioPlaybackState(
        activeStation: _station('A'),
        playing: true,
        volume: 0.3,
      );
      expect(base.copyWith(), equals(base));
    });
  });

  group('playback emissions', () {
    late AppDatabase db;
    late ProviderContainer container;
    late RadioPlaybackNotifier notifier;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // Present row: the async preferences load must not fall back to
      // path_provider (no plugin in a plain VM test).
      await db.into(db.preferencesTable).insert(
            PreferencesTableCompanion.insert(id: const Value(0)),
          );
      container = ProviderContainer(overrides: [
        radioBackendFactoryProvider
            .overrideWith((ref) => () => _SilentBackend()),
        musicPlaybackDelegateProvider
            .overrideWith((ref) => _SilentMusicDelegate()),
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);
      addTearDown(db.close);
      notifier = container.read(radioPlaybackControllerProvider.notifier);
    });

    test('an unchanged emission does not notify listeners', () async {
      await notifier.play(_station('A'));

      var notifications = 0;
      final sub = container.listen(radioPlaybackControllerProvider, (_, __) {
        notifications++;
      });
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final baseline = notifications;

      // Same volume the play() already established: a fresh instance with
      // identical content must not read as a change.
      await notifier.setVolume(1.0);
      await notifier.setVolume(1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifications - baseline, 0,
          reason: 'NotifierProvider defaults to !identical, so the notifier '
              'must opt into value equality');
    });

    test('a real change still notifies', () async {
      await notifier.play(_station('A'));

      var notifications = 0;
      final sub = container.listen(radioPlaybackControllerProvider, (_, __) {
        notifications++;
      });
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final baseline = notifications;

      await notifier.setVolume(0.25);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifications - baseline, greaterThan(0));
    });
  });

  group('per-station status is narrowed', () {
    late AppDatabase db;
    late ProviderContainer container;
    late RadioPlaybackNotifier notifier;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      // Present row: the async preferences load must not fall back to
      // path_provider (no plugin in a plain VM test).
      await db.into(db.preferencesTable).insert(
            PreferencesTableCompanion.insert(id: const Value(0)),
          );
      container = ProviderContainer(overrides: [
        radioBackendFactoryProvider
            .overrideWith((ref) => () => _SilentBackend()),
        musicPlaybackDelegateProvider
            .overrideWith((ref) => _SilentMusicDelegate()),
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);
      addTearDown(db.close);
      notifier = container.read(radioPlaybackControllerProvider.notifier);
    });

    test('a volume frame does not notify another station', () async {
      await notifier.play(_station('A'));

      var statusNotifications = 0;
      var controllerNotifications = 0;
      final statusSub =
          container.listen(radioStationStatusProvider('p:B'), (_, __) {
        statusNotifications++;
      });
      final controllerSub =
          container.listen(radioPlaybackControllerProvider, (_, __) {
        controllerNotifications++;
      });
      addTearDown(statusSub.close);
      addTearDown(controllerSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 20 frames of a volume drag, as a slider produces.
      for (var i = 1; i <= 20; i++) {
        await notifier.setVolume(i / 100);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controllerNotifications, greaterThan(0),
          reason: 'sanity: the controller really did emit');
      expect(statusNotifications, 0,
          reason: 'B is not the live station, so nothing it renders changed');
    });

    test('the live station does see its own transitions', () async {
      await notifier.play(_station('A'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      var notifications = 0;
      final sub = container.listen(radioStationStatusProvider('p:A'), (_, __) {
        notifications++;
      });
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await notifier.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifications, greaterThan(0));
    });

    test('status reports the same values the tile derived by hand', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // A present row keeps the async preferences load off path_provider
      // (no plugin in a plain VM test).
      await db.into(db.preferencesTable).insert(
            PreferencesTableCompanion.insert(id: const Value(0)),
          );

      final container = ProviderContainer(overrides: [
        radioBackendFactoryProvider
            .overrideWith((ref) => () => _SilentBackend()),
        musicPlaybackDelegateProvider
            .overrideWith((ref) => _SilentMusicDelegate()),
        databaseProvider.overrideWithValue(db),
      ]);
      addTearDown(container.dispose);

      RadioStationStatus read(String key) =>
          container.read(radioStationStatusProvider(key));

      expect(read('p:A').isActive, isFalse);
      expect(read('p:A').isPlaying, isFalse);
      expect(read('p:A').isLoading, isFalse);

      container
          .read(radioPlaybackControllerProvider.notifier)
          .play(_station('A'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final a = read('p:A');
      expect(a.isActive, isTrue);
      expect(a.isPlaying, isFalse);
      expect(a.isLoading, isTrue, reason: 'connecting right after play()');

      final b = read('p:B');
      expect(b.isActive, isFalse);
      expect(b.isLoading, isFalse);
    });
  });

  group('source guard: per-item controls must not watch the controller', () {
    // A provider test cannot see which provider a widget watches, and this is
    // the property that actually matters: one bare watch of the controller in a
    // per-item widget puts every mounted card back on the volume-frame path.
    // Same approach as test/engine_call_budget_test.dart.
    const watchedFiles = [
      'lib/modules/radio/radio_station_tile.dart',
      'lib/modules/root/sidebar/sidebar_station_pin_tile.dart',
    ];

    test('no unwatched controller in a per-item control', () {
      for (final path in watchedFiles) {
        final source = File(path).readAsStringSync();
        expect(
          RegExp(r'ref\.watch\(\s*radioPlaybackControllerProvider\s*\)')
              .hasMatch(source),
          isFalse,
          reason: '$path must watch radioStationStatusProvider(favoriteKey) '
              'instead of the whole controller',
        );
      }
    });

    test('the per-item controls do use the narrowed provider', () {
      for (final path in watchedFiles) {
        expect(
          File(path).readAsStringSync(),
          contains('radioStationStatusProvider('),
          reason: '$path is expected to read the narrowed status',
        );
      }
    });
  });
}
