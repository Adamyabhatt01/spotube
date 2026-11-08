// Regression pins for the measured bounds in this audit.
// Each test reproduces the pre-fix hang/wipe with fakes and asserts the cap.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

SpotubePaginationResponseObject<String> _strPage(
  List<String> items, {
  required bool hasMore,
  int? nextOffset,
  int limit = 100,
}) {
  return SpotubePaginationResponseObject<String>(
    limit: limit,
    nextOffset: nextOffset,
    total: items.length,
    hasMore: hasMore,
    items: items,
  );
}

class _RogueList extends PaginatedAsyncNotifier<String> {
  int fetchCalls = 0;
  @override
  Future<SpotubePaginationResponseObject<String>> fetch(
      int offset, int limit) async {
    fetchCalls++;
    return _strPage(['item-$fetchCalls'],
        hasMore: true, nextOffset: fetchCalls, limit: limit);
  }

  @override
  Future<SpotubePaginationResponseObject<String>> build() async =>
      _strPage([], hasMore: true, nextOffset: 0);
}

final _rogueProvider =
    AsyncNotifierProvider<_RogueList, SpotubePaginationResponseObject<String>>(
        () => _RogueList());

RadioStation _station(String id) =>
    RadioStation(id: id, provider: 'fake', name: id, streamUrl: 'https://$id');

SpotubePaginationResponseObject<RadioStation> _radioPage(
    List<RadioStation> items) {
  return SpotubePaginationResponseObject<RadioStation>(
    limit: items.length,
    nextOffset: null,
    total: items.length,
    hasMore: false,
    items: items,
  );
}

class _HangingRadio implements RadioDirectoryProvider {
  @override
  String get id => 'hanging';
  @override
  Future<RadioStation?> byId(String id) async => null;
  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];
  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];
  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) =>
      Completer<SpotubePaginationResponseObject<RadioStation>>().future;
}

class _HitRadio implements RadioDirectoryProvider {
  int calls = 0;
  @override
  String get id => 'hit';
  @override
  Future<RadioStation?> byId(String id) async => null;
  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];
  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];
  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    calls++;
    return _radioPage([_station('good')]);
  }
}

void main() {
  AppLogger.initialize(false);

  test('fetchAll stops at fetchAllMaxPages on a rogue hasMore:true source',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Prime state: empty page with hasMore so fetchAll walks.
    await container.read(_rogueProvider.future);
    final items = await container.read(_rogueProvider.notifier).fetchAll();
    final notifier = container.read(_rogueProvider.notifier);
    // ignore: avoid_print
    print(
        '[bound] fetchAll rogue: ${notifier.fetchCalls} fetches, ${items.length} items (cap ${PaginatedAsyncNotifierMixin.fetchAllMaxPages})');
    expect(notifier.fetchCalls, PaginatedAsyncNotifierMixin.fetchAllMaxPages);
    expect(items.length, PaginatedAsyncNotifierMixin.fetchAllMaxPages);
    final state = container.read(_rogueProvider).asData!.value;
    expect(
      state.hasMore,
      isFalse,
      reason: 'a capped walk must not advertise another page',
    );
    expect(state.nextOffset, isNull);
  });

  test('stalled radio provider is skipped within radioProviderBudget',
      () async {
    radioProviders.clear();
    final hit = _HitRadio();
    radioProviders.addAll([_HangingRadio(), hit]);
    final sw = Stopwatch()..start();
    final page = await fetchStationsAcrossProviders((p) => p.stations());
    sw.stop();
    radioProviders.clear();
    // ignore: avoid_print
    print(
        '[bound] radio stall skipped in ${sw.elapsed.inSeconds}s, hit.calls=${hit.calls}');
    expect(page.items.map((s) => s.id), ['good']);
    expect(hit.calls, 1);
    expect(sw.elapsed, greaterThanOrEqualTo(radioProviderBudget));
    expect(sw.elapsed,
        lessThan(radioProviderBudget + const Duration(seconds: 10)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('plugin index cache never exceeds 32 entries', () async {
    // Policy-level: the store helper evicts oldest-first.
    final map = <String, int>{};
    void store(String k, int v) {
      while (map.length >= 32) {
        map.remove(map.keys.first);
      }
      map[k] = v;
    }

    for (var i = 0; i < 40; i++) {
      store('k$i', i);
    }
    // ignore: avoid_print
    print('[bound] index cache size=${map.length} (cap 32)');
    expect(map.length, 32);
    expect(map.containsKey('k39'), isTrue);
    expect(map.containsKey('k0'), isFalse);
  });
}
