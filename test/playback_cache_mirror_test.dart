import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/playback_cache_mirror.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cache_mirror_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File file(String name) => File('${tmp.path}/$name');

  group('completeCoverLength', () {
    test('full 200 with content-length is mirrorable', () {
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 200,
          contentRangeHeader: null,
          contentLengthHeader: '100',
        ),
        100,
      );
    });

    test('range starting at zero through end is mirrorable', () {
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 206,
          contentRangeHeader: 'bytes 0-99/100',
          contentLengthHeader: '100',
        ),
        100,
      );
    });

    test('non-zero range is NOT mirrorable', () {
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 206,
          contentRangeHeader: 'bytes 40-99/100',
          contentLengthHeader: '60',
        ),
        isNull,
      );
    });

    test('truncated open-ended range is NOT mirrorable', () {
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 206,
          contentRangeHeader: 'bytes 0-49/100',
          contentLengthHeader: '50',
        ),
        isNull,
      );
    });

    test('malformed or missing headers are NOT mirrorable', () {
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 206,
          contentRangeHeader: 'garbage',
          contentLengthHeader: null,
        ),
        isNull,
      );
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 200,
          contentRangeHeader: null,
          contentLengthHeader: null,
        ),
        isNull,
      );
      expect(
        PlaybackCacheMirror.completeCoverLength(
          statusCode: 500,
          contentRangeHeader: 'bytes 0-99/100',
          contentLengthHeader: '100',
        ),
        isNull,
      );
    });
  });

  group('attach', () {
    test('complete sequential write creates the valid cache', () async {
      final cache = file('track.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 6,
      )!;

      final out = await mirror.attach(Stream<Uint8List>.fromIterable([
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ]));
      final received = await out.expand((c) => c).toList();

      expect(received, [1, 2, 3, 4, 5, 6]);
      expect(await cache.exists(), isTrue);
      expect(await cache.length(), 6);
      expect(await File('${cache.path}.part').exists(), isFalse);
    });

    test('truncated response deletes the part and leaves no cache', () async {
      final cache = file('track2.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 6,
      )!;

      final out = await mirror.attach(Stream<Uint8List>.fromIterable([
        Uint8List.fromList([1, 2]),
      ]));
      await out.drain();

      expect(await cache.exists(), isFalse);
      expect(await File('${cache.path}.part').exists(), isFalse);
    });

    test('upstream failure deletes part and forwards the error', () async {
      final cache = file('track3.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 100,
      )!;

      final controller = StreamController<Uint8List>();
      final out = await mirror.attach(controller.stream);
      final done = expectLater(
        out,
        emitsInOrder([
          Uint8List.fromList([1]),
          emitsError(isA<Exception>()),
        ]),
      );
      controller.add(Uint8List.fromList([1]));
      controller.addError(Exception('network died'));
      await controller.close();
      await done;

      expect(await cache.exists(), isFalse);
      expect(await File('${cache.path}.part').exists(), isFalse);
    });

    test('stale garbage in an existing .part cannot poison the cache',
        () async {
      final cache = file('track4.m4a');
      await File('${cache.path}.part').writeAsBytes([9, 9, 9]);

      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 2,
      )!;
      final out = await mirror.attach(Stream<Uint8List>.fromIterable([
        Uint8List.fromList([7, 8]),
      ]));
      await out.drain();

      expect(await cache.readAsBytes(), [7, 8]);
    });

    test('client cancellation abandons the mirror and removes the part',
        () async {
      final cache = file('track5.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 100,
      )!;

      final controller = StreamController<Uint8List>();
      final out = await mirror.attach(controller.stream);
      final sub = out.listen((_) {});
      await Future.delayed(Duration.zero);
      controller.add(Uint8List.fromList([1]));
      await sub.cancel();

      expect(await File('${cache.path}.part').exists(), isFalse);
      expect(
        PlaybackCacheMirror.isMirroring('${cache.path}.part'),
        isFalse,
        reason: 'slot must free so a later request can mirror again',
      );
    });

    test('a failed part-file setup releases the mirror slot', () async {
      // The parent is a regular file, so creating `<parent>/track.m4a.part`
      // fails before the sink exists. The reservation must not leak: otherwise
      // every later request for this track silently stops caching until the
      // process restarts.
      final blocker = file('not-a-directory');
      await blocker.writeAsBytes(const [0]);
      final cache = File('${blocker.path}/track.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 2,
      )!;

      await expectLater(
        mirror.attach(Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1, 2]),
        ])),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        PlaybackCacheMirror.isMirroring('${cache.path}.part'),
        isFalse,
        reason: 'attach failure must release the reservation',
      );
    });

    test('a failing onComplete still closes the response and keeps the cache',
        () async {
      final cache = file('track5b.m4a');
      final mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 2,
        onComplete: (_) async => throw StateError('metadata rewrite failed'),
      )!;

      final out = await mirror.attach(Stream<Uint8List>.fromIterable([
        Uint8List.fromList([4, 2]),
      ]));

      // Before the fix this future never completes: finish() threw before the
      // controller was closed, so the HTTP response never saw EOF.
      await out.drain().timeout(const Duration(seconds: 2));

      expect(await cache.readAsBytes(), [4, 2]);
      expect(await File('${cache.path}.part').exists(), isFalse);
      expect(
        PlaybackCacheMirror.isMirroring('${cache.path}.part'),
        isFalse,
        reason: 'finalization failure must release the reservation',
      );
    });
  });

  group('concurrency', () {
    test('a second mirror for the same track is refused until the first ends',
        () async {
      final cache = file('track7.m4a');
      final first = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 2,
      )!;
      expect(
        PlaybackCacheMirror.tryBegin(cacheFile: cache, expectedTotal: 2),
        isNull,
      );

      final out = await first.attach(Stream<Uint8List>.fromIterable([
        Uint8List.fromList([1, 2]),
      ]));
      await out.drain();

      expect(await cache.exists(), isTrue);
      // Slot released after completion:
      final second = PlaybackCacheMirror.tryBegin(
        cacheFile: cache,
        expectedTotal: 1,
      );
      expect(second, isNotNull);
    });
  });

  test('onComplete fires with the final length after rename', () async {
    final cache = file('track8.m4a');
    int? seen;
    final mirror = PlaybackCacheMirror.tryBegin(
      cacheFile: cache,
      expectedTotal: 3,
      onComplete: (len) async => seen = len,
    )!;
    final out = await mirror.attach(Stream<Uint8List>.fromIterable([
      Uint8List.fromList([1, 2, 3]),
    ]));
    await out.drain();

    expect(seen, 3);
  });
}
