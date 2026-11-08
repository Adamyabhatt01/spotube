// Regression tests for chunkDownload (lib/extensions/dio.dart).
//
// Covered against a real loopback HttpServer:
//  - a server honoring Range gets a chunked transfer reassembled
//    byte-exact.
//  - a server that *ignores* Range (206 -> 200 full-body) previously
//    produced an N-times-larger corrupted file; now the transfer falls
//    back to a single download and the bytes are exact.
//  - when HEAD fails, the length-discovery GET stream is closed and the
//    plain fallback download runs (no leaked socket, valid bytes).
//  - cancellation aborts the transfer and removes partial output.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' show basename;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:spotube/extensions/dio.dart';
import 'package:spotube/services/music_cache_policy.dart';

import 'support/common_fakes.dart';

Future<HttpServer> _startServer({
  required List<int> payload,
  bool ignoreRange = false,
  bool failHead = false,
  bool slowBody = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (req.method == 'HEAD') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('accept-ranges', 'bytes');
      if (!failHead) {
        req.response.headers.set('content-length', '${payload.length}');
      }
      await req.response.close();
      return;
    }

    final range = req.headers.value('range');
    if (range != null && !ignoreRange) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      final start = int.parse(m!.group(1)!);
      final end =
          m.group(2)!.isEmpty ? payload.length - 1 : int.parse(m.group(2)!);
      final slice = payload.sublist(start, end + 1);
      req.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-length', '${slice.length}')
        ..headers.set('content-range', 'bytes $start-$end/${payload.length}');
      if (slowBody) {
        // Delay the body so cancellation windows are observable.
        await req.response.addStream(
          Stream.fromFuture(
            Future<List<int>>.delayed(
              const Duration(milliseconds: 300),
              () => slice,
            ),
          ),
        );
      } else {
        await req.response.addStream(Stream.value(slice));
      }
      await req.response.close();
      return;
    }

    // Range ignored (or not requested): full body.
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-length', '${payload.length}')
      ..headers.set('accept-ranges', 'bytes');
    if (slowBody) {
      // Dribble the payload with gaps so a cancellation window exists.
      await req.response.addStream(
        Stream.fromFuture(
          Future<List<int>>.delayed(
            const Duration(milliseconds: 250),
            () => payload,
          ),
        ),
      );
    } else {
      await req.response.addStream(Stream.value(payload));
    }
    await req.response.close();
  });
  return server;
}

