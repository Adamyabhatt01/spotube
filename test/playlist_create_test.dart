// Regression coverage for creating a Spotify playlist with its initial
// tracks. The old flow created the playlist, then asked the notifier keyed by
// "" to add tracks, so the tracks were sent to `spotify:playlist:` instead of
// the new playlist. These tests pin the created-ID handoff and the failure
// state that keeps the dialog open.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/metadata.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://open.spotify.com/user/$id',
    );

SpotubeFullPlaylistObject _playlist({
  required String id,
  required String name,
  List<SpotubeImageObject> images = const [],
}) =>
    SpotubeFullPlaylistObject(
      id: id,
      name: name,
      description: 'description',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: images,
      public: false,
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
  _FakePlaylistEndpoint({this.createError});

  final Object? createError;
  List<SpotubeImageObject> coverImages = const [];
  int getPlaylistCalls = 0;
  final List<
      ({
        String userId,
        String name,
        String? description,
        bool? public,
        bool? collaborative,
      })> createCalls = [];

  @override
  Future<SpotubeFullPlaylistObject?> create(
    String userId, {
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    createCalls.add((
      userId: userId,
      name: name,
      description: description,
      public: public,
      collaborative: collaborative,
    ));
    if (createError != null) throw createError!;
    return _playlist(id: 'new-id', name: name);
  }

  @override
  Future<SpotubeFullPlaylistObject> getPlaylist(String id) async {
    getPlaylistCalls++;
    return _playlist(id: id, name: 'Playlist $id', images: coverImages);
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

class _FakeSavedPlaylistsNotifier extends MetadataPluginSavedPlaylistsNotifier {
  final List<({String playlistId, List<String> trackIds})> addTrackCalls = [];

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _page(const []);

  @override
  Future<void> addTracks(String playlistId, List<String> trackIds) async {
    addTrackCalls.add((
      playlistId: playlistId,
      trackIds: List.of(trackIds),
    ));
  }
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  ProviderContainer containerFor({
    required _FakePlaylistEndpoint playlist,
    required _FakeSavedPlaylistsNotifier saved,
  }) {
    return ProviderContainer(
      overrides: [
        metadataPluginProvider.overrideWith(
          (ref) async => _FakeMetadataPlugin(playlist),
        ),
        metadataPluginUserProvider.overrideWith((ref) async => _user('me')),
        metadataPluginAuthenticatedProvider.overrideWith(
          () => _AlwaysAuthenticated(),
        ),
        metadataPluginSavedPlaylistsProvider.overrideWith(() => saved),
        playlistCoverRefreshDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
  }

  test('create adds tracks to the playlist returned by Spotify', () async {
    final playlist = _FakePlaylistEndpoint();
    final saved = _FakeSavedPlaylistsNotifier();
    final container = containerFor(playlist: playlist, saved: saved);
    addTearDown(container.dispose);
    final subscription = container.listen(
      metadataPluginPlaylistProvider(''),
      (_, __) {},
    );
    addTearDown(subscription.close);
    await container.read(metadataPluginSavedPlaylistsProvider.future);

    final created = await container
        .read(metadataPluginPlaylistProvider('').notifier)
        .create(
      name: 'New playlist',
      description: 'description',
      public: false,
      trackIds: ['track-1', 'track-2'],
    );

    expect(created?.id, 'new-id');
    expect(playlist.createCalls.single.userId, 'me');
    expect(playlist.createCalls.single.name, 'New playlist');
    expect(saved.addTrackCalls.single.playlistId, 'new-id');
    expect(saved.addTrackCalls.single.trackIds, ['track-1', 'track-2']);
    expect(saved.state.value!.items.single.id, 'new-id');
    expect(
      container.read(metadataPluginPlaylistProvider('')).requireValue.id,
      'new-id',
    );
  });

  test('create re-reads only the new playlist to pick up its cover', () async {
    final playlist = _FakePlaylistEndpoint()
      ..coverImages = [
        SpotubeImageObject(url: 'https://i.scdn.co/image/generated'),
      ];
    final saved = _FakeSavedPlaylistsNotifier();
    final container = containerFor(playlist: playlist, saved: saved);
    addTearDown(container.dispose);
    final subscription = container.listen(
      metadataPluginPlaylistProvider(''),
      (_, __) {},
    );
    addTearDown(subscription.close);
    await container.read(metadataPluginSavedPlaylistsProvider.future);
    await container.read(metadataPluginPlaylistProvider('').future);
    final getPlaylistCallsBefore = playlist.getPlaylistCalls;

    await container
        .read(metadataPluginPlaylistProvider('').notifier)
        .create(name: 'New playlist');
    // Let the zero-delay, best-effort cover refresh finish.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(playlist.getPlaylistCalls - getPlaylistCallsBefore, 1);
    expect(
      saved.state.value!.items.single.images.single.url,
      'https://i.scdn.co/image/generated',
    );
    expect(
      container
          .read(metadataPluginPlaylistProvider(''))
          .requireValue
          .images
          .single
          .url,
      'https://i.scdn.co/image/generated',
    );
  });

  test('create stores an error state and does not register a playlist',
      () async {
    final playlist = _FakePlaylistEndpoint(
      createError: StateError('Spotify rejected the create'),
    );
    final saved = _FakeSavedPlaylistsNotifier();
    final container = containerFor(playlist: playlist, saved: saved);
    addTearDown(container.dispose);
    final subscription = container.listen(
      metadataPluginPlaylistProvider(''),
      (_, __) {},
    );
    addTearDown(subscription.close);
    await container.read(metadataPluginSavedPlaylistsProvider.future);

    Object? reported;
    await expectLater(
      container.read(metadataPluginPlaylistProvider('').notifier).create(
            name: 'New playlist',
            onError: (error) => reported = error,
          ),
      throwsA(isA<StateError>()),
    );

    expect(reported, isA<StateError>());
    expect(
      container.read(metadataPluginPlaylistProvider('')).hasError,
      isTrue,
    );
    expect(saved.addTrackCalls, isEmpty);
    expect(saved.state.value!.items, isEmpty);
  });
}
