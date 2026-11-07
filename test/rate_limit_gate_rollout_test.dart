// Regression this guards: every metadata provider used to call the plugin
// directly, so once Spotify answered 429 the next navigation, next keystroke
// and next screen each probed the wall again. The session gate now wraps
// these builds: the first 429 still surfaces, everything after it fails fast
// with RateLimitedUntilException until the cooldown expires.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/album/releases.dart';
import 'package:spotube/provider/metadata_plugin/artist/albums.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:spotube/provider/metadata_plugin/artist/related.dart';
import 'package:spotube/provider/metadata_plugin/artist/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/browse/section_items.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/provider/metadata_plugin/search/albums.dart';
import 'package:spotube/provider/metadata_plugin/search/artists.dart';
import 'package:spotube/provider/metadata_plugin/search/playlists.dart';
import 'package:spotube/provider/metadata_plugin/search/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/album.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/tracks/track.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/artist.dart';
import 'package:spotube/services/metadata/endpoints/browse.dart';
import 'package:spotube/services/metadata/endpoints/search.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/metadata.dart';

const _vmCrossed429 =
    'DioException [bad response]: This exception was thrown because the '
    'response has a status code of 429 and RequestOptions.validateStatus was '
    'configured to throw for this status code.';

/// Real timers, so the budget has to be far shorter than
/// [metadataRequestBudget] for these to run quickly.
const _testBudget = Duration(milliseconds: 10);

SpotubePaginationResponseObject<T> _page<T>(List<T> items) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

/// Endpoint fakes: only the members the providers under test touch are
/// implemented, [noSuchMethod] stands in for the rest of the interface.
class _StubEndpoint {
  _StubEndpoint(this.failure);

  /// Null means the endpoint answers instead of rate-limiting.
  final Object? failure;
  int calls = 0;

  void _fire() {
    ++calls;
    final error = failure;
    // The Hetu VM hands DioException over as its stringified form, so the
    // stubs reproduce that rather than throwing a typed exception.
    if (error != null) throw StateError(error.toString());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubBrowse extends _StubEndpoint
    implements MetadataPluginBrowseEndpoint {
  _StubBrowse(super.failure);

  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      sections({
    int? offset,
    int? limit,
  }) async {
    _fire();
    return _page([]);
  }
}

class _StubSearch extends _StubEndpoint
    implements MetadataPluginSearchEndpoint {
  _StubSearch(super.failure);

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String query, {
    int? limit,
    int? offset,
  }) async {
    _fire();
    return _page([]);
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String query, {
    int? limit,
    int? offset,
  }) async {
    _fire();
    return _page([]);
  }
}

class _StubArtist extends _StubEndpoint
    implements MetadataPluginArtistEndpoint {
  _StubArtist(super.failure);

  @override
  Future<SpotubeFullArtistObject> getArtist(String id) async {
    _fire();
    return SpotubeFullArtistObject(
      id: id,
      name: 'Artist $id',
      externalUri: 'https://example.test/artist/$id',
    );
  }
}

class _StubMetadataPlugin implements MetadataPlugin {
  _StubMetadataPlugin({
    _StubBrowse? browse,
    _StubSearch? search,
    _StubArtist? artist,
  })  : browse = browse ?? _StubBrowse(null),
        search = search ?? _StubSearch(null),
        artist = artist ?? _StubArtist(null);

  @override
  final _StubBrowse browse;

  @override
  final _StubSearch search;

