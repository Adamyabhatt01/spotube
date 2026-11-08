// The saved-stations page: the bookmarked stations (the heart on a station
// card) have a home of their own, next to the playlists in the library.
//
// No network and no native player: the list is served from the local drift
// snapshot, and the radio backend factory is overridden with a fake.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';
import 'package:spotube/pages/library/user_radio_stations.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/services/logger/logger.dart';

RadioStation _station(String id, {String name = 'Station'}) => RadioStation(
      id: id,
      provider: 'fake',
      name: name,
      streamUrl: 'https://stream/$id',
      tags: const ['jazz'],
    );

class _NoopMusicDelegate implements MusicPlaybackDelegate {
  @override
  Future<void> pauseMusic() async {}

  @override
  Stream<bool> get musicPlayingStream => const Stream<bool>.empty();
}

Future<void> _pumpPage(WidgetTester tester, AppDatabase db) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        radioBackendFactoryProvider
            .overrideWithValue(() => throw UnimplementedError()),
        musicPlaybackDelegateProvider.overrideWithValue(_NoopMusicDelegate()),
      ],
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: [Locale('en')],
        home: Scaffold(child: UserRadioStationsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The drift-backed favorites stream schedules a retirement timer when the
/// tree is torn down, so the tree is emptied and the clock advanced before
/// the test ends.
Future<void> _drainPendingTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  AppLogger.initialize(false);

  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  testWidgets('an empty library says so instead of showing a bare grid',
      (tester) async {
    await _pumpPage(tester, db);

    expect(
        find.text('Save a station with the heart on the Radio page and it '
            'shows up here.'),
        findsOneWidget);
    expect(find.byType(RadioStationTile, skipOffstage: false), findsNothing);

    await _drainPendingTimers(tester);
  });

  testWidgets('bookmarked stations are listed and can be filtered',
      (tester) async {
    await _pumpPage(tester, db);

    final container = ProviderScope.containerOf(
      find.byType(UserRadioStationsPage).evaluate().first,
    );
    await container
        .read(radioFavoritesProvider.notifier)
        .toggle(_station('1', name: 'Jazz FM'));
    await tester.pumpAndSettle();

    expect(find.text('Jazz FM'), findsWidgets);

    // The filter narrows the list to what the user types.
    await tester.enterText(find.byType(TextField).first, 'nothing matches');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Jazz FM'), findsNothing);

    await _drainPendingTimers(tester);
  });
}
