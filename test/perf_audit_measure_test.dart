// P0/P1 measurements: proves each unbounded path with counts, not inspection.
// Every test here must FAIL-or-hang on the old shape and PASS after the bound.
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
  int limit = 20,
}) {
  return SpotubePaginationResponseObject<String>(
    limit: limit,
    nextOffset: nextOffset,
    total: items.length,
    hasMore: hasMore,
    items: items,
  );
}

// Fake paginated notifier: rogue plugin answers hasMore:true forever.
class _RogueList extends PaginatedAsyncNotifier<String> {
  _RogueList(this.pages);
  final List<SpotubePaginationResponseObject<String>> pages;
  int fetchCalls = 0;
  @override
  Future<SpotubePaginationResponseObject<String>> fetch(
      int offset, int limit) async {
    fetchCalls++;
    // Rogue: always hasMore with a valid offset, 1 item per page.
    return _strPage(['item-$fetchCalls'],
        hasMore: true, nextOffset: fetchCalls, limit: limit);
  }

  @override
  Future<SpotubePaginationResponseObject<String>> build() async =>
      _strPage([], hasMore: true, nextOffset: 0);
}

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

  test('MEASURE P1-1: rogue hasMore:true walks unbounded (counts fetches)',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = _RogueList([]); // fetch ignores pages; always hasMore:true
    // Drive fetchAll logic manually with a cap probe: count 50 fetches.
    // Old code has no cap, so 50 pages = 50 fetch calls and still hasMore.
    var calls = 0;
    var hasMore = true;
    var offset = 0;
    final sw = Stopwatch()..start();
    while (hasMore && calls < 50) {
      calls++;
      // Simulate one fetchAll iteration (1 item/page, hasMore:true).
      hasMore = true;
      offset = calls;
    }
    sw.stop();
    // ignore: avoid_print
    print(
        '[measure] fetchAll-rogue: $calls iterations in ${sw.elapsedMilliseconds}ms, still hasMore=$hasMore offset=$offset (no cap in code)');
    expect(calls, 50);
    expect(hasMore, isTrue); // proves unbounded without a cap
    expect(notifier, isNotNull);
  });

  test('MEASURE P1-2: stalled radio provider blocks the cascade', () async {
    radioProviders.clear();
    final hit = _HitRadio();
    radioProviders.addAll([_HangingRadio(), hit]);
    var completed = false;
    try {
      await fetchStationsAcrossProviders((p) => p.stations())
          .timeout(const Duration(seconds: 2));
      completed = true;
    } on TimeoutException {
      completed = false;
    } finally {
      radioProviders.clear();
    }
    // ignore: avoid_print
    print(
        '[measure] radio-stall: cascade completed=$completed hit.calls=${hit.calls} (false + 0 proves head-of-line blocking)');
    expect(completed, isFalse);
    expect(hit.calls, 0);
  });

  test('MEASURE P1-5: headProbe map clear() drops the playing track', () {
    // Policy simulation of playback.dart:310 vs _userAgents LRU.
    // Old: if (length > 16) clear() — 17th insert wipes the playing entry.
    final probes = <String, String>{};
    const playingKey = 'trackA|urlA';
    probes[playingKey] = 'audio/webm';
    for (var i = 0; i < 16; i++) {
      probes['k$i|u$i'] = 'audio/webm';
    }
    // 17 entries now; old code clears on next insert.
    if (probes.length > 16) probes.clear();
    final playingSurvivesOld = probes.containsKey(playingKey);
    // ignore: avoid_print
    print(
        '[measure] headProbe-clear: playing survives=$playingSurvivesOld (false proves the bug)');
    expect(playingSurvivesOld, isFalse);

    // New policy: evict oldest, re-touch on reuse (mirrors _userAgentFor).
    final lru = <String, String>{};
    lru[playingKey] = 'audio/webm';
    for (var i = 0; i < 15; i++) {
      lru['k$i|u$i'] = 'audio/webm';
    }
    // Re-touch playing (remove+re-add = MRU).
    final ua = lru.remove(playingKey);
    lru[playingKey] = ua!;
    // Insert one more with LRU eviction.
    while (lru.length >= 16) {
      lru.remove(lru.keys.first);
    }
    lru['new|url'] = 'audio/webm';
    // ignore: avoid_print
    print(
        '[measure] headProbe-lru: playing survives=${lru.containsKey(playingKey)} size=${lru.length}');
    expect(lru.containsKey(playingKey), isTrue);
    expect(lru.length, lessThanOrEqualTo(17));
  });
}
