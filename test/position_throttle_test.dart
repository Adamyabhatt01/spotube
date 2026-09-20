// PR B + PR 5: position-tick contracts.
//
// Covered hermetically (pure units; backend streams cannot run headless):
//  - PositionTicker: one raw chain in, at most one tick per second out,
//    seek invalidation, no burst for a late subscriber.
//  - the fan-out it removes, measured (prints a before/after line).
//  - the fan-out it saves, measured (prints a before/after line).
//  - isSameQueuePayload: the connect queue event is only worth sending when
//    the membership it carries actually changed.
//  - shouldRefreshSponsorSegments: fetch only on track change.
//  - PendingNotificationBuffer: latest-wins staging, exactly-once take.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player_streams.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/server/routes/connect.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/utils/position_tick.dart';

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

/// Five raw events per second, the libmpv cadence.
StreamController<Duration> _raw() => StreamController<Duration>.broadcast();

/// One timed fan-out run: how many dispatches and handler calls it took.
typedef _TickSample = ({int dispatches, int handlerCalls, int microseconds});

/// Lets the ticker's broadcast delivery reach every listener.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Closes [raw] and waits for every consumer's done event, which by stream
/// ordering means every earlier event was delivered too. (`asFuture` is not
/// used: a broadcast subscription's done does not complete it.)
Future<void> _drain(
  StreamController<Duration> raw,
  Iterable<Completer<void>> drained,
) async {
  await raw.close();
  await Future.wait([
    for (final completer in drained) completer.future,
  ]);
}

