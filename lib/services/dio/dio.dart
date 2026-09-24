import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:spotube/services/vpn/pinned_client.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';
import 'package:spotube/utils/perf_counters.dart';

final globalDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
  ),
)
  // Source-pins sockets to the held VPN lease when one exists; delegates
  // unpinned otherwise. Interceptors below are unaffected (adapter layer).
  ..httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => createPinnedClient(VpnPinHolder.current),
  )
  ..interceptors.add(_TimingInterceptor());

/// `dio.<host>=n (µs)` — the app's own HTTP traffic, which had no timing at all.
/// Keyed by host, not path: paths carry signed tokens and per-video ids, so they
/// would grow the counter map without bound.
class _TimingInterceptor extends Interceptor {
  static const _startedAt = 'spotube.perfStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _record(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions);
    handler.next(err);
  }

  void _record(RequestOptions options) {
    // Idempotent: a redirect or a retry re-enters here with the stopwatch
    // already spent, and a second `time()` would count one request twice.
    if (options.extra[_startedAt] case final Stopwatch sw when sw.isRunning) {
      sw.stop();
      PerfCounters.time('dio.${options.uri.host}', sw.elapsed);
    }
  }
}
