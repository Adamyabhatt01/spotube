// Lifecycle rule for metadata providers: auto-disposed with a short
// keep-alive instead of retained forever (or refetched on every revisit).
// These tests pin the keep-alive half — a navigation away and back inside
// the window must not rebuild, i.e. must cost zero HTTP. (The disposal half
// is structural: AutoDispose + cacheFor, review-verified; exercising it
// would mean waiting out the 5-minute keep-alive.)

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/album/releases.dart';
import 'package:spotube/provider/metadata_plugin/artist/albums.dart';
import 'package:spotube/provider/metadata_plugin/artist/related.dart';
import 'package:spotube/provider/metadata_plugin/artist/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/browse/section_items.dart';
import 'package:spotube/provider/metadata_plugin/browse/sections.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/search/albums.dart';
import 'package:spotube/provider/metadata_plugin/search/artists.dart';
import 'package:spotube/provider/metadata_plugin/search/playlists.dart';
import 'package:spotube/provider/metadata_plugin/search/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/album.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/metadata_plugin/tracks/track.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/album.dart';
import 'package:spotube/services/metadata/endpoints/artist.dart';
import 'package:spotube/services/metadata/endpoints/browse.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/endpoints/search.dart';
import 'package:spotube/services/metadata/endpoints/track.dart';
import 'package:spotube/services/metadata/metadata.dart';

SpotubePaginationResponseObject<T> _emptyPage<T>() {
  return SpotubePaginationResponseObject<T>(
    limit: 20,
    nextOffset: null,
    total: 0,
    hasMore: false,
    items: const [],
  );
}

