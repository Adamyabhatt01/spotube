// Responsive render proof for the minimum radio UI: the same screen uses list
// tiles at a phone width and a card grid at a desktop width (the requirement
// that radio "keep mobile view in mind"), and tapping play opens a station
// through the injected backend and moves the radio controller into its playing
// state.
//
// No network and no native player: an in-memory directory is registered and the
// radio backend factory is overridden with a fake.

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/playbutton_view/playbutton_view.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/radio/radio_station_rail.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/pages/radio/radio.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/services/audio_player/radio_audio_player.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

RadioStation _station(String id) => RadioStation(
      id: id,
      provider: 'fake',
      name: 'Station $id',
      streamUrl: 'https://stream/$id',
      tags: const ['jazz'],
    );

class _InMemoryDirectory implements RadioDirectoryProvider {
  @override
  final String id = 'fake';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    final items = [_station('1'), _station('2')];
    return SpotubePaginationResponseObject(
      limit: limit,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async =>
      [RadioTag(name: 'rock')];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async =>
      [RadioCountry(code: 'us', name: 'United States')];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

class _NoopMusicDelegate implements MusicPlaybackDelegate {
  @override
  Future<void> pauseMusic() async {}
  @override
  Stream<bool> get musicPlayingStream => const Stream<bool>.empty();
}

class _FakeBackend implements RadioPlayerBackend {
  final opened = <String>[];
  final _playing = StreamController<bool>.broadcast();

  @override
  Future<void> open(String url, {bool play = true}) async {
    opened.add(url);
    // Report the stream as live so the controller leaves its buffering state;
    // an never-emitting fake would leave the play button as a permanent spinner.
    _playing.add(true);
  }

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
  Stream<String> get titleStream => const Stream<String>.empty();
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();
  @override
  Stream<String> get errorStream => const Stream<String>.empty();
  @override
  Future<void> dispose() async => _playing.close();
}

Future<void> _pumpRadio(
  WidgetTester tester,
  Size surface,
  AppDatabase db,
  _FakeBackend backend,
) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        radioBackendFactoryProvider.overrideWithValue(() => backend),
        musicPlaybackDelegateProvider.overrideWithValue(_NoopMusicDelegate()),
      ],
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        // Pages run inside the app scaffold in production; the scaffold owns
        // the overlay layer shadcn popups (e.g. the country Select) need.
        home: Scaffold(child: RadioScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The station rows watch the drift-backed favorites stream. When the tree is
// torn down, drift schedules a Timer(Duration.zero) in StreamQueryStore to
// retire the query — created during disposal, so a pump inside the test body
// can't reach it unless we unmount the tree ourselves first. Replacing the tree
// with an empty widget forces that disposal to run here, then one clock advance
// fires the pending timer before the framework's invariant check.
Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  AppLogger.initialize(false);

  late AppDatabase db;
  setUp(() async {
    // The radio controller's audio-filter listen reads the spatial/mono
    // toggles from the KV store; production initializes it before runApp.
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Seed the preferences row so the async load never calls path_provider
    // (no plugin in tests); the defaults match the row it would seed itself.
    await db.into(db.preferencesTable).insert(
          PreferencesTableCompanion.insert(id: const Value(0)),
        );
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory());
  });
  tearDown(() {
    radioProviders.clear();
    db.close();
  });

  testWidgets('phone width renders station rows as a list', (tester) async {
    await _pumpRadio(tester, const Size(420, 900), db, _FakeBackend());

    expect(find.text('Station 1'), findsWidgets);
    // Compact layout uses tiles in the main grid; the section rails are cards
    // at every width (Home parity), so the card assertions are scoped. The
    // rails push the grid below the fold on a 900px phone surface, so these
    // structural assertions ignore the stage (production scrolls; the
    // viewport is a harness artifact here).
    expect(
      find.byType(RadioStationTile, skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(PlaybuttonView),
        matching: find.byType(RadioStationCard),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(RadioStationRail),
        matching: find.byType(RadioStationCard),
        skipOffstage: false,
      ),
      findsWidgets,
    );

    await _drainPendingTimers(tester);
  });

  testWidgets('desktop width renders stations as a card grid', (tester) async {
    await _pumpRadio(tester, const Size(1200, 900), db, _FakeBackend());

    expect(find.byType(RadioStationCard), findsWidgets);
    expect(find.byType(RadioStationTile), findsNothing);

    await _drainPendingTimers(tester);
  });

  testWidgets(
      'tapping play opens the station and moves the controller to radio',
      (tester) async {
    final backend = _FakeBackend();
    await _pumpRadio(tester, const Size(420, 900), db, backend);

    // Each row's play control shows the play glyph; tap the first station's.
    await tester.tap(find.byIcon(SpotubeIcons.play).first);
    await tester.pumpAndSettle();

    expect(backend.opened, ['https://stream/1']);

    final container = ProviderScope.containerOf(
      find.byType(RadioScreen).evaluate().first,
    );
    final state = container.read(radioPlaybackControllerProvider);
    expect(state.source, PlaybackSource.radio);
    expect(state.activeStation?.id, '1');

    await _drainPendingTimers(tester);
  });

