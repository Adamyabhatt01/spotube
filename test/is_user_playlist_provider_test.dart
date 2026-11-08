// Fix 5: the `is user's own playlist?` question used to open a full watch on
// the saved-playlists library in three widgets (page header, action row, track
// list). It is now answered by one derived provider so those consumers share a
// single cached boolean. This locks that behavior: owned → true, followed →
// false, and unresolved inputs → false rather than a throw.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://example.test/user/$id',
    );

SpotubeSimplePlaylistObject _playlist(String id, SpotubeUserObject owner) =>
    SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://example.test/playlist/$id',
      owner: owner,
    );

/// A saved-playlists notifier backed by a fixed list, so the derived provider
/// is exercised without a live plugin or the auth gate its real `build` awaits.
class _FakeSavedPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  _FakeSavedPlaylists(this.items);
  final List<SpotubeSimplePlaylistObject> items;

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async {
    return SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );
  }

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>> fetch(
    int offset,
    int limit,
  ) =>
      build();
}

void main() {
  final me = _user('me');
  final other = _user('someone-else');
  final mine = _playlist('mine', me);
  final theirs = _playlist('theirs', other);

  ProviderContainer containerWith({
    required List<SpotubeSimplePlaylistObject> playlists,
    SpotubeUserObject? me,
  }) {
    final container = ProviderContainer(
      overrides: [
        metadataPluginSavedPlaylistsProvider
            .overrideWith(() => _FakeSavedPlaylists(playlists)),
        metadataPluginUserProvider.overrideWith((ref) async => me),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle(ProviderContainer container) async {
    await container.read(metadataPluginSavedPlaylistsProvider.future);
    await container.read(metadataPluginUserProvider.future);
  }

  test('true only for a playlist owned by the signed-in user', () async {
    final container = containerWith(playlists: [mine, theirs], me: me);
    await settle(container);

    expect(container.read(isUserPlaylistProvider('mine')), isTrue);
    expect(container.read(isUserPlaylistProvider('theirs')), isFalse,
        reason: 'same library, different owner is not the user\'s own');
    expect(container.read(isUserPlaylistProvider('absent')), isFalse);
  });

  test('false while the library or the account is unresolved', () async {
    // No await: the provider is still loading, so `asData` is null and the
    // answer must degrade to false rather than reading through a null list.
    final loading = containerWith(playlists: [mine], me: me);
    expect(loading.read(isUserPlaylistProvider('mine')), isFalse);

    final signedOut = containerWith(playlists: [mine], me: null);
    await settle(signedOut);
    expect(signedOut.read(isUserPlaylistProvider('mine')), isFalse,
        reason: 'no account → nothing is the user\'s own playlist');
  });
}
