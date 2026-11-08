// Exercises fetchStationsAcrossProviders — the priority + isolation rule the
// radio directory registry inherits from the lyrics subsystem: first
// non-empty page wins, an empty result is a miss, a throwing provider is
// skipped, and an error only surfaces when every provider that ran failed.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

SpotubePaginationResponseObject<RadioStation> _page(List<RadioStation> items) {
  return SpotubePaginationResponseObject(
    limit: items.length,
    nextOffset: null,
    total: items.length,
    hasMore: false,
    items: items,
  );
}

RadioStation _station(String id) =>
    RadioStation(id: id, provider: 'fake', name: id, streamUrl: 'https://$id');

/// [items] null => throw; empty list => miss; non-empty => hit.
class _FakeProvider implements RadioDirectoryProvider {
  _FakeProvider(this.id, {this.items, this.throwOnCall = false});

  @override
  final String id;
  final List<RadioStation>? items;
  final bool throwOnCall;
  int calls = 0;

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    calls++;
    if (throwOnCall) throw StateError('broken: $id');
    return _page(items ?? const []);
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

void main() {
  AppLogger.initialize(false);

  setUp(() => radioProviders.clear());
  tearDown(() => radioProviders.clear());

  test('first non-empty provider wins and later ones are not called', () async {
    final first = _FakeProvider('first', items: [_station('a')]);
    final second = _FakeProvider('second', items: [_station('b')]);
    radioProviders.addAll([first, second]);

    final page = await fetchStationsAcrossProviders((p) => p.stations());

    expect(page.items.map((s) => s.id), ['a']);
    expect(first.calls, 1);
    expect(second.calls, 0);
  });

  test('an empty result is a miss; the next provider serves', () async {
    final empty = _FakeProvider('empty');
    final hit = _FakeProvider('hit', items: [_station('c')]);
    radioProviders.addAll([empty, hit]);

    final page = await fetchStationsAcrossProviders((p) => p.stations());

    expect(page.items.map((s) => s.id), ['c']);
    expect(empty.calls, 1);
    expect(hit.calls, 1);
  });

  test('a throwing provider is isolated; a later hit still serves', () async {
    final broken = _FakeProvider('broken', throwOnCall: true);
    final hit = _FakeProvider('hit', items: [_station('d')]);
    radioProviders.addAll([broken, hit]);

    final page = await fetchStationsAcrossProviders((p) => p.stations());

    expect(page.items.map((s) => s.id), ['d']);
    expect(broken.calls, 1);
  });

  test('escalates when every provider that ran threw', () async {
    radioProviders.addAll([
      _FakeProvider('one', throwOnCall: true),
      _FakeProvider('two', throwOnCall: true),
    ]);

    await expectLater(
      fetchStationsAcrossProviders((p) => p.stations()),
      throwsA(isA<StateError>()),
    );
  });

  test('all-empty (no throw) returns an empty page, not an error', () async {
    radioProviders.add(_FakeProvider('empty'));

    final page = await fetchStationsAcrossProviders((p) => p.stations());

    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('no providers registered returns an empty page', () async {
    final page = await fetchStationsAcrossProviders((p) => p.stations());
    expect(page.items, isEmpty);
  });
}