  testWidgets('bookmarking a station shows it in the favorites rail',
      (tester) async {
    await _pumpRadio(tester, const Size(420, 900), db, _FakeBackend());

    final screen = find.byType(RadioScreen).evaluate().first;
    final container = ProviderScope.containerOf(screen);
    // Bookmark through the drift-backed notifier. The rail renders from the
    // stored snapshot, so no directory fetch is needed. The favorites rail
    // sits first, so no scrolling is needed to see it.
    await container.read(radioFavoritesProvider.notifier).toggle(_station('1'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Your favorites'), findsOneWidget);
    expect(find.text('Station 1'), findsWidgets);

    await _drainPendingTimers(tester);
  });

  testWidgets('country filter is always on screen, the rail keeps tag chips',
      (tester) async {
    await _pumpRadio(tester, const Size(420, 900), db, _FakeBackend());

    // The country axis has a row of its own, above the rails. It used to be
    // the last item of the horizontally scrolling tag rail, which put it
    // off-screen on a phone (thirty tag chips first) and took it away with
    // the rail while a search was typed.
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('United States'), findsNothing);

    // Open the dropdown and pick the country; the control then shows the
    // selection.
    await tester.tap(find.text('Country'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('United States'));
    await tester.pumpAndSettle();

    expect(find.text('United States'), findsOneWidget);

    // Tags stay as chips, in the rail further down the page.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('rock'), findsOneWidget);

    await _drainPendingTimers(tester);
  });

  // The Radio search bar is styled to match Browse's (see HomeSearchBar): a
  // filled pill capped to the same width, with an in-field clear affordance.
  // These are the properties that made the two bars read as different widgets.
  testWidgets('search bar matches the Browse pill', (tester) async {
    await _pumpRadio(tester, const Size(1200, 900), db, _FakeBackend());

    final field = find.widgetWithText(TextField, 'Search stations');
    expect(field, findsOneWidget);
    // Search drops this shortcut, but the actual Radio page keeps it.
    expect(find.byKey(const ValueKey('radioMusicShortcut')), findsOneWidget);

    final theme = tester.element(find.byType(RadioScreen)).theme;
    final textField = tester.widget<TextField>(field);
    expect(textField.filled, isTrue);
    expect(textField.borderRadius, theme.borderRadiusXxl);
    expect(
      textField.padding,
      EdgeInsets.symmetric(
          horizontal: 16 * theme.scaling, vertical: 12 * theme.scaling),
    );

    // Capped like Browse, so a wide window does not stretch it into a band.
    expect(tester.getSize(field).width, lessThanOrEqualTo(520));

    await _drainPendingTimers(tester);
  });

  testWidgets('typing reveals the clear button and it empties the field',
      (tester) async {
    await _pumpRadio(tester, const Size(1200, 900), db, _FakeBackend());

    final field = find.widgetWithText(TextField, 'Search stations');
    // AnimatedCrossFade keeps both children mounted and only swaps which one
    // it paints, so presence proves nothing. Read the state that drives it.
    CrossFadeState clearButtonState() => tester
        .widget<AnimatedCrossFade>(
          find.descendant(of: field, matching: find.byType(AnimatedCrossFade)),
        )
        .crossFadeState;

    expect(clearButtonState(), CrossFadeState.showSecond);

    await tester.enterText(field, 'jazz');
    await tester.pumpAndSettle();
    expect(clearButtonState(), CrossFadeState.showFirst);

    // Tap the button, not the glyph: the Icon's own box is inset inside the
    // IconButton, so its center is not a reliable hit target.
    await tester.tap(
      find.ancestor(
        of: find.descendant(
          of: field,
          matching: find.byIcon(SpotubeIcons.close),
        ),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(clearButtonState(), CrossFadeState.showSecond);

    await _drainPendingTimers(tester);
  });

  testWidgets('pinning a station from its row stores the pin', (tester) async {
    // The preferences row is seeded in setUp, so the notifier loads cleanly.
    await _pumpRadio(tester, const Size(420, 900), db, _FakeBackend());

    Finder tilePin(IconData icon) => find.descendant(
          of: find.byType(RadioStationTile),
          matching: find.byIcon(icon),
        );

    final screen = find.byType(RadioScreen).evaluate().first;
    final container = ProviderScope.containerOf(screen);

    // Let the initial preferences load (row seed) settle before toggling:
    // a toggle racing the seed would be overwritten by it.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (container.read(userPreferencesStatusProvider) is AsyncData) break;
    }
    expect(container.read(userPreferencesStatusProvider), isA<AsyncData>());

    // The grid sits below the rails; bring its rows onstage first.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    await tester.tap(tilePin(SpotubeIcons.pinOff).first);
    await tester.pumpAndSettle();

    expect(
      container.read(userPreferencesProvider).pinnedStationIds,
      ['fake:1'],
    );

    // Tapping the pinned icon again unpins.
    await tester.tap(tilePin(SpotubeIcons.pinOn).first);
    await tester.pumpAndSettle();
    expect(
      container.read(userPreferencesProvider).pinnedStationIds,
      isEmpty,
    );

    // Pinning raised a toast with an auto-dismiss timer; run past it before
    // the end-of-test timer check.
    await tester.pump(const Duration(seconds: 10));

    await _drainPendingTimers(tester);
  });
}