void main() {
  group('PositionTicker', () {
    test('emits once per second across a minute of raw ticks', () async {
      final source = _raw();
      final ticker = PositionTicker(source.stream);
      final ticks = <Duration>[];
      final subscription = ticker.stream.listen(ticks.add);

      // One hour of playback at exactly 5 events/sec, truncated to the first
      // 296 events (60 seconds).
      for (var i = 0; i < 296; i++) {
        source.add(Duration(milliseconds: i * 200));
      }
      await _flush();

      // One for second 0, then one per new second through second 59.
      expect(ticks.length, 60);
      expect(ticks.first, Duration.zero);
      expect(ticks.last, const Duration(seconds: 59));

      await subscription.cancel();
      await ticker.dispose();
      await source.close();
    });

    test('the first event of each new second passes, later ones do not',
        () async {
      final source = _raw();
      final ticker = PositionTicker(source.stream);
      final ticks = <Duration>[];
      final subscription = ticker.stream.listen(ticks.add);

      for (final ms in [0, 200, 400, 600, 800]) {
        source.add(Duration(milliseconds: ms));
      }
      source.add(const Duration(milliseconds: 999));
      source.add(const Duration(milliseconds: 1000));
      source.add(const Duration(milliseconds: 1100));
      await _flush();

      expect(ticks, [
        Duration.zero,
        const Duration(seconds: 1),
      ]);

      await subscription.cancel();
      await ticker.dispose();
      await source.close();
    });

    test('invalidate makes the next event pass within the same second',
        () async {
      final source = _raw();
      final ticker = PositionTicker(source.stream);
      final ticks = <Duration>[];
      final subscription = ticker.stream.listen(ticks.add);

      source.add(const Duration(milliseconds: 31500));
      await _flush();
      // Without invalidation, everything still inside second 31 is gated out —
      // which is exactly why the player service invalidates on seek.
      source.add(const Duration(milliseconds: 31800));
      await _flush();
      expect(ticks.length, 1);

      ticker.invalidate();
      source.add(const Duration(milliseconds: 31900));
      await _flush();

      expect(ticks, [
        const Duration(milliseconds: 31500),
        const Duration(milliseconds: 31900),
      ]);

      await subscription.cancel();
      await ticker.dispose();
      await source.close();
    });

    test('one upstream subscription serves every consumer', () async {
      var rawEventsSeen = 0;
      final source = _raw();
      final ticker = PositionTicker(
        source.stream.map((event) {
          rawEventsSeen++;
          return event;
        }),
      );
      final first = <Duration>[];
      final second = <Duration>[];
      final subscriptions = [
        ticker.stream.listen(first.add),
        ticker.stream.listen(second.add),
      ];

      source.add(const Duration(seconds: 5));
      source.add(const Duration(seconds: 5, milliseconds: 200));
      await _flush();

      // Both consumers shared the single gate: two raw events, one tick each.
      expect(rawEventsSeen, 2);
      expect(first, [const Duration(seconds: 5)]);
      expect(second, [const Duration(seconds: 5)]);

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await ticker.dispose();
      await source.close();
    });

    test('drops events while nobody listens instead of queuing them',
        () async {
      final source = _raw();
      final ticker = PositionTicker(source.stream);
      final first = <Duration>[];
      await ticker.stream.listen(first.add).cancel();

      // Seconds 1..4 go by with no subscriber (provider disposed, page closed).
      for (var second = 1; second <= 4; second++) {
        source.add(Duration(seconds: second));
      }
      await _flush();

      final late = <Duration>[];
      final subscription = ticker.stream.listen(late.add);
      source.add(const Duration(seconds: 5));
      await _flush();

      expect(first, isEmpty);
      expect(late, [const Duration(seconds: 5)]);

      await subscription.cancel();
      await ticker.dispose();
      await source.close();
    });
  });

  group('fan-out measurement', () {
    /// One hour of playback at the libmpv cadence (~5 events/sec), fanned out
    /// to the eight whole-second consumers that used to subscribe to the raw
    /// stream individually.
    const consumers = 8;
    const playbackSeconds = 3600;
    const rawEvents = playbackSeconds * 5;

    /// Before: every consumer subscribes to the raw stream and gates it alone.
    Future<_TickSample> runUngated(StreamController<Duration> raw) async {
      var dispatches = 0;
      var handlerCalls = 0;
      final lastSeconds = List.filled(consumers, -1);
      final drained = <Completer<void>>[];
      for (var i = 0; i < consumers; i++) {
        final done = Completer<void>();
        drained.add(done);
        raw.stream.listen(
          (position) {
            dispatches++;
            final second = position.inSeconds;
            if (second == lastSeconds[i]) return;
            lastSeconds[i] = second;
            handlerCalls++;
          },
          onDone: done.complete,
        );
      }

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < rawEvents; i++) {
        raw.add(Duration(milliseconds: i * 200));
      }
      await _drain(raw, drained);
      stopwatch.stop();

      return (
        dispatches: dispatches,
        handlerCalls: handlerCalls,
        microseconds: stopwatch.elapsedMicroseconds,
      );
    }

    /// After: one shared gate, every consumer on the resulting tick stream.
    Future<_TickSample> runTickered(StreamController<Duration> raw) async {
      final ticker = PositionTicker(raw.stream);
      var dispatches = 0;
      var handlerCalls = 0;
      final drained = <Completer<void>>[];
      for (var i = 0; i < consumers; i++) {
        final done = Completer<void>();
        drained.add(done);
        ticker.stream.listen(
          (_) {
            dispatches++;
            handlerCalls++;
          },
          onDone: done.complete,
        );
      }

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < rawEvents; i++) {
        raw.add(Duration(milliseconds: i * 200));
      }
      await _drain(raw, drained);
      stopwatch.stop();
      await ticker.dispose();

      return (
        dispatches: dispatches,
        handlerCalls: handlerCalls,
        microseconds: stopwatch.elapsedMicroseconds,
      );
    }

    test('one gated chain replaces eight', () async {
      // Async broadcast, like the real player stream: every delivery is
      // scheduled, so the numbers below are the dispatch cost the consumers
      // collectively pay — which is what the shared gate reduces.
      Future<_TickSample> measure(
          Future<_TickSample> Function(StreamController<Duration>) run) async {
        return run(StreamController<Duration>.broadcast());
      }

      // Warm up so the timed runs are not the first to compile these closures.
      await measure(runUngated);
      await measure(runTickered);
      final before = await measure(runUngated);
      final ticksSeenSoFar = PerfCounters.countOf('position.tick');
      final after = await measure(runTickered);

      // ignore: avoid_print
      print(
        '[position-fanout] $rawEvents raw events x $consumers consumers over '
        '$playbackSeconds s | before: dispatches=${before.dispatches} '
        'handled=${before.handlerCalls} ${before.microseconds}us | '
        'after: dispatches=${after.dispatches} handled=${after.handlerCalls} '
        '${after.microseconds}us',
      );

      // The work that renders something is unchanged: every consumer still
      // gets every second. What disappeared is the gated re-dispatch of the
      // four raw events in between.
      expect(before.dispatches, rawEvents * consumers);
      expect(before.handlerCalls, playbackSeconds * consumers);
      expect(after.dispatches, playbackSeconds * consumers);
      expect(after.handlerCalls, playbackSeconds * consumers);
      expect(
        PerfCounters.countOf('position.tick') - ticksSeenSoFar,
        playbackSeconds,
      );
    });
  });

  group('isSameQueuePayload', () {
    AudioPlayerState queueState({
      required List<SpotubeTrackObject> tracks,
      int currentIndex = 0,
      List<String> collections = const [],
      bool playing = false,
      bool shuffled = false,
      PlaylistMode loopMode = PlaylistMode.none,
    }) {
      return AudioPlayerState(
        tracks: tracks,
        currentIndex: currentIndex,
        collections: collections,
        playing: playing,
        shuffled: shuffled,
        loopMode: loopMode,
      );
    }

    test('the first payload is always sent', () {
      expect(
        isSameQueuePayload(null, queueState(tracks: [_testTrack('a')])),
        isFalse,
      );
    });

    test('play state, shuffle and loop changes are not queue changes',
        () async {
      final tracks = [_testTrack('a')];
      final sent = queueState(tracks: tracks);
      // Exactly what AudioPlayerNotifier does on playingStream/loopModeStream
      // /shuffleStream events: copyWith passes the existing list through, so
      // the payload the client would receive is the same one it already has.
      final next = sent.copyWith(
        playing: true,
        shuffled: true,
        loopMode: PlaylistMode.single,
      );

      // The lists are freezed's EqualUnmodifiableListView wrappers, which
      // compare by backing-list identity — not element by element.
      expect(identical(sent.tracks, next.tracks), isFalse);
      expect(sent.tracks == next.tracks, isTrue);
      expect(isSameQueuePayload(sent, next), isTrue);
    });

    test('a new index is sent — the active track changed', () {
      final tracks = [_testTrack('a'), _testTrack('b')];
      final sent = queueState(tracks: tracks);

      expect(isSameQueuePayload(sent, sent.copyWith(currentIndex: 1)), isFalse);
    });

    test('a replaced track list is sent even if the content is equal', () {
      final sent = queueState(tracks: [_testTrack('a')]);
      final next = queueState(tracks: [_testTrack('a')]);

      expect(isSameQueuePayload(sent, next), isFalse);
    });

    test('a replaced collection list is sent', () {
      final tracks = [_testTrack('a')];
      final sent = queueState(tracks: tracks, collections: const ['playlist-0']);

      expect(
        isSameQueuePayload(
          sent,
          sent.copyWith(collections: const ['playlist-1']),
        ),
        isFalse,
      );
      expect(
        isSameQueuePayload(
          sent,
          sent.copyWith(collections: sent.collections),
        ),
        isTrue,
      );
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

  group('shouldPrewarmNow', () {
    final failedAt = DateTime(2026, 9, 20, 12);

    test('a different candidate is always allowed', () {
      expect(
        shouldPrewarmNow(
          failedTrackId: 'a',
          retryAfter: failedAt.add(prewarmRetryCooldown),
          candidateId: 'b',
          now: failedAt,
        ),
        isTrue,
      );
    });

    test('failed candidate is blocked until the cooldown elapses', () {
      expect(
        shouldPrewarmNow(
          failedTrackId: 'a',
          retryAfter: failedAt.add(prewarmRetryCooldown),
          candidateId: 'a',
          now: failedAt.add(const Duration(seconds: 14)),
        ),
        isFalse,
      );
      expect(
        shouldPrewarmNow(
          failedTrackId: 'a',
          retryAfter: failedAt.add(prewarmRetryCooldown),
          candidateId: 'a',
          now: failedAt.add(prewarmRetryCooldown),
        ),
        isTrue,
      );
    });
  });
}
