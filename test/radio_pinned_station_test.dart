// Sidebar pin resolution: a persisted favorite key resolves favorites first
// (offline snapshot), then listen history, then the owning directory's byId,
// and null when nothing answers — the sidebar skips it like a deleted
// playlist pin. No network and no native player: an in-memory database plus
// an in-memory directory.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/radio/favorites.dart';
import 'package:spotube/provider/radio/pinned_station.dart';
import 'package:spotube/provider/radio/stations.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

RadioStation _station(String id, {String provider = 'fake'}) => RadioStation(
      id: id,
      provider: provider,
      name: 'Station $id',
      streamUrl: 'https://stream/$id',
      tags: const ['jazz'],
    );

class _InMemoryDirectory implements RadioDirectoryProvider {
  _InMemoryDirectory({this.onById});

  /// Called on every [byId] that reaches the network, so a test can count how
  /// many round-trips a rebuild costs.
  final void Function(String id)? onById;

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
    return SpotubePaginationResponseObject(
      limit: limit,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: const [],
    );
  }

  // Only 'net' exists on the network; everything else is a miss.
  @override
  Future<RadioStation?> byId(String id) async {
    onById?.call(id);
    return id == 'net' ? _station('net') : null;
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];
}

void main() {
  AppLogger.initialize(false);

  late AppDatabase db;
  late ProviderContainer container;
  late int syncGeneration;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncGeneration = 0;
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // The real sync reads metadataPluginsProvider, which would try to
        // extract plugins off disk (no path_provider in tests). Replaced with a
        // generation counter the test can bump by hand — which is exactly the
        // value the real sync yields, and the only reason a dependent of the
        // registry ever learns that the plugin set changed.
        radioPluginDirectorySyncProvider.overrideWith((ref) => syncGeneration),
      ],
    );
  });

  tearDown(() {
    radioProviders.clear();
    container.dispose();
    db.close();
  });

  Future<void> settlePinned() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  // A listener keeps the autoDispose family alive while it loads; a bare
  // `.future` read would be disposed mid-flight in the test env. Reads the
  // settled value instead of the first completion: the first build can
  // complete from byId/miss before the seeded snapshots land, and only a
  // later rebuild (triggered by the snapshots' watch emissions) sees them —
  // in the app the widget watch absorbs this, here we flush explicitly.
  /// What the sync's listener does in the app: rewrite the global registry,
  /// then publish a new generation so dependents re-read it.
  void announceSync() {
    syncGeneration++;
    container.invalidate(radioPluginDirectorySyncProvider);
  }

  Future<RadioStation?> resolve(String key) async {
    final sub = container.listen(pinnedStationProvider(key), (_, __) {});
    addTearDown(sub.close);
    await settlePinned();
    return container.read(pinnedStationProvider(key)).asData?.value;
  }

  test('favorites snapshot wins without touching the network', () async {
    await container
        .read(radioFavoritesProvider.notifier)
        .toggle(_station('fav'));
    // The directory knows nothing about 'fav' (byId misses): a non-null
    // answer proves the favorites snapshot served it.
    final station = await resolve('fake:fav');
    expect(station?.id, 'fav');
    expect(station?.name, 'Station fav');
  });

  test('listen history serves pins that were never favorited', () async {
    final station = _station('heard');
    await db.into(db.historyTable).insert(
          HistoryTableCompanion.insert(
            type: HistoryEntryType.radio,
            itemId: station.favoriteKey,
            data: station.toJson(),
          ),
        );
    final resolved = await resolve('fake:heard');
    expect(resolved?.id, 'heard');
  });

  test('directory byId is the last resort', () async {
    final resolved = await resolve('fake:net');
    expect(resolved?.id, 'net');
  });

  test('unknown provider, unknown id and malformed keys resolve null',
      () async {
    expect(await resolve('ghost:gone'), isNull);
    expect(await resolve('fake:gone'), isNull);
    expect(await resolve('no-separator'), isNull);
    expect(await resolve(':empty-provider'), isNull);
  });

  test('a pin re-resolves once the plugin directory sync lands', () async {
    // The sidebar reads pins before plugin state has finished loading, so the
    // registry is still empty and the network path has nothing to ask.
    radioProviders.clear();
    expect(await resolve('fake:net'), isNull);

    // What the sync does: rewrite the global registry in place, then announce
    // itself. Nothing observable happens to a plain mutable list, so a consumer
    // that does not watch the sync keeps the null it computed.
    radioProviders.add(_InMemoryDirectory());
    announceSync();
    await settlePinned();

    expect((await resolve('fake:net'))?.id, 'net',
        reason: 'a pin must not stay invisible for the rest of the session '
            'because the sidebar got there before the plugins did');
  });

  test('unrelated history writes do not re-ask the directory', () async {
    var byIdCalls = 0;
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory(onById: (_) => byIdCalls++));

    expect((await resolve('fake:net'))?.id, 'net');
    expect(byIdCalls, 1);

    // Pinning does not favorite, so 'net' lives in neither offline snapshot.
    // An ordinary music session still writes history_table rows, and the radio
    // history query declares readsFrom on it — each write used to cost one more
    // directory round-trip per pin.
    for (var i = 0; i < 5; i++) {
      final station = _station('other-$i');
      await db.into(db.historyTable).insert(
            HistoryTableCompanion.insert(
              type: HistoryEntryType.radio,
              itemId: station.favoriteKey,
              data: station.toJson(),
            ),
          );
      await settlePinned();
    }

    expect((await resolve('fake:net'))?.id, 'net');
    expect(byIdCalls, 1,
        reason: 'a successful directory resolution is memoized, so history '
            'churn does not re-hit the network');
  });

  test('a miss is not memoized', () async {
    var byIdCalls = 0;
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory(onById: (_) => byIdCalls++));

    expect(await resolve('fake:gone'), isNull);
    expect(await resolve('fake:gone'), isNull);

    expect(byIdCalls, 2,
        reason: 'a miss is the answer most likely to change (the directory '
            'may still be loading), so it must be re-asked');
  });

  test('a changed directory set drops the memo', () async {
    var byIdCalls = 0;
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory(onById: (_) => byIdCalls++));

    expect((await resolve('fake:net'))?.id, 'net');
    expect(byIdCalls, 1);

    // A plugin update rewrites the registry and rotates stream URLs, so the
    // cached station must not outlive the directory set that produced it.
    radioProviders
      ..clear()
      ..add(_InMemoryDirectory(onById: (_) => byIdCalls++));
    announceSync();
    await settlePinned();

    expect((await resolve('fake:net'))?.id, 'net');
    expect(byIdCalls, 2);
  });
}
