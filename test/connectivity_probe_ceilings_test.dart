// PR 8 (N-01): the connectivity probe must be ceilinged and single-flight.
// Before this the probe's Dio had no timeouts and no dedupe, so one hung
// DNS/HTTP probe could hold the 30 s retry loop hostage and every
// connectivity event could stack another full probe on top.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/connectivity_adapter.dart';

class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.latency);

  final Duration latency;
  int heads = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    heads++;
    await Future<void>.delayed(latency);
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the default probe client has a 5s ceiling', () {
    final dio = ConnectionCheckerService.forTesting().dio;
    expect(dio.options.connectTimeout, const Duration(seconds: 5));
    expect(dio.options.sendTimeout, const Duration(seconds: 5));
    expect(dio.options.receiveTimeout, const Duration(seconds: 5));
  });

  test('concurrent isConnected calls share one in-flight probe', () async {
    final adapter = _CountingAdapter(const Duration(milliseconds: 80));
    final service = ConnectionCheckerService.forTesting(
        dio: Dio()..httpClientAdapter = adapter);
    // Force the dio.head fallback for every address; the first 200 short-
    // circuits the google||baidu||vpn chain, so a full probe is exactly
    // one head.
    service.lookup = (host) =>
        Future<List<InternetAddress>>.error(const SocketException('simulated'));

    final results = await Future.wait([
      service.isConnected,
      service.isConnected,
      service.isConnected,
      service.isConnected,
      service.isConnected,
    ]);

    expect(results, everyElement(isTrue));
    expect(adapter.heads, 1, reason: 'probes stacked instead of piggybacking');

    // The in-flight slot is released afterwards: a later call probes again.
    await service.isConnected;
    expect(adapter.heads, 2);
  });
}
