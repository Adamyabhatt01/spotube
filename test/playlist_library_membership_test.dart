// Creating a playlist has to put it in the account's *library*, not only
// create it on Spotify.
//
// The plugin's create does both — it creates the playlist and then follows
// it into the library rootlist — but the second half is invisible to the
// host, and a failure there is silent. The symptom is the one this whole
// change set is about: the playlist exists on Spotify and in no device's
// library, so it never appears on another device signed into the same
// account.
//
// These tests pin the host half: after a create, the host asks the network
// what the library holds, repairs the library when the answer says the
// playlist is missing, and tells the user when even the repair failed.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/metadata.dart';

import 'support/common_fakes.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://open.spotify.com/user/$id',
    );

SpotubeFullPlaylistObject _fullPlaylist(String id, String name) =>
    SpotubeFullPlaylistObject(
      id: id,
      name: name,
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
      collaborative: false,
      public: false,
    );

SpotubeSimplePlaylistObject _simple(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
    );

/// The account's library, as the network sees it.
class _FakeLibrary {
  final List<SpotubeSimplePlaylistObject> playlists = [];

  void add(String id) => playlists.add(_simple(id));
}

/// A playlist endpoint whose `create` does *not* put the playlist into the
/// library — the silent failure this whole path guards against. `save` is the
/// repair: it does.
class _FakePlaylistEndpoint implements MetadataPluginPlaylistEndpoint {
  _FakePlaylistEndpoint(this.library, {this.saveFails = false});

  final _FakeLibrary library;
  final bool saveFails;

  final List<String> createCalls = [];
  final List<String> saveCalls = [];

  @override
  Future<SpotubeFullPlaylistObject?> create(
    String userId, {
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    createCalls.add(name);
    // The playlist exists on Spotify — but not in the library.
    return _fullPlaylist('pl-new', name);
  }

  @override
  Future<void> save(String playlistId) async {
    saveCalls.add(playlistId);
    if (saveFails) throw StateError('the rootlist write was refused');
    library.add(playlistId);
  }

  @override
  Future<SpotubeFullPlaylistObject> getPlaylist(String id) async =>
      _fullPlaylist(id, 'Playlist $id');

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

/// The saved-playlists list, reading the fake library.
class _StubbedSavedPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  _StubbedSavedPlaylists(this.library);

  final _FakeLibrary library;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
    int offset,
    int limit,
  ) async {
    final all = library.playlists;
    final page = all.skip(offset).take(limit).toList();
    final next = offset + page.length;

    return SpotubePaginationResponseObject(
      limit: limit,
      nextOffset: next < all.length ? next : null,
      total: all.length,
      hasMore: next < all.length,
      items: page,
    );
  }

  /// The cover re-read schedules a 3s/6s/10s ladder of timers; it is not what
  /// these tests are about, and leaving it running outlives the database.
  @override
  void refreshCoverLater(String playlistId) {}
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  late AppDatabase db;
  setUpAll(() => AppLogger.initialize(false));
  setUp(() => db = newMemoryDatabase());
  tearDown(() => db.close());

  ProviderContainer containerFor({
    required _FakeLibrary library,
    required _FakePlaylistEndpoint endpoint,
  }) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metadataPluginProvider.overrideWith(
          (ref) async => _FakeMetadataPlugin(endpoint),
        ),
        metadataPluginUserProvider.overrideWith((ref) async => _user('me')),
        metadataPluginAuthenticatedProvider.overrideWith(
          () => _AlwaysAuthenticated(),
        ),
        metadataPluginSavedPlaylistsProvider.overrideWith(
          () => _StubbedSavedPlaylists(library),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('a created playlist is put in the account library', () {
    test('a playlist that is missing from the library is added to it',
        () async {
      final library = _FakeLibrary();
      final endpoint = _FakePlaylistEndpoint(library);
      final container = containerFor(library: library, endpoint: endpoint);

      final notifier =
          container.read(metadataPluginPlaylistProvider('pl-new').notifier);
      await container.read(metadataPluginPlaylistProvider('pl-new').future);

      final warnings = <String>[];
      await notifier.create(name: 'Road trip', onWarning: warnings.add);
      await notifier.libraryCheck;

      expect(endpoint.createCalls, ['Road trip']);
      expect(
        endpoint.saveCalls,
        ['pl-new'],
        reason: 'the playlist was not in the library, so the host has to put '
            'it there — otherwise it stays invisible on every other device',
      );
      expect(
        library.playlists.map((p) => p.id),
        contains('pl-new'),
        reason: 'and the repair has to be visible in the library afterwards',
      );
      expect(warnings, isEmpty);
    });

    test('a playlist that is already in the library is left alone', () async {
      final library = _FakeLibrary()..add('pl-new');
      final endpoint = _FakePlaylistEndpoint(library);
      final container = containerFor(library: library, endpoint: endpoint);

      final notifier =
          container.read(metadataPluginPlaylistProvider('pl-new').notifier);
      await container.read(metadataPluginPlaylistProvider('pl-new').future);

      final warnings = <String>[];
      await notifier.create(name: 'Road trip', onWarning: warnings.add);
      await notifier.libraryCheck;

      expect(
        endpoint.saveCalls,
        isEmpty,
        reason: 'the plugin already followed the playlist into the library',
      );
      expect(warnings, isEmpty);
    });

    test('a library that refuses the repair is reported to the user',
        () async {
      final library = _FakeLibrary();
      final endpoint = _FakePlaylistEndpoint(library, saveFails: true);
      final container = containerFor(library: library, endpoint: endpoint);

      final notifier =
          container.read(metadataPluginPlaylistProvider('pl-new').notifier);
      await container.read(metadataPluginPlaylistProvider('pl-new').future);

      final warnings = <String>[];
      await notifier.create(name: 'Road trip', onWarning: warnings.add);
      await notifier.libraryCheck;

      expect(endpoint.saveCalls, ['pl-new']);
      expect(
        warnings,
        hasLength(1),
        reason: 'a playlist that cannot reach the library would be invisible '
            'on the other devices — the user has to be told, not left to '
            'discover it',
      );
      expect(warnings.single, 'Road trip');
    });

    test('the create itself still succeeds when the library check fails',
        () async {
      final library = _FakeLibrary();
      final endpoint = _FakePlaylistEndpoint(library, saveFails: true);
      final container = containerFor(library: library, endpoint: endpoint);

      final notifier =
          container.read(metadataPluginPlaylistProvider('pl-new').notifier);
      await container.read(metadataPluginPlaylistProvider('pl-new').future);

      final playlist = await notifier.create(name: 'Road trip');

      expect(playlist, isNotNull);
      expect(playlist!.id, 'pl-new');
    });
  });
}
