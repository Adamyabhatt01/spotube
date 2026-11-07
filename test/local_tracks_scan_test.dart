// PR A: local-tracks scan contracts.
//
// Covered hermetically (no bridge, no filesystem scan — MetadataGod and
// path_provider cannot run headless):
//  - collectInWaves: bounded concurrency, order preservation, empty
//    input, wave accounting, abort-on-throw.
//  - localTrackFromFile with null metadata (the degraded path every
//    bridge failure takes): filename-derived identity, Unknown placeholders.

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/utils/async_waves.dart';

void main() {
  group('collectInWaves', () {
    test('bounds concurrency and preserves order', () {
      fakeAsync((async) {
        var inFlight = 0;
        var maxObserved = 0;
        var wavesDone = 0;
        List<int>? result;

        collectInWaves(
          List.generate(
            10,
            (i) => () async {
              inFlight++;
              if (inFlight > maxObserved) maxObserved = inFlight;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              inFlight--;
              return i;
            },
          ),
          waveSize: 3,
          onWaveDone: (_) => wavesDone++,
        ).then((value) => result = value);
        async.elapse(const Duration(seconds: 5));

        expect(result, List.generate(10, (i) => i));
        expect(maxObserved, lessThanOrEqualTo(3));
        expect(maxObserved, greaterThan(1));
        // 10 tasks in waves of 3 -> 4 waves.
        expect(wavesDone, 4);
      });
    });

    test('empty input resolves immediately', () {
      fakeAsync((async) {
        List<int>? result;
        collectInWaves<int>([]).then((value) => result = value);
        async.elapse(const Duration(seconds: 1));
        expect(result, isEmpty);
      });
    });

    test('throw aborts without partial results', () {
      fakeAsync((async) {
        Object? caught;
        collectInWaves([
          () async => 1,
          () async => throw StateError('bad file'),
          () async => 3,
        ], waveSize: 2).then<void>(
          (_) {},
          onError: (Object e) {
            caught = e;
          },
        );
        async.elapse(const Duration(seconds: 1));
        expect(caught, isStateError);
      });
    });

    test('default wave size batches large inputs', () {
      fakeAsync((async) {
        var maxObserved = 0;
        var inFlight = 0;
        var wavesDone = 0;
        List<int>? result;

        collectInWaves(
          List.generate(
            100,
            (i) => () async {
              inFlight++;
              if (inFlight > maxObserved) maxObserved = inFlight;
              await Future<void>.delayed(const Duration(milliseconds: 5));
              inFlight--;
              return i;
            },
          ),
          onWaveDone: (_) => wavesDone++,
        ).then((value) => result = value);
        async.elapse(const Duration(minutes: 1));

        expect(result, hasLength(100));
        expect(maxObserved, lessThanOrEqualTo(32));
        // 100 tasks in waves of 32 -> 4 waves (32+32+32+4).
        expect(wavesDone, 4);
      });
    });
  });

  group('localTrackFromFile degraded mapping', () {
    test('null metadata derives identity from filename', () {
      final track = SpotubeTrackObject.localTrackFromFile(
        File('/music/Artist Name - Song Title.mp3'),
      );

      expect(track, isA<SpotubeLocalTrackObject>());
      final local = track as SpotubeLocalTrackObject;
      expect(local.id, '/music/Artist Name - Song Title.mp3');
      expect(local.name, 'Artist Name - Song Title');
      expect(local.path, '/music/Artist Name - Song Title.mp3');
      expect(local.artists.single.name, 'Unknown Artist');
      expect(local.album.name, 'Unknown Album');
    });
  });
}