void main() {
  late Directory tempRoot;
  PathProviderPlatform? realPathProvider;

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('spotube-chunk-dl-test');
    realPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);
  });

  tearDownAll(() async {
    if (realPathProvider != null) {
      PathProviderPlatform.instance = realPathProvider!;
    }
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  List<int> payload() => List.generate(64 * 1024, (i) => (i * 31) % 251);

  /// Byte-for-byte comparison without pulling in another import: the point of
  /// these tests is whether the bytes are exactly one payload or a mix.
  bool bytesMatch(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  Future<({File file, Dio dio, HttpServer server})> setup(
    HttpServer server,
  ) async {
    final dio = Dio();
    final outDir = Directory('${tempRoot.path}/out')
      ..createSync(recursive: true);
    final file = File('${outDir.path}/track-${server.port}.bin');
    addTearDown(() async {
      dio.close();
      await server.close(force: true);
      if (await file.exists()) await file.delete();
    });
    return (file: file, dio: dio, server: server);
  }

  test('range-honoring server gets a chunked, byte-exact transfer', () async {
    final data = payload();
    final server = await _startServer(payload: data);
    final ctx = await setup(server);

    final response = await ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
    );

    expect(response.statusCode, 200);
    expect(await ctx.file.readAsBytes(), data);
  });

  test('server ignoring Range falls back instead of writing a corrupt file',
      () async {
    final data = payload();
    final server = await _startServer(payload: data, ignoreRange: true);
    final ctx = await setup(server);

    final progress = <int>[];
    await ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
      onReceiveProgress: (count, total) => progress.add(count),
    );

    // Without the 206/range validation this file was up to
    // `connections` times too large.
    expect(await ctx.file.readAsBytes(), data);
  });

  test('HEAD failure falls back through the discovery GET safely', () async {
    final data = payload();
    final server = await _startServer(payload: data, failHead: true);
    final ctx = await setup(server);

    await ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
    );

    expect(await ctx.file.readAsBytes(), data);
  });

  test('cancel aborts the transfer and removes partial output', () async {
    final data = payload();
    final server = await _startServer(payload: data, slowBody: true);
    final ctx = await setup(server);

    final cancelToken = CancelToken();
    final future = ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
      cancelToken: cancelToken,
    );

    final elapsed = Stopwatch()..start();
    Timer(const Duration(milliseconds: 100), cancelToken.cancel);

    await expectLater(
      future,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await ctx.file.exists(), false);
  });

  test('a failed attempt keeps the previously completed file', () async {
    // A re-download that never reached the target must not destroy what is
    // already on disk: previously any throw deleted the file at savePath,
    // including a finished earlier download.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    });

    final dio = Dio();
    final outDir = Directory('${tempRoot.path}/out')
      ..createSync(recursive: true);
    final file = File('${outDir.path}/track-${server.port}.bin');
    addTearDown(() async {
      dio.close();
      await server.close(force: true);
      if (await file.exists()) await file.delete();
    });

    final previous = List<int>.generate(1024, (i) => i % 256);
    await file.writeAsBytes(previous);

    await expectLater(
      dio.chunkDownload(
        'http://127.0.0.1:${server.port}/file',
        file.path,
      ),
      throwsA(isA<DioException>()),
    );

    expect(await file.readAsBytes(), previous);
  });

  test('a multi-connection transfer writes slices byte-exact', () async {
    // The positional-write path (>= 2 MiB with Range support) assembles the
    // file directly at slice offsets — no part files, no concatenation.
    final data = List.generate(
      5 * 1024 * 1024,
      (i) => (i * 37 + (i >> 8)) % 251,
    );
    final server = await _startServer(payload: data);
    final ctx = await setup(server);

    final progress = <int>[];
    final response = await ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
      onReceiveProgress: (count, total) => progress.add(count),
    );

    expect(response.statusCode, 200);
    expect(await ctx.file.readAsBytes(), data);
    // Progress sums must never exceed the file: each byte counted once.
    expect(progress.reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(data.length));
    // The staging file is not left behind next to the target.
    expect(File('${ctx.file.path}.part').existsSync(), false);
  });

  test('a misreported length falls back instead of shipping a short file',
      () async {
    // HEAD promises more bytes than the body ever sends. The staged file
    // would be short; the length check must route to the single-stream
    // download rather than renaming a truncated file into place.
    final data = List.generate(3 * 1024 * 1024, (i) => (i * 17) % 251);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.method == 'HEAD') {
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.set('accept-ranges', 'bytes')
          ..headers.set('content-length', '${data.length + 4096}');
        await req.response.close();
        return;
      }
      final range = req.headers.value('range');
      if (range == null) {
        // Discovery/fallback GET with no Range header: honest full body.
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.set('content-length', '${data.length}')
          ..headers.set('accept-ranges', 'bytes');
        await req.response.addStream(Stream.value(data));
        await req.response.close();
        return;
      }
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
      final start = int.parse(m.group(1)!);
      final claimedEnd = int.parse(m.group(2)!);
      // Serve at most what the payload actually has.
      final end = claimedEnd < data.length ? claimedEnd : data.length - 1;
      final slice = data.sublist(start, end + 1);
      req.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set('content-length', '${slice.length}')
        ..headers.set('content-range', 'bytes $start-$end/${data.length}');
      await req.response.addStream(Stream.value(slice));
      await req.response.close();
    });
    final ctx = await setup(server);

    await ctx.dio.chunkDownload(
      'http://127.0.0.1:${server.port}/file',
      ctx.file.path,
    );

    expect(await ctx.file.readAsBytes(), data);
    expect(File('${ctx.file.path}.part').existsSync(), false);
  });

  test('startup sweep removes legacy chunk scratch, nothing else', () async {
    final spotubeTemp = Directory('${tempRoot.path}/Spotube')
      ..createSync(recursive: true);
    final stale = Directory('${spotubeTemp.path}/.chunk_dl_track.mp3')
      ..createSync();
    File('${stale.path}/part_0').writeAsBytesSync([1, 2, 3]);
    final keep = Directory('${spotubeTemp.path}/keepme')..createSync();
    addTearDown(() async {
      if (await spotubeTemp.exists()) {
        await spotubeTemp.delete(recursive: true);
      }
    });

    final report = await sweepStaleChunkStaging();

    expect(report.didWork, true);
    expect(stale.existsSync(), false);
    expect(keep.existsSync(), true);
  });

  group('staging file isolation', () {
    // Two transfers that resolve to the same `_savePath` — which the queue
    // layer does not prevent: the name is "<title> - <artists>.<ext>" with no
    // track id, `addToQueue` never runs the batch collision prefilter, and
    // three workers run concurrently. They used to share one
    // `<savePath>.part` and interleave writes at the same slice offsets, and
    // both integrity gates still passed because each transfer did receive
    // exactly its own byte count.

    /// Serves a distinct payload per path, holding every ranged GET until
    /// [onRelease] is invoked, and reports how many are in flight.
    Future<({HttpServer server, void Function() release})>
        startGatedMultiServer({
      required Map<String, List<int>> payloads,
      required void Function(int inFlight) onInFlight,
    }) async {
      final gate = Completer<void>();
      var inFlight = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path.substring(1);
        final data = payloads[path];
        if (data == null) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        if (req.method == 'HEAD') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set('accept-ranges', 'bytes')
            ..headers.set('content-length', '${data.length}');
          await req.response.close();
          return;
        }

        final range = req.headers.value('range');
        if (range == null) {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set('content-length', '${data.length}');
          await req.response.addStream(Stream.value(data));
          await req.response.close();
          return;
        }

        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final start = int.parse(m.group(1)!);
        final end =
            m.group(2)!.isEmpty ? data.length - 1 : int.parse(m.group(2)!);
        final slice = data.sublist(start, end + 1);

        inFlight++;
        onInFlight(inFlight);
        await gate.future;
        inFlight--;

        req.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-length', '${slice.length}')
          ..headers.set('content-range', 'bytes $start-$end/${data.length}');
        await req.response.addStream(Stream.value(slice));
        await req.response.close();
      });
      return (
        server: server,
        release: () {
          if (!gate.isCompleted) gate.complete();
        },
      );
    }

    test('concurrent transfers to one target stage independently', () async {
      // 6 MiB each so `_connectionsForSize` spends 3 connections per transfer
      // and the chunked positional-write path is what runs.
      final a = List.generate(6 * 1024 * 1024, (i) => (i * 31) % 251);
      final b = List.generate(6 * 1024 * 1024, (i) => (i * 97 + 13) % 241);
      expect(a.length, b.length);

      final reached = Completer<void>();
      final gated = await startGatedMultiServer(
        payloads: {'a': a, 'b': b},
        onInFlight: (n) {
          // Both transfers are mid-transfer: each has already created its
          // staging file and issued its first ranged GET.
          if (n >= 2 && !reached.isCompleted) reached.complete();
        },
      );
      final server = gated.server;

      final outDir = Directory('${tempRoot.path}/out')
        ..createSync(recursive: true);
      final target = File('${outDir.path}/shared-${server.port}.bin');
      addTearDown(() async {
        gated.release();
        if (await target.exists()) await target.delete();
        for (final e in outDir.listSync()) {
          if (e.path.endsWith('.part')) e.deleteSync();
        }
      });

      final dioA = Dio();
      final dioB = Dio();
      addTearDown(() {
        dioA.close();
        dioB.close();
      });

      final futureA =
          dioA.chunkDownload('http://127.0.0.1:${server.port}/a', target.path);
      final futureB =
          dioB.chunkDownload('http://127.0.0.1:${server.port}/b', target.path);

      await reached.future;
      // The proof, read off the filesystem: one staging file per transfer, not
      // one inode both are writing slices into.
      final parts = outDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.part'))
          .toList();
      expect(parts, hasLength(2));

      gated.release();
      final results = await Future.wait([futureA, futureB]);
      for (final r in results) {
        expect(r.statusCode, lessThan(400));
      }

      // Last rename wins, and it is a whole, valid file: byte-exact for one
      // payload, never an interleaving of the two.
      final written = await target.readAsBytes();
      expect(
        bytesMatch(written, a) || bytesMatch(written, b),
        true,
        reason: 'target must be one payload byte-for-byte, not a mix',
      );
      expect(
        outDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.part')),
        isEmpty,
        reason: 'no staging file may outlive its transfer',
      );
    });

    test('cancel during the single-stream fallback keeps an existing file',
        () async {
      // Small payload -> `_connectionsForSize` returns 1 -> the fallback,
      // which is where dio's `deleteOnError` used to unlink the target.
      //
      // The first chunk has to be flushed *before* the cancel: dio opens (and
      // so truncates) the destination only once the response headers arrive,
      // and delaying the whole response would cancel before the file was ever
      // touched — which would make this test pass against the old code too.
      final data = List<int>.generate(32 * 1024, (i) => i % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.method == 'HEAD') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set('content-length', '${data.length}');
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.set('content-length', '${data.length}');
        final body = StreamController<List<int>>();
        unawaited(req.response.addStream(body.stream).catchError((_) {}));
        body.add(data.sublist(0, 1024));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!body.isClosed) {
          body.add(data.sublist(1024));
          await body.close();
        }
        try {
          await req.response.close();
        } catch (_) {
          // Canceled client; nothing to clean up on this side.
        }
      });

      final dio = Dio();
      final outDir = Directory('${tempRoot.path}/out')
        ..createSync(recursive: true);
      final file = File('${outDir.path}/existing-${server.port}.bin');
      addTearDown(() async {
        dio.close();
        await server.close(force: true);
        if (await file.exists()) await file.delete();
        for (final e in outDir.listSync()) {
          if (e.path.endsWith('.part')) e.deleteSync();
        }
      });

      final previous = List<int>.generate(4096, (i) => (i * 7) % 199);
      await file.writeAsBytes(previous);

      final cancelToken = CancelToken();
      final future = dio.chunkDownload(
        'http://127.0.0.1:${server.port}/file',
        file.path,
        cancelToken: cancelToken,
      );
      Timer(const Duration(milliseconds: 120), cancelToken.cancel);

      await expectLater(
        future,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );

      expect(
        await file.readAsBytes(),
        previous,
        reason: 'a canceled re-download must not delete what was already there',
      );
    });

    test('the staging file is named so the startup sweep can reclaim it',
        () async {
      // A SIGKILL / OOM / power loss cannot run `chunkDownload`'s cleanup, so
      // the only thing standing between a crash mid-download and a permanently
      // full music folder is that the leftover is named like a `.part` and
      // lives where `sweepStaleMusicCacheMirrors` looks for those. Pins the
      // suffix: the pid + sequence prefix is what makes it unique, the `.part`
      // tail is what makes it collectable.
      final data = List.generate(6 * 1024 * 1024, (i) => (i * 31) % 251);
      final reached = Completer<void>();
      final gated = await startGatedMultiServer(
        payloads: {'a': data},
        onInFlight: (n) {
          if (n >= 1 && !reached.isCompleted) reached.complete();
        },
      );

      final outDir = Directory('${tempRoot.path}/out')
        ..createSync(recursive: true);
      final target = File('${outDir.path}/swept-${gated.server.port}.bin');
      final dio = Dio();
      addTearDown(() async {
        gated.release();
        dio.close();
        await gated.server.close(force: true);
        if (await target.exists()) await target.delete();
        for (final e in outDir.listSync()) {
          if (e.path.endsWith('.part')) e.deleteSync();
        }
      });

      final future = dio.chunkDownload(
          'http://127.0.0.1:${gated.server.port}/a', target.path);
      await reached.future;

      final parts = outDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.part'))
          .toList();
      expect(parts, hasLength(1));
      expect(basename(parts.single.path), startsWith('swept-'));

      // The very sweep that runs at startup, pointed at the download folder.
      // `olderThan: Duration.zero` stands in for the 10-minute window a
      // genuinely abandoned file would have aged past.
      final report = await sweepIncompleteMirrors(
        dir: outDir,
        olderThan: Duration.zero,
        now: DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(report.removedFiles, 1);

      gated.release();
      // Only that the staging file is collectable matters here. How the
      // in-flight transfer reacts to losing its staging file underneath it is
      // not a production state — the sweep is age-bounded and runs at startup,
      // before this process can have a download in flight.
      try {
        await future;
      } catch (_) {
        // Expected on some platforms: the connections hold open handles to the
        // unlinked inode, so the transfer's fate is a race with the kernel.
      }
    });

    test('a mid-body failure on the fallback keeps an existing file', () async {
      final data = List<int>.generate(32 * 1024, (i) => i % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.method == 'HEAD') {
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.set('content-length', '${data.length}');
          await req.response.close();
          return;
        }
        // Promise the full length, deliver half, then hang up: the client's
        // body stream fails mid-transfer with the target still in place.
        // dart:io's server-side length check fires on `close` too; swallowing
        // it here keeps it out of this test's zone — the client still sees the
        // truncated body, which is the failure under test.
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.set('content-length', '${data.length}');
        try {
          await req.response.addStream(
            Stream.value(data.sublist(0, data.length ~/ 2)),
          );
          await req.response.close();
        } catch (_) {
          // Server-side "Content size below specified contentLength".
        }
      });

      final dio = Dio();
      final outDir = Directory('${tempRoot.path}/out')
        ..createSync(recursive: true);
      final file = File('${outDir.path}/truncated-${server.port}.bin');
      addTearDown(() async {
        dio.close();
        await server.close(force: true);
        if (await file.exists()) await file.delete();
        for (final e in outDir.listSync()) {
          if (e.path.endsWith('.part')) e.deleteSync();
        }
      });

      final previous = List<int>.generate(4096, (i) => (i * 11) % 197);
      await file.writeAsBytes(previous);

      await expectLater(
        dio.chunkDownload('http://127.0.0.1:${server.port}/file', file.path),
        throwsA(isA<DioException>()),
      );

      expect(
        await file.readAsBytes(),
        previous,
        reason: 'a failed re-download must not delete what was already there',
      );
    });
  });
}
