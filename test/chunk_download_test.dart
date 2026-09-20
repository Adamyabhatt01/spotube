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

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spotube/extensions/dio.dart';

/// Serves the fake temp directory chunkDownload asks path_provider for.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

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
      final end = m.group(2)!.isEmpty
          ? payload.length - 1
          : int.parse(m.group(2)!);
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
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDownAll(() async {
    if (realPathProvider != null) {
      PathProviderPlatform.instance = realPathProvider!;
    }
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  List<int> payload() => List.generate(64 * 1024, (i) => (i * 31) % 251);

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

  test('range-honoring server gets a chunked, byte-exact transfer',
      () async {
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

  test('HEAD failure falls back through the discovery GET safely',
      () async {
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
}
