// Exercises the PR-E UI provider layer: registration idempotency, the paginated
// station family (first page, append-with-dedupe, and that a distinct query keys
// a distinct instance), and the tags/countries aggregation that skips dead or
// empty directories.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/radio/plugin_directory_adapter.dart';
import 'package:spotube/provider/radio/stations.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

/// Hands back a [Ref] to exercise [radioProvidersFor] without a database. The
/// adapters it builds resolve their plugin VM lazily, so the ordering tests
/// below never touch `ref` — a captured, unused Ref is enough.
final _refProvider = Provider<Ref>((ref) => ref);

PluginConfiguration _radio(String name) => PluginConfiguration(
      name: name,
      author: 'Spotube',
      description: name,
      version: '1.0.0',
      entryPoint: 'X',
      pluginApiVersion: '2.0.0',
      abilities: const [PluginAbilities.radio],
    );

PluginConfiguration _nonRadio() => PluginConfiguration(
      name: 'Not radio',
      author: 'Spotube',
      description: 'metadata only',
      version: '1.0.0',
      entryPoint: 'X',
      pluginApiVersion: '2.0.0',
      abilities: const [PluginAbilities.metadata],
    );

RadioStation _station(String id) => RadioStation(
      id: id,
      provider: 'fake',
      name: id,
      streamUrl: 'https://$id',
    );

/// Serves a fixed station list across [stations] calls, slicing by offset/limit
/// like a real directory, and records every query it was asked for.
class _PagingProvider implements RadioDirectoryProvider {
  _PagingProvider(this.id, this._all, {this.pageSize = 20});

