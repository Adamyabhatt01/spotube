import 'dart:math';

// ignore: depend_on_referenced_packages
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/state.dart';

SpotubeSimpleAlbumObject _album(String id) => SpotubeSimpleAlbumObject(
      id: id,
      name: 'Album $id',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    );

List<SpotubeSimpleArtistObject> _artists(String id) => [
      SpotubeSimpleArtistObject(
        id: id,
        name: 'Artist $id',
        externalUri: 'https://example.test/artist/$id',
      ),
    ];

SpotubeFullTrackObject _remote(String id) => SpotubeFullTrackObject(
      id: id,
      name: 'Track $id',
      externalUri: 'https://example.test/track/$id',
      artists: _artists(id),
      album: _album(id),
      durationMs: 180000,
      isrc: 'ISRC$id',
      explicit: false,
    );

SpotubeLocalTrackObject _local(String path) => SpotubeLocalTrackObject(
      id: 'file://$_abs(path)',
      name: path,
      externalUri: 'file://$_abs(path)',
      artists: _artists(path),
      album: _album(path),
      durationMs: 1000,
      path: path,
    );

String _abs(String path) => path.startsWith('/') ? path.substring(1) : path;

AudioPlayerState _state(List<SpotubeTrackObject> queue,
    {int currentIndex = 0}) {
  return AudioPlayerState(
    playing: true,
    loopMode: PlaylistMode.none,
    shuffled: false,
    collections: const [],
    currentIndex: currentIndex,
    tracks: queue,
  );
}

