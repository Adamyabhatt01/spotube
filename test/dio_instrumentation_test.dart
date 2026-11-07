// Phase 6 (instrumentation) has no behaviour of its own, so the only thing that
// can be asserted is that it *observes*: a counter that silently never fires is
// as useless as no counter, and that was the state of this app before - which is
// why "sometimes slow" could only be inferred from things that throw.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/utils/perf_counters.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.fails = false});

  final bool fails;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // The options the interceptor stamped are the ones a real adapter attaches
    // to its error (`DioMixin.assureDioException` hands an already-typed
    // DioException back verbatim), so fabricating fresh ones here would test
    // the fixture rather than the interceptor.
    if (fails) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;

  setUp(() {
    PerfCounters.reset();
    dio = createAppDio();
  });

  test('a request is timed once, under its host', () async {
    dio.httpClientAdapter = _StubAdapter();

    await dio.get('https://instrumentation.test/a');

    expect(PerfCounters.countOf('dio.instrumentation.test'), 1);
    expect(
      PerfCounters.totalOf('dio.instrumentation.test'),
      greaterThan(Duration.zero),
    );
  });

  test('a failed request is timed too', () async {
    dio.httpClientAdapter = _StubAdapter(fails: true);

    await expectLater(
      dio.get('https://instrumentation.test/b'),
      throwsA(isA<DioException>()),
    );

    expect(PerfCounters.countOf('dio.instrumentation.test'), 1);
  });

  test('the key is the host, never the path', () async {
    dio.httpClientAdapter = _StubAdapter();

    await dio.get('https://instrumentation.test/signed/one-off-token');

    // Paths carry tokens and per-video ids; keying on them would grow the
    // counter map without bound.
    expect(
      PerfCounters.snapshot(),
      isNot(contains('signed/one-off-token')),
    );
  });
}
