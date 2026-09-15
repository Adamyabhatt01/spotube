// PR B: position-tick throttle + sponsor/late-init contracts.
//
// Covered hermetically (pure units; backend streams cannot run headless):
//  - PositionTickGate: same+same suppresses, same+new emits,
//    new+same emits (initial-state guarantee), reset forgets.
//  - shouldRefreshSponsorSegments: fetch only on track change.
//  - PendingNotificationBuffer: latest-wins staging, exactly-once take.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player_streams.dart';
import 'package:spotube/utils/position_tick_gate.dart';

SpotubeFullTrackObject _testTrack(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: const [],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

void main() {
  group('PositionTickGate', () {
    test('first tick always emits', () {
      final gate = PositionTickGate();
      expect(
        gate.shouldEmit(
            trackId: 'a', position: const Duration(seconds: 47)),
        isTrue,
      );
    });

    test('same track + same second suppresses', () {
      final gate = PositionTickGate();
      expect(
        gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 10)),
        isTrue,
      );
      expect(
        gate.shouldEmit(
            trackId: 'a', position: const Duration(milliseconds: 10500)),
        isFalse,
      );
      expect(
        gate.shouldEmit(
            trackId: 'a', position: const Duration(milliseconds: 10999)),
        isFalse,
      );
    });

    test('same track + new second emits', () {
      final gate = PositionTickGate();
      gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 10));
      expect(
        gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 11)),
        isTrue,
      );
    });

    test('new track + same second emits (initial-state guarantee)', () {
      final gate = PositionTickGate();
      gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 47));
      // Track change landing on the identical second must still emit.
      expect(
        gate.shouldEmit(trackId: 'b', position: const Duration(seconds: 47)),
        isTrue,
      );
      // ...and the gate now tracks the new track.
      expect(
        gate.shouldEmit(trackId: 'b', position: const Duration(seconds: 47)),
        isFalse,
      );
      expect(
        gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 47)),
        isTrue,
      );
    });

    test('null track ids follow the second rule', () {
      final gate = PositionTickGate();
      expect(
        gate.shouldEmit(trackId: null, position: Duration.zero),
        isTrue,
      );
      expect(
        gate.shouldEmit(trackId: null, position: Duration.zero),
        isFalse,
      );
      expect(
        gate.shouldEmit(
            trackId: null, position: const Duration(seconds: 1)),
        isTrue,
      );
    });

    test('reset forgets history', () {
      final gate = PositionTickGate();
      gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 10));
      gate.reset();
      expect(
        gate.shouldEmit(trackId: 'a', position: const Duration(seconds: 10)),
        isTrue,
      );
    });

    test('five ticks in one second forward exactly one', () {
      final gate = PositionTickGate();
      var forwarded = 0;
      for (final ms in [0, 200, 400, 600, 800]) {
        if (gate.shouldEmit(
            trackId: 'a', position: Duration(milliseconds: ms))) {
          forwarded++;
        }
      }
      expect(forwarded, 1);
    });
  });

  group('shouldRefreshSponsorSegments', () {
    test('fetches initially and on track change only', () {
      expect(
        shouldRefreshSponsorSegments(activeTrackId: null, cachedTrackId: null),
        isFalse,
      );
      expect(
        shouldRefreshSponsorSegments(activeTrackId: 'a', cachedTrackId: null),
        isTrue,
      );
      expect(
        shouldRefreshSponsorSegments(activeTrackId: 'a', cachedTrackId: 'a'),
        isFalse,
      );
      expect(
        shouldRefreshSponsorSegments(activeTrackId: 'b', cachedTrackId: 'a'),
        isTrue,
      );
    });
  });

  group('PendingNotificationBuffer', () {
    test('empty take returns null', () {
      expect(PendingNotificationBuffer().take(), isNull);
      expect(PendingNotificationBuffer().hasPending, isFalse);
    });

    test('latest wins, take is exactly-once', () {
      final buffer = PendingNotificationBuffer();
      final first = _testTrack('first');
      final second = _testTrack('second');

      buffer.stage(first);
      expect(buffer.hasPending, isTrue);
      buffer.stage(second);

      expect(buffer.take()?.id, 'second');
      expect(buffer.hasPending, isFalse);
      expect(buffer.take(), isNull);
    });
  });
}
