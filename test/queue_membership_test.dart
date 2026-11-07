// The shared queue-membership set behind track rows: one O(queue) build per
// queue revision plus O(1) lookups, exactly matching the
// AudioPlayerState.containsTrack/listContainsTrack predicate it replaces.
//
// Two suites: pure equivalence of isTrackInQueue against the containsTrack
// oracle across a remote/local matrix (including the id-fallback branches),
// and rebuild isolation through a real container — an unrelated queue
// mutation must not notify a row whose membership did not flip.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/queue_membership.dart';
import 'package:spotube/provider/audio_player/state.dart';

class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  _FakeAudioPlayerNotifier(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

AudioPlayerState _playerState({required List<SpotubeTrackObject> tracks}) {
  return AudioPlayerState(
    playing: false,
    loopMode: PlaylistMode.none,
    shuffled: false,
    collections: const [],
    tracks: tracks,
  );
}

SpotubeFullTrackObject _full(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: const [],
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'ISRC$id',
    explicit: false,
  );
}

SpotubeLocalTrackObject _local(String id, String path) {
  return SpotubeLocalTrackObject(
    id: id,
    name: 'Local $id',
    externalUri: 'file://$path',
    album: SpotubeSimpleAlbumObject(
      id: 'album-1',
      name: 'Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    path: path,
  );
}

/// Builds the membership exactly the way the provider does, so the
/// equivalence suite covers set construction plus predicate together.
QueueMembership _membershipOf(List<SpotubeTrackObject> tracks) {
  final ids = <String>{};
  final remoteIds = <String>{};
  final paths = <String>{};
  for (final track in tracks) {
    ids.add(track.id);
    if (track is SpotubeLocalTrackObject) {
      paths.add(track.path);
    } else {
      remoteIds.add(track.id);
    }
  }
  return (ids: ids, remoteIds: remoteIds, paths: paths);
}

void main() {
  group('isTrackInQueue matches containsTrack', () {
    final fullA = _full('a');
    final fullB = _full('b');
    final localX = _local('x', '/music/x.mp3');
    final localXSamePath = _local('other-id', '/music/x.mp3');
    final localY = _local('x', '/music/y.mp3');

    final cases = <String, (List<SpotubeTrackObject>, SpotubeTrackObject)>{
      'empty queue': (const [], fullA),
      'track present': ([fullA], fullA),
      'track absent': ([fullA], fullB),
      'local same path, different id': ([localX], localXSamePath),
      'local different path, same id': ([localX], localY),
      // The id fallback runs unless both sides are local.
      'full queue, local row, same id': ([fullA], _local('a', '/other.mp3')),
      'local queue, full row, same id': (
        [_local('a', '/music/a.mp3')],
        _full('a'),
      ),
      // Domain separation: a path never matches an id and vice versa.
      'local path equal to a remote id does not match': (
        [_full('/music/x.mp3')],
        localX,
      ),
      'remote id equal to a local path does not match': (
        [localX],
        _full('/music/x.mp3'),
      ),
      'mixed queue, remote row': ([localX, fullB], fullB),
      'mixed queue, local row by path': ([fullA, localX], localXSamePath),
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final (queue, row) = entry.value;
        final oracle = AudioPlayerState(
          playing: false,
          loopMode: PlaylistMode.none,
          shuffled: false,
          collections: const [],
          tracks: queue,
        ).containsTrack(row);
        expect(isTrackInQueue(_membershipOf(queue), row), oracle);
      });
    }
  });

  group('rebuild isolation through the provider', () {
    late ProviderContainer container;
    late _FakeAudioPlayerNotifier fakePlayer;

    setUp(() {
      fakePlayer = _FakeAudioPlayerNotifier(_playerState(tracks: const []));
      container = ProviderContainer(
        overrides: [audioPlayerProvider.overrideWith(() => fakePlayer)],
      );
    });

    tearDown(() => container.dispose());

    Future<void> drain() async {
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('unrelated queue mutations do not notify the row', () async {
      final row = _full('row');
      final other = _full('other');
      final third = _full('third');

      var notifications = 0;
      final sub = container.listen(
        trackMembershipOfProvider(row),
        (_, __) => notifications++,
      );
      addTearDown(sub.close);

      expect(container.read(trackMembershipOfProvider(row)), isFalse);
      final baseline = notifications;

      fakePlayer.emit(_playerState(tracks: [other]));
      await drain();
      fakePlayer.emit(_playerState(tracks: [other, third]));
      await drain();
      fakePlayer.emit(_playerState(tracks: [third]));
      await drain();

      expect(notifications, baseline,
          reason: 'rows whose membership never flips must stay silent');
      expect(container.read(trackMembershipOfProvider(row)), isFalse);
    });

    test('membership flips notify exactly once', () async {
      final row = _full('row');

      var notifications = 0;
      final sub = container.listen(
        trackMembershipOfProvider(row),
        (_, __) => notifications++,
      );
      addTearDown(sub.close);

      expect(container.read(trackMembershipOfProvider(row)), isFalse);
      final baseline = notifications;

      fakePlayer.emit(_playerState(tracks: [row]));
      await drain();

      expect(container.read(trackMembershipOfProvider(row)), isTrue);
      expect(notifications, greaterThan(baseline));

      final joined = notifications;
      fakePlayer.emit(_playerState(tracks: [row, _full('other')]));
      await drain();

      expect(notifications, joined,
          reason: 'staying a member across an unrelated add is silent');
    });
  });
}
