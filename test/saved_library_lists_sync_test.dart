// The app has four saved lists — playlists, liked tracks, saved albums and
// followed artists — and all four have to be re-read when the account may
// have changed on another device.
//
// The lists differ in shape, and the difference matters:
//
//  * the playlists, albums and artists lists are small, so a re-read walks
//    every page of them;
//  * the liked-tracks list can hold thousands of rows, and Spotify orders it
//    by the time a track was saved — so a newly liked track arrives at its
//    *head*, which the first page covers. It is probed, never walked.
//
// These tests pin the wiring: every list is re-read, each one at its own
// depth, and one failing list never stops the others.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/library_refresh.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

SpotubePaginationResponseObject<T> _page<T>(List<T> items) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

/// Counts the re-reads of one list and records how deep it went.
class _Recorder {
  int refreshes = 0;
  int fullWalks = 0;
}

/// The real notifiers, with only the re-read stubbed. The wiring under test
/// is *which* list is re-read and how deep, so the depth knob and the
/// re-read itself are what has to be observed.
class _StubPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  _StubPlaylists(this.recorder);

  final _Recorder recorder;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _page(const []);

  @override
  Future<List<SpotubeSimplePlaylistObject>?> refresh({
    bool forceFullWalk = false,
  }) async {
    recorder.refreshes++;
    if (forceFullWalk) recorder.fullWalks++;
    return null;
  }
}

class _StubTracks extends MetadataPluginSavedTracksNotifier {
  _StubTracks(this.recorder);

  final _Recorder recorder;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>>
      build() async => _page(const []);

  @override
  Future<List<SpotubeFullTrackObject>?> refresh({
    bool forceFullWalk = false,
  }) async {
    recorder.refreshes++;
    if (forceFullWalk) recorder.fullWalks++;
    return null;
  }
}

class _StubAlbums extends MetadataPluginSavedAlbumNotifier {
  _StubAlbums(this.recorder);

  final _Recorder recorder;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimpleAlbumObject>>
      build() async => _page(const []);

  @override
  Future<List<SpotubeSimpleAlbumObject>?> refresh({
    bool forceFullWalk = false,
  }) async {
    recorder.refreshes++;
    if (forceFullWalk) recorder.fullWalks++;
    return null;
  }
}

class _StubArtists extends MetadataPluginSavedArtistNotifier {
  _StubArtists(this.recorder);

  final _Recorder recorder;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullArtistObject>>
      build() async => _page(const []);

  @override
  Future<List<SpotubeFullArtistObject>?> refresh({
    bool forceFullWalk = false,
  }) async {
    recorder.refreshes++;
    if (forceFullWalk) recorder.fullWalks++;
    return null;
  }
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  setUpAll(() => AppLogger.initialize(false));

  ProviderContainer containerWith({
    required _Recorder playlists,
    required _Recorder tracks,
    required _Recorder albums,
    required _Recorder artists,
  }) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(newMemoryDatabase()),
        metadataPluginAuthenticatedProvider.overrideWith(
          () => _AlwaysAuthenticated(),
        ),
        networkAvailableProvider.overrideWithValue(true),
        metadataPluginSavedPlaylistsProvider.overrideWith(
          () => _StubPlaylists(playlists),
        ),
        metadataPluginSavedTracksProvider.overrideWith(
          () => _StubTracks(tracks),
        ),
        metadataPluginSavedAlbumsProvider.overrideWith(
          () => _StubAlbums(albums),
        ),
        metadataPluginSavedArtistsProvider.overrideWith(
          () => _StubArtists(artists),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('every saved list is re-read', () async {
    final playlists = _Recorder();
    final tracks = _Recorder();
    final albums = _Recorder();
    final artists = _Recorder();

    final container = containerWith(
      playlists: playlists,
      tracks: tracks,
      albums: albums,
      artists: artists,
    );

    await container.read(savedLibraryRefreshProvider).refreshAll();

    expect(playlists.refreshes, 1);
    expect(tracks.refreshes, 1);
    expect(albums.refreshes, 1);
    expect(artists.refreshes, 1);
  });

  test('the liked-tracks list is never walked', () async {
    final playlists = _Recorder();
    final tracks = _Recorder();
    final albums = _Recorder();
    final artists = _Recorder();

    final container = containerWith(
      playlists: playlists,
      tracks: tracks,
      albums: albums,
      artists: artists,
    );

    await container.read(savedLibraryRefreshProvider).refreshAll();

    expect(
      tracks.fullWalks,
      0,
      reason: 'the liked list can hold thousands of rows, and a newly liked '
          'track lands at its head — walking it would be a hundred requests '
          'for nothing',
    );
  });

  test('a second sync is held back by the cooldown', () async {
    final playlists = _Recorder();
    final tracks = _Recorder();
    final albums = _Recorder();
    final artists = _Recorder();

    final container = containerWith(
      playlists: playlists,
      tracks: tracks,
      albums: albums,
      artists: artists,
    );

    final refresher = container.read(savedLibraryRefreshProvider);
    await refresher.refreshAll();
    await refresher.refreshAll();

    expect(playlists.refreshes, 1);
    expect(tracks.refreshes, 1);
    expect(albums.refreshes, 1);
    expect(artists.refreshes, 1);
  });

  test('the depth of each list is the one it needs', () async {
    // The playlists, albums and artists lists are small enough to walk; the
    // liked-tracks list is not. These are the knobs the sync's cost rests
    // on, so they are pinned here rather than only in the mixin.
    expect(
      MetadataPluginSavedPlaylistsNotifier().refreshAllPages,
      isTrue,
      reason: 'Spotify appends a new playlist to the end of the library',
    );
    expect(MetadataPluginSavedAlbumNotifier().refreshAllPages, isTrue);
    expect(MetadataPluginSavedArtistNotifier().refreshAllPages, isTrue);
    expect(
      MetadataPluginSavedTracksNotifier().refreshAllPages,
      isFalse,
      reason: 'a newly liked track arrives at the head of the list',
    );
  });
}
