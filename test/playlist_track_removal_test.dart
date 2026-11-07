// Removal of a track from a Spotify playlist has to land in two places, and for
// a long time it landed in neither:
//
//  - upstream, through the bundled plugin, whose `removeTracks` asserted on an
//    identifier that does not exist as a parameter, so every call threw before
//    reaching the network;
//  - locally, in the download mirror's membership rows, which nothing deleted —
//    so the playlist page's reload fallback kept re-painting the track the user
//    had just removed.
//
// The plugin half is verified in the plugin repo and on a phone (the AVD has no
// Spotify credentials). These tests pin the host half: the delete is scoped to
// the one playlist, it never touches the downloaded file, and it only happens
// once Spotify has confirmed.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/metadata.dart';

import 'support/common_fakes.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://open.spotify.com/user/$id',
    );

SpotubeSimplePlaylistObject _playlist(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
    );

SpotubePaginationResponseObject<T> _page<T>(List<T> items) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

class _FakePlaylistEndpoint implements MetadataPluginPlaylistEndpoint {
  _FakePlaylistEndpoint({this.removeError});

  final Object? removeError;
  final List<({String playlistId, List<String> trackIds})> removeCalls = [];

  @override
  Future<void> removeTracks(
    String playlistId, {
    required List<String> trackIds,
  }) async {
    removeCalls.add((playlistId: playlistId, trackIds: List.of(trackIds)));
    if (removeError != null) throw removeError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMetadataPlugin implements MetadataPlugin {
  _FakeMetadataPlugin(this.playlist);

  @override
  final MetadataPluginPlaylistEndpoint playlist;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The real notifier, with only its list-fetch stubbed. The removal behaviour
/// under test is `removeTracks` itself, so it must not be overridden.
class _StubbedSavedPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _page([_playlist('pl-1')]);

  /// The cover re-read schedules a 3s/6s/10s ladder of timers; it is not what
  /// these tests are about, and leaving it running outlives the database.
  @override
  void refreshCoverLater(String playlistId) {}
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  Future<bool> build() async => true;
}

Future<void> _seed(
  AppDatabase db, {
  required String playlistId,
  required List<String> trackIds,
}) {
  return attachTracksToPlaylist(
    db,
    playlistId: playlistId,
    trackIds: trackIds,
  );
}

Future<void> _seedDownload(AppDatabase db, String trackId) {
  return db.into(db.trackDownloadTable).insert(
        TrackDownloadTableCompanion.insert(
          trackId: trackId,
          filePath: '/storage/emulated/0/Music/$trackId.m4a',
          baseName: trackId,
          status: DownloadPersistedStatus.completed,
          updatedAtMs: 1,
          trackData: '{}',
        ),
      );
}

void main() {
  late AppDatabase db;
  setUp(() => db = newMemoryDatabase());
  tearDown(() => db.close());

  group('detachTracksFromPlaylist', () {
    test('removes only the named track from the named playlist', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a', 'b', 'c']);
      await _seed(db, playlistId: 'pl-2', trackIds: ['a', 'b']);

      await detachTracksFromPlaylist(
        db,
        playlistId: 'pl-1',
        trackIds: ['b'],
      );

      expect(
        (await playlistMembership(db, 'pl-1')).map((r) => r.trackId),
        ['a', 'c'],
      );
      expect(
        (await playlistMembership(db, 'pl-2')).map((r) => r.trackId),
        ['a', 'b'],
        reason: 'a track belongs to more than one playlist',
      );
    });

    test('keeps the file row of a track that is still downloaded', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a']);
      await _seedDownload(db, 'a');

      await detachTracksFromPlaylist(db, playlistId: 'pl-1', trackIds: ['a']);

      expect(
        await (db.select(db.trackDownloadTable)
              ..where((t) => t.trackId.equals('a')))
            .get(),
        hasLength(1),
        reason: 'removal from a playlist is not deletion of the download',
      );
    });

    test('is a no-op on an empty playlist id', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a']);

      await detachTracksFromPlaylist(db, playlistId: '', trackIds: ['a']);

      expect(await playlistMembership(db, 'pl-1'), hasLength(1));
    });

    test('is a no-op on an empty track list', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a', 'b']);

      await detachTracksFromPlaylist(db, playlistId: 'pl-1', trackIds: []);

      expect(await playlistMembership(db, 'pl-1'), hasLength(2));
    });

    test('leaves a gap instead of renumbering the rest of the list', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a', 'b', 'c']);

      await detachTracksFromPlaylist(db, playlistId: 'pl-1', trackIds: ['a']);

      final rows = await playlistMembership(db, 'pl-1');
      expect(rows.map((r) => r.position), [1, 2]);
      expect(rows.map((r) => r.trackId), ['b', 'c']);
    });
  });

  group('MetadataPluginSavedPlaylistsNotifier.removeTracks', () {
    ProviderContainer containerFor({
      required _FakePlaylistEndpoint playlist,
    }) {
      return ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          metadataPluginProvider.overrideWith(
            (ref) async => _FakeMetadataPlugin(playlist),
          ),
          metadataPluginUserProvider.overrideWith((ref) async => _user('me')),
          metadataPluginAuthenticatedProvider.overrideWith(
            () => _AlwaysAuthenticated(),
          ),
          metadataPluginSavedPlaylistsProvider.overrideWith(
            () => _StubbedSavedPlaylists(),
          ),
        ],
      );
    }

    test('deletes the mirror row once Spotify confirms', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a', 'b']);
      final playlist = _FakePlaylistEndpoint();
      final container = containerFor(playlist: playlist);
      addTearDown(container.dispose);
      final notifier = container.read(
        metadataPluginSavedPlaylistsProvider.notifier,
      );
      await container.read(metadataPluginSavedPlaylistsProvider.future);

      await notifier.removeTracks('pl-1', ['a']);

      expect(playlist.removeCalls, hasLength(1));
      expect(playlist.removeCalls.single.playlistId, 'pl-1');
      expect(playlist.removeCalls.single.trackIds, ['a']);
      expect(
        (await playlistMembership(db, 'pl-1')).map((r) => r.trackId),
        ['b'],
      );
    });

    test('leaves the mirror untouched when the plugin call fails', () async {
      await _seed(db, playlistId: 'pl-1', trackIds: ['a', 'b']);
      final playlist = _FakePlaylistEndpoint(
        removeError: StateError('removeTracks asserted on an unknown name'),
      );
      final container = containerFor(playlist: playlist);
      addTearDown(container.dispose);
      final notifier = container.read(
        metadataPluginSavedPlaylistsProvider.notifier,
      );
      await container.read(metadataPluginSavedPlaylistsProvider.future);

      await expectLater(
        notifier.removeTracks('pl-1', ['a']),
        throwsA(isA<StateError>()),
        reason: 'the failure has to reach the caller instead of vanishing',
      );
      expect(
        (await playlistMembership(db, 'pl-1')).map((r) => r.trackId),
        ['a', 'b'],
      );
    });
  });
}