  @override
  final String id;
  final List<RadioStation> _all;
  final int pageSize;
  final List<RadioStationsQuery?> seen = [];

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    seen.add((tag: tag, country: country, search: search));
    final size = pageSize;
    final page = _all.skip(offset).take(size).toList();
    final nextOffset = offset + size < _all.length ? offset + size : null;
    return SpotubePaginationResponseObject(
      limit: size,
      nextOffset: nextOffset,
      total: _all.length,
      hasMore: nextOffset != null,
      items: page,
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Returns canned tags/countries, or throws when [broken], to test aggregation.
class _MetaProvider implements RadioDirectoryProvider {
  _MetaProvider(
    this.id, {
    this.tagList = const [],
    this.countryList = const [],
    this.broken = false,
  });

  @override
  final String id;
  final List<RadioTag> tagList;
  final List<RadioCountry> countryList;
  final bool broken;

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async =>
      SpotubePaginationResponseObject(
        limit: 0,
        nextOffset: null,
        total: 0,
        hasMore: false,
        items: const [],
      );

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async {
    if (broken) throw StateError('tags down: $id');
    return tagList;
  }

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async {
    if (broken) throw StateError('countries down: $id');
    return countryList;
  }

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Two pages where page two re-serves page one's last item, so a naive append
/// would show a duplicate.
class _OverlappingProvider implements RadioDirectoryProvider {
  @override
  final String id = 'overlap';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset == 0) {
      return SpotubePaginationResponseObject(
        limit: 2,
        nextOffset: 2,
        total: 3,
        hasMore: true,
        items: [_station('a'), _station('b')],
      );
    }
    return SpotubePaginationResponseObject(
      limit: 2,
      nextOffset: null,
      total: 3,
      hasMore: false,
      items: [_station('b'), _station('c')],
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Fails the top-up (offset > 0) but serves page one, to pin what a failed
/// pagination is allowed to do to the caller.
class _TopUpFailsProvider implements RadioDirectoryProvider {
  @override
  final String id = 'flaky';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset != 0) throw StateError('page two down');
    return SpotubePaginationResponseObject(
      limit: 1,
      nextOffset: 1,
      total: 2,
      hasMore: true,
      items: [_station('a')],
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Simulates [radioPluginDirectorySyncProvider] landing mid-request: it rewrites
/// the global registry while a fan-out loop is suspended inside an `await`,
/// which is exactly what a `plugins_table` write does.
///
/// Returns an **empty** page, because that is what makes the bug reachable: a
/// non-empty answer returns straight out of the loop and never advances the
/// iterator, so only a miss leaves the loop stepping into a list that changed
/// length under it.
class _RegistryMutatingProvider implements RadioDirectoryProvider {
  _RegistryMutatingProvider(this.onStations);

  /// Invoked while the fan-out loop is parked inside this provider's request.
  final void Function() onStations;

  @override
  final String id = 'mutator';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    await Future<void>.delayed(Duration.zero);
    onStations();
    return SpotubePaginationResponseObject(
      limit: 0,
      nextOffset: null,
      total: 0,
      hasMore: false,
      items: const [],
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async {
    await Future<void>.delayed(Duration.zero);
    onStations();
    return const [];
  }

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async {
    await Future<void>.delayed(Duration.zero);
    onStations();
    return const [];
  }

  @override
  Future<RadioStation?> byId(String id) async => null;
}

/// Counts every call the browse layer makes, so a test can tell "the page was
/// rebuilt" from "the directory was asked again".
class _CountingProvider implements RadioDirectoryProvider {
  @override
  final String id = 'counting';

  int stationCalls = 0;
  int tagCalls = 0;
  int countryCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    stationCalls++;
    return SpotubePaginationResponseObject(
      limit: 1,
      nextOffset: null,
      total: 1,
      hasMore: false,
      items: [_station('s$offset')],
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async {
    tagCalls++;
    return [RadioTag(name: 'rock', stationCount: 3)];
  }

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async {
    countryCalls++;
    return [RadioCountry(code: 'us', name: 'United States')];
  }

  @override
  Future<RadioStation?> byId(String id) async => null;
}

const _popular = (tag: null, country: null, search: null);

void main() {
  AppLogger.initialize(false);

  late ProviderContainer container;
  setUp(() {
    radioProviders.clear();
    container = ProviderContainer();
  });
  tearDown(() {
    container.dispose();
    radioProviders.clear();
  });

  test('radio directories put the default plugin first and drop the rest', () {
    final state = MetadataPluginState(
      plugins: [_radio('Alpha'), _nonRadio(), _radio('Beta')],
      defaultRadioPlugin: 2,
    );

    final providers = radioProvidersFor(container.read(_refProvider), state);

    expect(providers.map((p) => p.id), ['Beta', 'Alpha']);
    expect(providers.every((p) => p is MetadataPluginRadioDirectoryProvider),
        isTrue);
  });

  test('with no default, every radio plugin is listed and non-radio skipped',
      () {
    final state = MetadataPluginState(
      plugins: [_radio('Alpha'), _nonRadio(), _radio('Beta')],
    );

    final providers = radioProvidersFor(container.read(_refProvider), state);
    expect(providers.map((p) => p.id), ['Alpha', 'Beta']);
  });

  test('station family serves page one and appends page two deduped', () async {
    radioProviders.add(
      _PagingProvider(
        'fake',
        List.generate(5, (i) => _station('s$i')),
        pageSize: 2,
      ),
    );

    // Pin the autoDispose family instance for the whole test: fetchMore mutates
    // the same instance we read back below.
    final sub = container.listen(radioStationsProvider(_popular), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(radioStationsProvider(_popular).notifier);
    var page = await container.read(radioStationsProvider(_popular).future);
    expect(page.items.map((s) => s.id).toList(), ['s0', 's1']);

    await notifier.fetchMore();
    page = container.read(radioStationsProvider(_popular)).requireValue;
    expect(page.items.map((s) => s.id).toList(), ['s0', 's1', 's2', 's3']);

    await notifier.fetchMore();
    page = container.read(radioStationsProvider(_popular)).requireValue;
    expect(page.items.map((s) => s.id).toList(),
        ['s0', 's1', 's2', 's3', 's4']);
    expect(page.hasMore, isFalse);

    // A completed list is not extended by a redundant fetchMore call.
    await notifier.fetchMore();
    expect(
      container.read(radioStationsProvider(_popular)).requireValue.items.length,
      5,
    );
  });

  test('fetchMore dedupes a station an overlapping second page re-serves',
      () async {
    radioProviders.add(_OverlappingProvider());

    const query = (tag: null, country: null, search: 'rock');
    final sub = container.listen(radioStationsProvider(query), (_, __) {});
    addTearDown(sub.close);

    final notifier = container.read(radioStationsProvider(query).notifier);
    await container.read(radioStationsProvider(query).future);

    await notifier.fetchMore();

    final page = container.read(radioStationsProvider(query)).requireValue;
    expect(page.items.map((s) => s.id).toList(), ['a', 'b', 'c']);
    expect(page.hasMore, isFalse);
  });

  test('a revisit reuses the fetched page instead of refetching', () async {
    final provider = _CountingProvider();
    radioProviders.add(provider);

    // First visit: the page mounts and the directory is asked for the popular
    // page, the tag list and the country list.
    var sub = container.listen(radioStationsProvider(_popular), (_, __) {});
    var tagSub = container.listen(radioTagsProvider, (_, __) {});
    var countrySub = container.listen(radioCountriesProvider, (_, __) {});
    addTearDown(tagSub.close);
    addTearDown(countrySub.close);

    await container.read(radioStationsProvider(_popular).future);
    await container.read(radioTagsProvider.future);
    await container.read(radioCountriesProvider.future);

    expect(provider.stationCalls, 1);
    expect(provider.tagCalls, 1);
    expect(provider.countryCalls, 1);

    // The user leaves the Radio tab: the page unmounts and its listeners go
    // away with it.
    sub.close();
    tagSub.close();
    countrySub.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Second visit: the answers are still held, so the directory is not asked
    // again - this is what made the Radio page refetch itself on every visit.
    sub = container.listen(radioStationsProvider(_popular), (_, __) {});
    tagSub = container.listen(radioTagsProvider, (_, __) {});
    countrySub = container.listen(radioCountriesProvider, (_, __) {});
    addTearDown(sub.close);
    addTearDown(tagSub.close);
    addTearDown(countrySub.close);

    final page = await container.read(radioStationsProvider(_popular).future);
    expect(page.items.map((s) => s.id), ['s0']);
    expect(provider.stationCalls, 1, reason: 'the revisit must not refetch');
    expect(provider.tagCalls, 1);
    expect(provider.countryCalls, 1);
  });

  test('a distinct query keys a distinct family instance', () async {
    final p = _PagingProvider('fake', [_station('x')]);
    radioProviders.add(p);

    const byTagQuery = (tag: 'jazz', country: null, search: null);
    const bySearchQuery = (tag: null, country: null, search: 'jazz');

    final t = container.listen(radioStationsProvider(byTagQuery), (_, __) {});
    final s = container.listen(radioStationsProvider(bySearchQuery), (_, __) {});
    addTearDown(t.close);
    addTearDown(s.close);

    await container.read(radioStationsProvider(byTagQuery).future);
    await container.read(radioStationsProvider(bySearchQuery).future);

    expect(p.seen, contains((tag: 'jazz', country: null, search: null)));
    expect(p.seen, contains((tag: null, country: null, search: 'jazz')));
  });

  test('tags provider skips a broken and an empty directory', () async {
    radioProviders.add(_MetaProvider('broken', broken: true));
    radioProviders.add(_MetaProvider('empty'));
    radioProviders.add(
      _MetaProvider('good', tagList: [RadioTag(name: 'rock', stationCount: 3)]),
    );

    final tags = await container.read(radioTagsProvider.future);
    expect(tags.map((t) => t.name), ['rock']);
  });

  test('countries provider serves the first non-empty directory', () async {
    radioProviders.add(_MetaProvider('empty'));
    radioProviders.add(
      _MetaProvider(
        'good',
        countryList: [RadioCountry(code: 'us', name: 'United States')],
      ),
    );

    final countries = await container.read(radioCountriesProvider.future);
    expect(countries.map((c) => c.code), ['us']);
  });

  group('pagination failure is contained', () {
    test('fetchMore reports failure without throwing into its void caller',
        () async {
      radioProviders.add(_TopUpFailsProvider());

      final sub = container.listen(radioStationsProvider(_popular), (_, __) {});
      addTearDown(sub.close);

      final notifier = container.read(radioStationsProvider(_popular).notifier);
      await container.read(radioStationsProvider(_popular).future);

      // The real caller is PlaybuttonView's `final VoidCallback onRequestMore`,
      // which discards the returned future — so a throw here becomes an
      // unhandled async error with no error state and paging silently dies.
      await expectLater(notifier.fetchMore(), completes);

      final page = container.read(radioStationsProvider(_popular)).requireValue;
      expect(page.items.map((s) => s.id).toList(), ['a'],
          reason: 'the page already on screen survives a failed top-up');
    });

    test('fetchMore can be retried after a failure', () async {
      final flaky = _FlakyTopUpProvider();
      radioProviders.add(flaky);

      final sub = container.listen(radioStationsProvider(_popular), (_, __) {});
      addTearDown(sub.close);

      final notifier = container.read(radioStationsProvider(_popular).notifier);
      await container.read(radioStationsProvider(_popular).future);

      await expectLater(notifier.fetchMore(), completes);
      // The guard must have been released, or paging can never recover.
      await expectLater(notifier.fetchMore(), completes);

      expect(flaky.topUpAttempts, 2);
      expect(
        container.read(radioStationsProvider(_popular)).requireValue.items.length,
        2,
      );
    });
  });

  group('a registry rewrite mid-request does not corrupt the fan-out', () {
    // The real sync does exactly this: removeWhere + addAll on the global list,
    // from a plugins_table listener, while a fan-out is in flight. The loop is
    // iterating the same list object it is being rewritten under, so stepping to
    // the next element throws ConcurrentModificationError — and it escapes the
    // per-provider try/catch, which only wraps the request call.
    void seedMutator() {
      radioProviders
        ..clear()
        ..add(_RegistryMutatingProvider(() {
          // A second plugin directory becomes available mid-flight.
          radioProviders.add(_PagingProvider('late', [_station('z')]));
        }));
    }

    test('stations degrade to an empty page instead of an error', () async {
      seedMutator();

      final page = await container.read(radioStationsProvider(_popular).future);
      expect(page.items, isEmpty,
          reason: 'a registry rewrite mid-flight must not surface an error '
              'state; the sync invalidates the family, which re-runs anyway');
    });

    test('tags degrade to empty instead of an error', () async {
      seedMutator();

      final tags = await container.read(radioTagsProvider.future);
      expect(tags, isEmpty);
    });

    test('countries degrade to empty instead of an error', () async {
      seedMutator();

      final countries = await container.read(radioCountriesProvider.future);
      expect(countries, isEmpty);
    });
  });
}

/// Page one always answers; page two fails [failures] times, then works.
class _FlakyTopUpProvider implements RadioDirectoryProvider {
  int topUpAttempts = 0;
  int failures = 1;

  @override
  final String id = 'flaky-retry';

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset == 0) {
      return SpotubePaginationResponseObject(
        limit: 1,
        nextOffset: 1,
        total: 2,
        hasMore: true,
        items: [_station('a')],
      );
    }
    topUpAttempts++;
    if (topUpAttempts <= failures) throw StateError('page two down');
    return SpotubePaginationResponseObject(
      limit: 1,
      nextOffset: null,
      total: 2,
      hasMore: false,
      items: [_station('b')],
    );
  }

  @override
  Future<List<RadioTag>> tags({int limit = 50}) async => const [];

  @override
  Future<List<RadioCountry>> countries({int limit = 100}) async => const [];

  @override
  Future<RadioStation?> byId(String id) async => null;
}
