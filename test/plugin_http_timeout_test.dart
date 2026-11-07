// Plugin HTTP timeouts: the stdlib binding passes null timeouts to Dio
// (wait forever); the host's binding override defaults them.
//
// The pure half pins the exact merge rule (null → default, explicit kept,
// everything else preserved). The integration half boots a real Hetu VM
// with the override and a local server: a plugin that constructs a bare
// `HttpBaseOptions()` must time out instead of hanging, while an explicit
// `receiveTimeout` is still honored.
//
// Local-only (test/ is gitignored): it boots Hetu from the pub-cache
// bytecode and binds a loopback server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/values.dart';
import 'package:hetu_std/hetu_std.dart';
import 'package:hetu_std/http/http.dart';
import 'package:spotube/services/metadata/http_timeout_binding.dart';

/// Locates the pinned `hetu_std` checkout through `.dart_tool/package_config.json`,
/// so the test runs on any machine (including CI) once `flutter pub get` has
/// run — no machine-specific absolute path.
String _stdPackagePath() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) {
    throw StateError(
      '.dart_tool/package_config.json not found; run `fvm flutter pub get`.',
    );
  }
  final packages =
      (jsonDecode(config.readAsStringSync())['packages'] as List).cast<Map>();
  final hetu = packages.firstWhere((p) => p['name'] == 'hetu_std');
  return Uri.parse(hetu['rootUri'] as String).toFilePath();
}

const _probeModule = '''
import "module:std" as std

var HttpClient = std.HttpClient
var HttpBaseOptions = std.HttpBaseOptions

class Probe {
  fun bareGet(baseUrl: string, path: string) -> Future {
    var client = HttpClient(HttpBaseOptions(baseUrl: baseUrl))
    return client.get_req(path)
  }

  fun timedGet(baseUrl: string, path: string, receive: int) -> Future {
    var client = HttpClient(HttpBaseOptions(baseUrl: baseUrl, receiveTimeout: receive))
    return client.get_req(path)
  }
}
''';

Future<Hetu> _bootHetu(PluginHttpTimeouts timeouts) async {
  final stdBytecode = File('${_stdPackagePath()}/lib/assets/bytecode/std.out');
  expect(
    stdBytecode.existsSync(),
    isTrue,
    reason: 'hetu_std std bytecode not found; run `fvm flutter pub get`',
  );

  final hetu = Hetu()..init();
  HetuStdLoader.loadBindings(hetu);
  bindPluginHttpTimeoutDefaults(hetu, timeouts: timeouts);
  hetu.loadBytecode(bytes: stdBytecode.readAsBytesSync(), moduleName: 'std');
  hetu.eval(_probeModule);
  hetu.eval('var probe = Probe()');
  return hetu;
}

Future<dynamic> _invoke(HTInstance probe, String method, List args) =>
    probe.invoke(method, positionalArgs: args);

void main() {
  group('applyPluginHttpTimeoutDefaults', () {
    test('null options get the production defaults', () {
      final filled = applyPluginHttpTimeoutDefaults(null);
      expect(filled.connectTimeout, 20);
      expect(filled.receiveTimeout, 30);
      expect(filled.sendTimeout, 30);
    });

    test('a bare HttpBaseOptions() gets the defaults', () {
      final filled = applyPluginHttpTimeoutDefaults(const HttpBaseOptions());
      expect(filled.connectTimeout, 20);
      expect(filled.receiveTimeout, 30);
      expect(filled.sendTimeout, 30);
    });

    test('an explicit timeout always wins', () {
      final filled = applyPluginHttpTimeoutDefaults(
        const HttpBaseOptions(receiveTimeout: 5),
      );
      expect(filled.connectTimeout, 20);
      expect(filled.receiveTimeout, 5);
      expect(filled.sendTimeout, 30);
    });

    test('everything else is preserved', () {
      final filled = applyPluginHttpTimeoutDefaults(
        HttpBaseOptions(
          baseUrl: 'https://example.test/api',
          followRedirects: false,
          headers: const {'User-Agent': 'probe'},
          queryParameters: const {'q': 'x'},
        ),
      );
      expect(filled.baseUrl, 'https://example.test/api');
      expect(filled.followRedirects, isFalse);
      expect(filled.headers, {'User-Agent': 'probe'});
      expect(filled.queryParameters, {'q': 'x'});
    });
  });

  group('the binding in a real VM', () {
    late HttpServer server;
    late int port;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) async {
        if (request.uri.path == '/slow') {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        request.response.write('ok');
        await request.response.close();
      });
    });

    tearDownAll(() async => server.close());

    test('a bare-options client times out on a slow server', () async {
      final hetu = await _bootHetu(const PluginHttpTimeouts(
        connectSeconds: 5,
        receiveSeconds: 1,
        sendSeconds: 5,
      ));
      final probe = hetu.fetch('probe') as HTInstance;
      final baseUrl = 'http://127.0.0.1:$port';

      await expectLater(
        _invoke(probe, 'bareGet', [baseUrl, '/slow']),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        )),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an explicit receiveTimeout is honored over the default',
        () async {
      final hetu = await _bootHetu(const PluginHttpTimeouts(
        connectSeconds: 5,
        receiveSeconds: 1,
        sendSeconds: 5,
      ));
      final probe = hetu.fetch('probe') as HTInstance;
      final baseUrl = 'http://127.0.0.1:$port';

      final response = await _invoke(probe, 'timedGet', [baseUrl, '/slow', 10]);
      final httpResponse = response as HttpResponse;
      expect(httpResponse.statusCode, 200);
      expect(httpResponse.data, 'ok');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