class _CountingBrowse implements MetadataPluginBrowseEndpoint {
  int sectionsCalls = 0;
  int itemsCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<SpotubeBrowseSectionObject<Object>>>
      sections({int? offset, int? limit}) async {
    sectionsCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<Object>> sectionItems(
    String id, {
    int? offset,
    int? limit,
  }) async {
    itemsCalls++;
    return _emptyPage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingArtist implements MetadataPluginArtistEndpoint {
  int albumsCalls = 0;
  int relatedCalls = 0;
  int topTracksCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> topTracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    topTracksCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String id, {
    int? offset,
    int? limit,
  }) async {
    albumsCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> related(
    String id, {
    int? offset,
    int? limit,
  }) async {
    relatedCalls++;
    return _emptyPage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingAlbum implements MetadataPluginAlbumEndpoint {
  int releasesCalls = 0;
  int tracksCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    tracksCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> releases({
    int? offset,
    int? limit,
  }) async {
    releasesCalls++;
    return _emptyPage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingSearch implements MetadataPluginSearchEndpoint {
  int tracksCalls = 0;
  int albumsCalls = 0;
  int artistsCalls = 0;
  int playlistsCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String query, {
    int? limit,
    int? offset,
  }) async {
    tracksCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>> albums(
    String query, {
    int? limit,
    int? offset,
  }) async {
    albumsCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>> artists(
    String query, {
    int? limit,
    int? offset,
  }) async {
    artistsCalls++;
    return _emptyPage();
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      playlists(
    String query, {
    int? limit,
    int? offset,
  }) async {
    playlistsCalls++;
    return _emptyPage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingPlaylistTracks implements MetadataPluginPlaylistEndpoint {
  int tracksCalls = 0;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> tracks(
    String id, {
    int? offset,
    int? limit,
  }) async {
    tracksCalls++;
    return _emptyPage();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingTrack implements MetadataPluginTrackEndpoint {
  int getTrackCalls = 0;

  @override
  Future<SpotubeFullTrackObject> getTrack(String id) async {
    getTrackCalls++;
    return SpotubeFullTrackObject(
      id: id,
      name: 'Track $id',
      externalUri: 'https://example.test/track/$id',
      artists: const [],
      album: SpotubeSimpleAlbumObject(
        id: 'al1',
        name: 'Album',
        externalUri: 'https://example.test/album/al1',
        artists: const [],
        albumType: SpotubeAlbumType.album,
      ),
      durationMs: 180000,
      isrc: 'ISRC',
      explicit: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPlugin implements MetadataPlugin {
  _StubPlugin({
    required this.browse,
    required this.artist,
    required this.album,
    required this.track,
    required this.search,
    required this.playlist,
  });

  @override
  final _CountingBrowse browse;
  @override
  final _CountingArtist artist;
  @override
  final _CountingAlbum album;
  @override
  final _CountingTrack track;
  @override
  final _CountingSearch search;
  @override
  final _CountingPlaylistTracks playlist;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  // Async on purpose, like the real authenticator: dependents observe a
  // loading emission before data, which is exactly the echo the `.future`
  // watches in the providers under test exist to suppress.
  @override
  FutureOr<bool> build() async => true;
}

void main() {
  AppLogger.initialize(false);

  late _CountingBrowse browse;
  late _CountingArtist artist;
  late _CountingAlbum album;
  late _CountingTrack track;
  late _CountingSearch search;
  late _CountingPlaylistTracks playlistTracks;
  late ProviderContainer container;
  late AppDatabase database;

  setUp(() {
    browse = _CountingBrowse();
    artist = _CountingArtist();
    album = _CountingAlbum();
    track = _CountingTrack();
    search = _CountingSearch();
    playlistTracks = _CountingPlaylistTracks();
    final plugin = _StubPlugin(
      browse: browse,
      artist: artist,
      album: album,
      track: track,
      search: search,
      playlist: playlistTracks,
    );
    database = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        metadataPluginProvider.overrideWith((ref) async => plugin),
        metadataPluginAuthenticatedProvider.overrideWith(
          () => _AlwaysAuthenticated(),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  /// Visits [provider] twice with no listener in between (a navigation away
  /// and back) and returns the endpoint call count afterwards.
  Future<void> visitTwice(
    ProviderListenable<AsyncValue<Object?>> provider,
  ) async {
    for (var visit = 0; visit < 2; visit++) {
      final sub = container.listen(provider, (_, __) {});
      try {
        for (var i = 0; i < 500 && sub.read().isLoading; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        sub.read().requireValue;
      } finally {
        sub.close();
      }
    }
  }

  test('track page revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginTrackProvider('t1'));
    expect(track.getTrackCalls, 1,
        reason: 'second visit inside the window must not refetch');
  });

  test('browse sections revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginBrowseSectionsProvider);
    expect(browse.sectionsCalls, 1);
  });

  test('drilled-down section revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginBrowseSectionItemsProvider('s1'));
    expect(browse.itemsCalls, 1);
  });

  test('new releases revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginAlbumReleasesProvider);
    expect(album.releasesCalls, 1);
  });

  test('artist albums revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginArtistAlbumsProvider('a1'));
    expect(artist.albumsCalls, 1);
  });

  test('related artists revisit stays on the keep-alive', () async {
    await visitTwice(metadataPluginArtistRelatedArtistsProvider('a1'));
    expect(artist.relatedCalls, 1);
  });

  test('artist top tracks fetch once per mount, not per plugin emission',
      () async {
    await visitTwice(metadataPluginArtistTopTracksProvider('a1'));
    expect(artist.topTracksCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('playlist tracks fetch once per mount, not per plugin emission',
      () async {
    await visitTwice(metadataPluginPlaylistTracksProvider('p1'));
    expect(playlistTracks.tracksCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('album tracks fetch once per mount, not per plugin emission', () async {
    await visitTwice(metadataPluginAlbumTracksProvider('al1'));
    expect(album.tracksCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('search tracks fetch once per mount, not per plugin emission', () async {
    await visitTwice(metadataPluginSearchTracksProvider('query'));
    expect(search.tracksCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('search albums fetch once per mount, not per plugin emission', () async {
    await visitTwice(metadataPluginSearchAlbumsProvider('query'));
    expect(search.albumsCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('search artists fetch once per mount, not per plugin emission',
      () async {
    await visitTwice(metadataPluginSearchArtistsProvider('query'));
    expect(search.artistsCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });

  test('search playlists fetch once per mount, not per plugin emission',
      () async {
    await visitTwice(metadataPluginSearchPlaylistsProvider('query'));
    expect(search.playlistsCalls, 1,
        reason: 'the loading emission must not trigger a second page-1 fetch');
  });
}
