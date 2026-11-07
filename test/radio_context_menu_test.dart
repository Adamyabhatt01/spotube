// Radio station context menu contracts: rows come from the shared `radio`
// defaults table, the homepage row only exists for stations that carry a
// homepage, labels follow the live playback/favorite/pin state, and Copy
// stream URL writes the station's stream address.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/radio/radio_context_menu.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

RadioStation _station({String? homepageUrl}) {
  return RadioStation(
    id: 'st-1',
    provider: 'fake',
    name: 'Station One',
    streamUrl: 'https://stream/st-1',
    tags: const ['jazz'],
    homepageUrl: homepageUrl,
  );
}

ProviderContainer _container({
  RadioStationStatus? status,
}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) => _db),
      themeDefinitionProvider.overrideWith(
        (ref) async => ThemeDefinition(
          specVersion: 4,
          light: builtInLightThemeColors(),
          dark: builtInDarkThemeColors(),
        ),
      ),
      themeUiProvider.overrideWith((ref) async => null),
      // Stands in for the transport: the real controller builds a media_kit
      // player, which no widget test initializes.
      radioStationStatusProvider.overrideWith(
        (ref, key) =>
            status ?? (isActive: false, isPlaying: false, isLoading: false),
      ),
    ],
  );
}

late AppDatabase _db;

Widget _harness(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        child: AppLayout(
          tokens: const ThemeTokens(),
          radii: const ThemeRadius(),
          layout: const ThemeLayout(),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

Widget _menu(RadioStation station) {
  return RadioStationContextMenu(
    station: station,
    child: const SizedBox(
      key: Key('radio-target'),
      width: 240,
      height: 80,
      child: ColoredBox(color: Color(0xFF888888)),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('radio-target'))),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    _db = AppDatabase.forTesting(NativeDatabase.memory());
    // Seed the preferences row so the async load never calls path_provider.
    await _db.into(_db.preferencesTable).insert(
          PreferencesTableCompanion.insert(id: const Value(0)),
        );
  });

  tearDown(() async {
    await _db.close();
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    RadioStation? station,
    RadioStationStatus? status,
  }) async {
    final container = _container(status: status);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(_menu(station ?? _station()), container));
    await tester.pumpAndSettle();
  }

  testWidgets('station offers play, favorite, pin and copy stream url',
      (tester) async {
    await pumpMenu(tester);
    await _openMenu(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Pin to sidebar'), findsOneWidget);
    expect(find.text('Copy stream URL'), findsOneWidget);
    expect(find.text('Open homepage'), findsNothing);
  });

  testWidgets('the homepage row only exists for stations with a homepage',
      (tester) async {
    await pumpMenu(tester, station: _station(homepageUrl: 'https://fm.test'));
    await _openMenu(tester);

    expect(find.text('Open homepage'), findsOneWidget);
  });

  testWidgets('labels follow the playing state', (tester) async {
    await pumpMenu(
      tester,
      status: (isActive: true, isPlaying: true, isLoading: false),
    );
    await _openMenu(tester);

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a favorited station offers to remove the favorite',
      (tester) async {
    final station = _station();
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(_menu(station), container));
    await tester.pumpAndSettle();

    // The drift-backed favorites provider only stays alive while something
    // listens; the menu itself resolves state on open without subscribing,
    // exactly like the app after the favorites page loaded the list.
    final sub = container.listen(radioFavoritesProvider, (_, __) {});
    await container.read(radioFavoritesProvider.notifier).toggle(station);
    await tester.pumpAndSettle();

    await _openMenu(tester);
    expect(find.text('Remove from favorites'), findsOneWidget);

    sub.close();
  });

  testWidgets('copy stream url writes the station URL', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pumpMenu(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Copy stream URL'));

    // Let the menu dismiss and the clipboard round-trip land; the toast's
    // timer is drained before teardown like the playlist test does.
    await tester.pumpAndSettle();
    expect(copied, 'https://stream/st-1');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