  @override
  final _StubArtist artist;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  FutureOr<bool> build() => true;
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  ProviderContainer containerWith(MetadataPlugin plugin) {
    final container = ProviderContainer(
      overrides: [
        metadataPluginProvider.overrideWith((ref) async => plugin),
        metadataPluginAuthenticatedProvider.overrideWith(
          () => _AlwaysAuthenticated(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('runGated', () {
    test('an interactive read waits out nothing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);

      var calls = 0;
      await expectLater(
        runGated<int>(gate, () async {
          ++calls;
          throw StateError(_vmCrossed429);
        }),
        throwsStateError,
      );
      expect(calls, 1, reason: 'no in-request cooldown retries');
      expect(gate.isBlocked, isTrue);
    });

    test('the saved-list retry ladder is unchanged', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);

      var calls = 0;
      final result = await runGated<int>(
        gate,
        () async {
          ++calls;
          if (calls <= 2) throw StateError(_vmCrossed429);
          return calls;
        },
        maxRetries: maxRateLimitAutoRetries,
        cooldown: Duration.zero,
      );

      expect(result, 3);
      expect(gate.isBlocked, isFalse, reason: 'success reopens the gate');
    });

    // The plugin's HttpClient is built with no options, so a stalled-but-open
    // connection to Spotify is a future that never completes. Only the budget
    // ends it.
    test('a stalled request is cut off at the budget', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);

      await expectLater(
        runGated<int>(
          gate,
          () => Completer<int>().future,
          budget: _testBudget,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a timeout is not retried as a rate limit', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);

      var calls = 0;
      await expectLater(
        runGated<int>(
          gate,
          () {
            ++calls;
            return Completer<int>().future;
          },
          maxRetries: maxRateLimitAutoRetries,
          cooldown: Duration.zero,
          budget: _testBudget,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1, reason: 'a stall is not a throttle, so no cooldown wait');
    });

    test('a timeout leaves unrelated reads alone', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gate = container.read(rateLimitGateProvider.notifier);

      await expectLater(
        runGated<int>(gate, () => Completer<int>().future, budget: _testBudget),
        throwsA(isA<TimeoutException>()),
      );
      expect(gate.isBlocked, isFalse);

      // A screen the rate-limit gate would have suppressed still succeeds.
      expect(
        await runGated<int>(gate, () async => 7, budget: _testBudget),
        7,
      );
    });
  });

  test('a rate-limited search stops the next keystroke', () async {
    final search = _StubSearch(_vmCrossed429);
    final container = containerWith(_StubMetadataPlugin(search: search));

    await expectLater(
      container.read(metadataPluginSearchTracksProvider('wa').future),
      throwsStateError,
    );
    expect(search.calls, 1);

    // Four more family providers per keystroke; none may reach the plugin.
    await expectLater(
      container.read(metadataPluginSearchTracksProvider('was').future),
      throwsA(isA<RateLimitedUntilException>()),
    );
    await expectLater(
      container.read(metadataPluginSearchAlbumsProvider('wass').future),
      throwsA(isA<RateLimitedUntilException>()),
    );
    expect(search.calls, 1, reason: 'no re-probing while the gate is closed');
  });

  test('browse and artist builds are gated too', () async {
    final browse = _StubBrowse(_vmCrossed429);
    final artist = _StubArtist(_vmCrossed429);
    final container = containerWith(
      _StubMetadataPlugin(browse: browse, artist: artist),
    );

    await expectLater(
      container.read(metadataPluginBrowseSectionsProvider.future),
      throwsStateError,
    );
    expect(browse.calls, 1);

    // A different screen, built while the gate is shut.
    await expectLater(
      container.read(metadataPluginArtistProvider('a1').future),
      throwsA(isA<RateLimitedUntilException>()),
    );
    expect(artist.calls, 0);
    expect(browse.calls, 1);
  });

  test('an invalidated provider still fails fast', () async {
    final browse = _StubBrowse(_vmCrossed429);
    final container = containerWith(_StubMetadataPlugin(browse: browse));

    await expectLater(
      container.read(metadataPluginBrowseSectionsProvider.future),
      throwsStateError,
    );
    container.invalidate(metadataPluginBrowseSectionsProvider);

    await expectLater(
      container.read(metadataPluginBrowseSectionsProvider.future),
      throwsA(isA<RateLimitedUntilException>()),
    );
    expect(browse.calls, 1);
  });

  test('one 429 covers a whole screen burst: 16 reads, 1 plugin call',
      () async {
    final browse = _StubBrowse(_vmCrossed429);
    final search = _StubSearch(_vmCrossed429);
    final artist = _StubArtist(_vmCrossed429);
    final container = containerWith(
      _StubMetadataPlugin(browse: browse, search: search, artist: artist),
    );

    // Home's first section rate-limits, and every later read of the burst
    // belongs to a screen the user actually opens next.
    await expectLater(
      container.read(metadataPluginBrowseSectionsProvider.future),
      throwsStateError,
    );

    final reads = <Future<Object?> Function()>[
      () =>
          container.read(metadataPluginBrowseSectionItemsProvider('s1').future),
      () => container.read(metadataPluginAlbumReleasesProvider.future),
      () => container.read(metadataPluginSearchAllProvider('flawed').future),
      () => container.read(metadataPluginSearchTracksProvider('flaw').future),
      () => container.read(metadataPluginSearchAlbumsProvider('flaw').future),
      () => container.read(metadataPluginSearchArtistsProvider('flaw').future),
      () =>
          container.read(metadataPluginSearchPlaylistsProvider('flaw').future),
      () => container.read(metadataPluginArtistProvider('a1').future),
      () => container.read(metadataPluginArtistAlbumsProvider('a1').future),
      () => container.read(metadataPluginArtistTopTracksProvider('a1').future),
      () => container
          .read(metadataPluginArtistRelatedArtistsProvider('a1').future),
      () => container.read(metadataPluginTrackProvider('t1').future),
      () => container.read(metadataPluginAlbumTracksProvider('a1').future),
      () => container.read(metadataPluginPlaylistProvider('p1').future),
      () => container.read(metadataPluginPlaylistTracksProvider('p1').future),
    ];

    for (final read in reads) {
      await expectLater(read(), throwsA(isA<RateLimitedUntilException>()));
    }

    // Before the gate each of these was its own request to a rate-limited
    // endpoint; the stubs prove none of them got that far.
    expect(browse.calls, 1);
    expect(search.calls, 0);
    expect(artist.calls, 0);
  });

  test('an unrelated error leaves the gate open', () async {
    final artist = _StubArtist(StateError('boom'));
    final container = containerWith(_StubMetadataPlugin(artist: artist));

    await expectLater(
      container.read(metadataPluginArtistProvider('a1').future),
      throwsStateError,
    );
    expect(container.read(rateLimitGateProvider), isNull);

    final second = _StubArtist(null);
    final openContainer = containerWith(_StubMetadataPlugin(artist: second));
    await openContainer.read(metadataPluginArtistProvider('a2').future);
    expect(second.calls, 1);
  });
}