/// The pre-optimization implementation, kept as the oracle the indexed
/// version is cross-validated against.
bool _naive(
  List<SpotubeTrackObject> haystack,
  List<SpotubeTrackObject> tracks,
) {
  return haystack.isNotEmpty &&
      tracks.every(
          (track) => AudioPlayerState.listContainsTrack(haystack, track));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listContainsTracks semantics', () {
    test('empty haystack or empty needles', () {
      expect(AudioPlayerState.listContainsTracks([], [_remote('a')]), isFalse);
      expect(AudioPlayerState.listContainsTracks([_remote('a')], []), isFalse);
    });

    test('local entries match by path, not id', () {
      final queue = [_local('/music/a.mp3')];
      expect(
        AudioPlayerState.listContainsTracks(
          queue,
          [_local('/music/a.mp3')],
        ),
        isTrue,
      );
      expect(
        AudioPlayerState.listContainsTracks(
          queue,
          [
            SpotubeLocalTrackObject(
              id: 'file://music/a.mp3',
              name: 'same id, different file',
              externalUri: 'file://music/a.mp3',
              artists: const [],
              album: _album('x'),
              durationMs: 1000,
              path: '/music/other.mp3',
            ),
          ],
        ),
        isFalse,
      );
    });

    test('a local needle is satisfied by a remote haystack entry via id', () {
      final remote = _remote('dup');
      final asLocal = SpotubeLocalTrackObject(
        id: remote.id,
        name: remote.name,
        externalUri: remote.externalUri,
        artists: const [],
        album: remote.album,
        durationMs: 1000,
        path: '/somewhere/else.mp3',
      );
      expect(
        AudioPlayerState.listContainsTracks([remote], [asLocal]),
        isTrue,
        reason: 'pair rule: only both-local compares paths',
      );
    });

    test('indexed path agrees with the naive scan on random inputs', () {
      final random = Random(20260920);
      for (var caseIndex = 0; caseIndex < 200; caseIndex++) {
        final pool = [
          for (var i = 0; i < 40; i++) ...[
            _remote('r$i'),
            _local('/music/l$i.mp3'),
          ],
        ];
        final haystack =
            pool.where((_) => random.nextBool()).toList(growable: false);
        final needles =
            pool.where((_) => random.nextBool()).toList(growable: false);
        // Force the indexed branch: 80 haystack x 40 needles >> threshold.
        final padded = [
          ...haystack,
          for (var i = haystack.length; i < 80; i++) _remote('pad$i'),
        ];
        final forced = [
          ...needles,
          for (var i = needles.length; i < 40; i++) _remote('need$i'),
        ];
        expect(
          AudioPlayerState.listContainsTracks(padded, forced),
          _naive(padded, forced),
          reason: 'mismatch on case $caseIndex',
        );
      }
    });
  });

  group('AudioPlayerState.containsTracks', () {
    // Regression: the parameter used to be named `tracks`, shadowing the field,
    // so the call reduced to `needles.isNotEmpty`. Every caller of it treats the
    // result as "this collection is the queue that is playing", which made
    // folder/playlist Play, Shuffle play and Add to queue no-ops.
    test('false when the queue does not hold the collection', () {
      final state = _state([_local('/music/in-queue.mp3')]);
      expect(
        state.containsTracks([_local('/music/other-folder.mp3')]),
        isFalse,
        reason: 'a different folder must not look like the playing queue',
      );
    });

    test('true only when the queue holds every track', () {
      final folder = [
        _local('/music/a.mp3'),
        _local('/music/b.mp3'),
        _local('/music/c.mp3'),
      ];
      expect(_state(folder).containsTracks(folder), isTrue);
      expect(_state([...folder, _local('/music/d.mp3')]).containsTracks(folder),
          isTrue);
      expect(
        _state(folder.take(2).toList()).containsTracks(folder),
        isFalse,
        reason: 'one missing track means it is not the same queue',
      );
    });

    test('empty queue and empty collection are both false', () {
      expect(
          _state(const []).containsTracks([_local('/music/a.mp3')]), isFalse);
      expect(
          _state([_local('/music/a.mp3')]).containsTracks(const []), isFalse);
    });

    test('works for a remote queue, matching the local case', () {
      final playlist = [_remote('x'), _remote('y')];
      expect(_state(playlist).containsTracks(playlist), isTrue);
      expect(_state(playlist).containsTracks([_remote('x'), _remote('z')]),
          isFalse);
    });

    test('containsTrack stays a single-track membership check', () {
      final state = _state([_local('/music/a.mp3'), _remote('r')]);
      expect(state.containsTrack(_local('/music/a.mp3')), isTrue);
      expect(state.containsTrack(_remote('r')), isTrue);
      expect(state.containsTrack(_local('/music/missing.mp3')), isFalse);
    });

    test('activeTrack membership is unaffected by the queue contents', () {
      final state = _state([_local('/music/a.mp3'), _local('/music/b.mp3')],
          currentIndex: 1);
      final active = state.activeTrack;
      expect((active as SpotubeLocalTrackObject).path, '/music/b.mp3');
      expect(state.containsTracks([active]), isTrue);
    });
  });

  group('listContainsTracks scaling', () {
    for (final size in [100, 1000]) {
      test('membership at ${size}x$size', () {
        final queue = [for (var i = 0; i < size; i++) _local('/m/t$i.mp3')];
        final folder = [for (var i = 0; i < size; i++) _local('/m/t$i.mp3')];

        final indexed = Stopwatch()..start();
        for (var i = 0; i < 50; i++) {
          expect(AudioPlayerState.listContainsTracks(queue, folder), isTrue);
        }
        indexed.stop();

        final naive = Stopwatch()..start();
        for (var i = 0; i < 50; i++) {
          expect(_naive(queue, folder), isTrue);
        }
        naive.stop();

        // ignore: avoid_print
        print(
          '[membership ${size}x$size] indexed=${indexed.elapsedMicroseconds}us '
          'naive=${naive.elapsedMicroseconds}us '
          'speedup=${(naive.elapsedMicroseconds / indexed.elapsedMicroseconds).toStringAsFixed(1)}x',
        );
      });
    }

    test('single needle against a long queue stays fast', () {
      final queue = [for (var i = 0; i < 2000; i++) _local('/m/t$i.mp3')];
      final needle = [_local('/m/t1999.mp3')];
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        expect(AudioPlayerState.listContainsTracks(queue, needle), isTrue);
      }
      sw.stop();
      // ignore: avoid_print
      print('[membership 2000x1] ${sw.elapsedMicroseconds}us per 1000 checks');
    });
  });
}
