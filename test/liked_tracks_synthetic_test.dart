import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://example.test/user/$id',
    );

SpotubeSimplePlaylistObject? _resolve({
  SpotubeUserObject? me,
  required bool? authenticated,
}) =>
    resolveLikedTracksPlaylist(
      name: 'Liked Tracks',
      description: 'Liked',
      me: me,
      authenticated: authenticated,
    );

void main() {
  group('buildLikedTracksPlaylist', () {
    test('carries the shared id, name and cover', () {
      final playlist = buildLikedTracksPlaylist(
        name: 'Liked Tracks',
        description: 'Liked',
        owner: _user('u1'),
      );

      expect(playlist.id, likedTracksPlaylistId);
      expect(playlist.id, 'user-liked-tracks');
      expect(playlist.name, 'Liked Tracks');
      expect(playlist.owner.id, 'u1');
      expect(playlist.images, isNotEmpty);
    });
  });

  group('resolveLikedTracksPlaylist', () {
    test('prefers the live profile when reachable', () {
      final playlist = _resolve(me: _user('live'), authenticated: true);

      expect(playlist, isNotNull);
      expect(playlist!.owner.id, 'live');
      expect(playlist.owner.name, 'User live');
    });

    test('falls back to an anonymous owner while signed in (offline)', () {
      final playlist = _resolve(me: null, authenticated: true);

      expect(playlist, isNotNull);
      expect(playlist!.id, likedTracksPlaylistId);
      // Empty owner renders as blank, never a crash: TrackPresentation
      // takes owner as a nullable String.
      expect(playlist.owner.name, isEmpty);
    });

    test('returns null while logged out', () {
      expect(_resolve(me: null, authenticated: false), isNull);
    });

    test('returns null while auth state is still loading', () {
      expect(_resolve(me: null, authenticated: null), isNull);
    });
  });
}
