// Unit tests for the VPN source-pinning client factory.
//
// Hermetic: loopback servers only, no VPN, no nmcli. Proves the adapter
// delegates byte-identically with no pin, pins with a 127.0.0.1 pin
// (plain + TLS legs), fails closed on an unroutable pin, refuses proxied
// requests, and applies the same certificate rule as the global overrides.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/collections/http-override.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/vpn/pinned_client.dart';
import 'package:spotube/services/vpn/vpn_backend.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';

class _RecordingBackend implements VpnSystemBackend {
  int deviceQueries = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<Set<String>> activeUuids() async => const {};

  @override
  Future<List<VpnConnection>> listConnections() async => const [];

  @override
  Future<void> bringUp(String uuid) async {}

  @override
  Future<void> bringDown(String uuid) async {}

  @override
  Future<List<String>> vpnDeviceNames() async {
    deviceQueries++;
    return const ['tun0'];
  }
}

class _FakeIface implements NetworkInterface {
  _FakeIface(this.name, List<String> addresses)
      : addresses = addresses.map(InternetAddress.new).toList();

  @override
  final String name;

  @override
  int get index => 0;

  @override
  final List<InternetAddress> addresses;
}


Dio _dioWithPin(
  InternetAddress? Function() readPin, {
  bool Function(X509Certificate, String, int)? certificateRule,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => createPinnedClient(
      readPin,
      certificateRule: certificateRule,
    ),
  );
  return dio;
}

