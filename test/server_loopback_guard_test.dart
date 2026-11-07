// The playback HTTP routes (/stream/*, /playback/*) are only ever consumed by
// this device's own mpv over loopback. With Connect enabled the server binds
// anyIPv4, so without a guard any LAN host could drive playback and pull
// queued audio. /ws keeps its own pairing dialog and is not gated here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:spotube/provider/server/router.dart';

class _FakeConnectionInfo implements HttpConnectionInfo {
  _FakeConnectionInfo(this.remoteAddress);

  @override
  final InternetAddress remoteAddress;
  @override
  final int remotePort = 50000;
  @override
  final int localPort = 9999;
}

Response okHandler(Request request) => Response.ok('inner');

void main() {
  Request requestFrom({InternetAddress? remote}) {
    return Request(
      'GET',
      Uri.parse('http://127.0.0.1:9999/stream/abc'),
      context: remote == null
          ? const {}
          : {
              'shelf.io.connection_info': _FakeConnectionInfo(remote),
            },
    );
  }

  test('loopback remote reaches the inner handler', () async {
    final res = await loopbackOnly(okHandler)(
      requestFrom(remote: InternetAddress.loopbackIPv4),
    );
    expect(res.statusCode, 200);
  });

  test('non-loopback remote is forbidden', () async {
    final res = await loopbackOnly(okHandler)(
      requestFrom(remote: InternetAddress('192.168.1.50')),
    );
    expect(res.statusCode, 403);
  });

  test('a request without connection info is allowed (test harnesses)',
      () async {
    final res = await loopbackOnly(okHandler)(requestFrom());
    expect(res.statusCode, 200);
  });
}
