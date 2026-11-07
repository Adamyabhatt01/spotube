// Cover-tap playback for sidebar pins: the fetch contract behind
// `usePlaylistPlay` — Liked routes to the (snapshot-backed) saved-tracks
// provider, a regular playlist reads the network first and the mirror on
// failure, and an unmirrored unreachable playlist throws so the caller can
// toast instead of loading nothing.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/playlist/use_playlist_play.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

import 'support/common_fakes.dart';

SpotubeFullTrackObject _track(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST000000$id',
    explicit: false,
  );
}

SpotubeSimplePlaylistObject _playlist(String id) {
  return SpotubeSimplePlaylistObject(
    id: id,
    name: 'Playlist $id',
    description: 'A playlist under test',
    externalUri: 'https://example.test/playlist/$id',
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

SpotubePaginationResponseObject<SpotubeFullTrackObject> _page(
  List<SpotubeFullTrackObject> items,
) {
  return SpotubePaginationResponseObject(
    limit: items.length,
    nextOffset: null,
    total: items.length,
    hasMore: false,
    items: items,
  );
}

/// Saved-tracks stub serving a canned page: the network never answers in
/// these tests, and the point is routing, not the snapshot machinery (which
/// `library_snapshot_test.dart` covers).
class _StubSavedTracks extends MetadataPluginSavedTracksNotifier {
  _StubSavedTracks(this.page);

  final SpotubePaginationResponseObject<SpotubeFullTrackObject> page;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> build() async =>
      page;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
    int offset,
    int limit,
  ) async =>
      page;
}

/// Regular-playlist stub serving a canned page, proving the network path is
/// preferred whenever it answers.
class _StubPlaylistTracks extends MetadataPluginPlaylistTracksNotifier {
  _StubPlaylistTracks(this.page);

  final SpotubePaginationResponseObject<SpotubeFullTrackObject> page;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> build(
    String arg,
  ) async =>
      page;

  @override
  Future<SpotubePaginationResponseObject<SpotubeFullTrackObject>> fetch(
    int offset,
    int limit,
  ) async =>
      page;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(() {
    AppLogger.initialize(false);
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  ProviderContainer containerWith({List<Override> extra = const []}) {
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // No default plugin: the real playlist-tracks notifier's
        // `metadataPlugin` getter throws noDefaultMetadataPlugin without
        // spinning up a Hetu VM — the offline shape the mirror fallback
        // exists for.
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(PreferencesTable.defaults()),
        ),
        ...extra,
      ],
    );
    return container;
  }

  /// Seeds a mirrored playlist whose members all have completed download
  /// rows, so the mirror join yields them in membership order.
  Future<void> seedMirror(
    String playlistId,
    List<SpotubeFullTrackObject> tracks,
  ) async {
    await writePlaylistMirror(
      db,
      playlistId: playlistId,
      playlistData: jsonEncode(_playlist(playlistId).toJson()),
      trackCount: tracks.length,
    );
    await writePlaylistMembership(
      db,
      playlistId: playlistId,
      trackIds: [for (final track in tracks) track.id],
    );
    for (final track in tracks) {
      await writeDownloadStatus(
        db,
        DownloadRecord(
          trackId: track.id,
          filePath: '/tmp/${track.id}.weba',
          baseName: track.id,
          status: DownloadPersistedStatus.completed,
          trackData: jsonEncode(track.toJson()),
        ),
      );
    }
  }

  group('fetchPlaylistInitialTracks', () {
    test('liked id reads the saved-tracks provider', () async {
      final tracks = [_track('a'), _track('b')];
      final container = containerWith(extra: [
        metadataPluginSavedTracksProvider
            .overrideWith(() => _StubSavedTracks(_page(tracks))),
      ]);

      final initial = await fetchPlaylistInitialTracks(
        container.read,
        _playlist(likedTracksPlaylistId),
      );

      expect([for (final track in initial) track.id], ['a', 'b']);
    });

    test('network answer wins over the mirror', () async {
      final network = [_track('net-1'), _track('net-2')];
      await seedMirror('playlist-a', [_track('mirror-1')]);
      final container = containerWith(extra: [
        metadataPluginPlaylistTracksProvider
            .overrideWith(() => _StubPlaylistTracks(_page(network))),
      ]);

      final initial = await fetchPlaylistInitialTracks(
        container.read,
        _playlist('playlist-a'),
      );

      expect(
        [for (final track in initial) track.id],
        ['net-1', 'net-2'],
        reason:
            'a reachable network must not be shadowed by stale mirror rows',
      );
    });

    test('unreachable network falls back to the mirror in order', () async {
      await seedMirror('playlist-a', [_track('m1'), _track('m2')]);
      final container = containerWith();

      final initial = await fetchPlaylistInitialTracks(
        container.read,
        _playlist('playlist-a'),
      );

      expect([for (final track in initial) track.id], ['m1', 'm2']);
    });

    test('unreachable and never mirrored throws', () async {
      final container = containerWith();

      await expectLater(
        fetchPlaylistInitialTracks(container.read, _playlist('playlist-a')),
        throwsA(isA<MetadataPluginException>()),
      );
    });
  });
}