void main() {
  AppLogger.initialize(false);

  late HttpServer server;
  late HttpServer tlsServer;
  late Directory tempRoot;

  Future<void> serve(HttpRequest req) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-length', '2');
    req.response.add([0x4F, 0x4B]);
    await req.response.close();
  }

  setUpAll(() async {
    tempRoot = await Directory.systemTemp.createTemp('vpn_pin_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(serve);

    // Self-signed loopback TLS identity for the https leg.
    final key = File('${tempRoot.path}/key.pem');
    final cert = File('${tempRoot.path}/cert.pem');
    final keyResult = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', key.path, '-out', cert.path, '-days', '1',
      '-subj', '/CN=127.0.0.1',
      '-addext', 'subjectAltName=IP:127.0.0.1',
    ]);
    expect(keyResult.exitCode, 0, reason: 'openssl must mint test certs');

    final context = SecurityContext()
      ..useCertificateChain(cert.path)
      ..usePrivateKey(key.path);
    tlsServer = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    tlsServer.listen(serve);
  });

  tearDownAll(() async {
    await server.close(force: true);
    await tlsServer.close(force: true);
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  String url() => 'http://${server.address.host}:${server.port}/';
  String tlsUrl() =>
      'https://${tlsServer.address.host}:${tlsServer.port}/';

  test('cert rule matches the global overrides', () {    final dummyCert = X509CertificatePlaceholder._();
    expect(
      allowsBadCertificateForHost(dummyCert, 'open.spotify.com', 443),
      isTrue,
    );
    expect(
      allowsBadCertificateForHost(dummyCert, 'api.spotify.com', 443),
      isTrue,
    );
    expect(
      allowsBadCertificateForHost(dummyCert, 'example.com', 443),
      isFalse,
    );
    expect(
      // Suffix rule, like the production override: only names ending in
      // an allowlisted domain pass.
      allowsBadCertificateForHost(dummyCert, 'spotify.evil.com', 443),
      isFalse,
    );
  });

  test('no pin delegates like a default client', () async {
    final dio = _dioWithPin(() => null);
    final res = await dio.get<String>(url());
    expect(res.statusCode, 200);
    expect(res.data, 'OK');
    dio.close();
  });

  test('loopback pin succeeds on the pinned path', () async {
    final dio = _dioWithPin(() => InternetAddress('127.0.0.1'));
    final res = await dio.get<String>(url());
    expect(res.statusCode, 200);
    expect(res.data, 'OK');
    dio.close();
  });

  test('unroutable pin fails closed without transmitting', () async {
    final dio = _dioWithPin(() => InternetAddress('192.0.2.1'));
    await expectLater(
      dio.get<String>(url()),
      throwsA(isA<DioException>()),
    );
    dio.close();
  });

  test('pinned https leg completes against loopback TLS', () async {
    // The self-signed test cert is untrusted: accept it via the factory's
    // test-only rule override (the app rule would correctly reject it —
    // 127.0.0.1 is not allowlisted — which the cert test above pins).
    final dio = _dioWithPin(
      () => InternetAddress('127.0.0.1'),
      certificateRule: (cert, host, port) => true,
    );
    final res = await dio.get<String>(tlsUrl());
    expect(res.statusCode, 200);
    expect(res.data, 'OK');
    dio.close();
  });

  test('proxied request under a pin throws instead of bypassing', () async {
    final client = createPinnedClient(() => InternetAddress('127.0.0.1'));
    // A proxy is only reachable here via an explicit findProxy rule (the
    // app configures none); it must fail closed, never transmit unpinned.
    client.findProxy = (uri) => 'PROXY 127.0.0.1:1';
    // Closure form: the factory may throw synchronously out of getUrl.
    await expectLater(
      () => client.getUrl(Uri.parse(url())),
      throwsA(isA<VpnProxyConflictException>()),
    );
    client.close();
  });

  group('resolveVpnEndpoint device selection', () {
    test('exact device wins over other tunnel interfaces', () async {
      final backend = _RecordingBackend();
      final endpoint = await resolveVpnEndpoint(
        backend: backend,
        deviceName: 'nordlynx',
        listInterfaces: ({
          bool includeLoopback = false,
          bool includeLinkLocal = false,
          InternetAddressType type = InternetAddressType.any,
        }) async => <NetworkInterface>[
          _FakeIface('wlan0', ['192.168.1.5']),
          _FakeIface('tun0', ['10.8.0.2']),
          _FakeIface('nordlynx', ['10.9.0.2']),
        ]);
      expect(endpoint.ifname, 'nordlynx');
      expect(endpoint.address.address, '10.9.0.2');
      expect(backend.deviceQueries, 0,
          reason: 'explicit device must not consult the backend');
    });

    test('absent device fails closed without fallback', () async {
      final backend = _RecordingBackend();
      await expectLater(
        resolveVpnEndpoint(
          backend: backend,
          deviceName: 'tun9',
          listInterfaces: ({
            bool includeLoopback = false,
            bool includeLinkLocal = false,
            InternetAddressType type = InternetAddressType.any,
          }) async =>
              <NetworkInterface>[_FakeIface('tun0', ['10.8.0.2'])]),
        throwsA(
          isA<VpnNoRouteException>().having(
            (e) => e.message,
            'message',
            contains('tun9'),
          ),
        ),
      );
    });

    test('device without addresses fails closed', () async {
      final backend = _RecordingBackend();
      await expectLater(
        resolveVpnEndpoint(
          backend: backend,
          deviceName: 'tun0',
          listInterfaces: ({
            bool includeLoopback = false,
            bool includeLinkLocal = false,
            InternetAddressType type = InternetAddressType.any,
          }) async =>
              <NetworkInterface>[_FakeIface('tun0', [])]),
        throwsA(isA<VpnNoRouteException>()),
      );
    });

    test('uuid flow still prefers backend devices, then hints', () async {
      final backend = _RecordingBackend();
      final endpoint = await resolveVpnEndpoint(
        backend: backend,
        listInterfaces: ({
          bool includeLoopback = false,
          bool includeLinkLocal = false,
          InternetAddressType type = InternetAddressType.any,
        }) async => <NetworkInterface>[
          _FakeIface('wlan0', ['192.168.1.5']),
          _FakeIface('tun0', ['10.8.0.2']),
        ]);
      expect(endpoint.ifname, 'tun0');
      expect(backend.deviceQueries, 1);
    });
  });
}

/// X509Certificate has no public constructor; tests only need the host
/// routing behavior of the allowlist predicate, so a throwaway implementer
/// stands in for the cert argument (never inspected).
class X509CertificatePlaceholder implements X509Certificate {
  X509CertificatePlaceholder._();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
