// Tests for the local control channel and the device-aware memory budget.
//
// The control channel is what makes `spotube --play ...` drive the running
// instance instead of starting a second one, and the memory budget is what
// keeps the image caches inside what the platform will let the app keep.
//
// Hermetic: a Unix socket in a temp directory, no engine, no network.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/control/control_protocol.dart';
import 'package:spotube/services/control/control_server.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/memory/device_memory_profile.dart';
import 'package:spotube/services/memory/memory_budget.dart';

void main() {
  // The control server logs through the app's logger, which is not
  // initialized in a unit test. It can only be initialized once.
  setUpAll(() => AppLogger.initialize(false));

  group('ControlProtocol', () {
    test('a request round-trips through the wire format', () {
      const request = ControlRequest('playback.seek', {'seconds': 12.5});
      final line = ControlProtocol.encodeRequest(request);
      expect(line.endsWith('\n'), isTrue);
      expect(line.trim().contains('\n'), isFalse,
          reason: 'one frame must be one line');

      final decoded = ControlProtocol.decodeRequest(line.trim());
      expect(decoded, isNotNull);
      expect(decoded!.command, 'playback.seek');
      expect(decoded.arguments['seconds'], 12.5);
    });

    test('a response round-trips through the wire format', () {
      final line = ControlProtocol.encodeResponse(
        const ControlResponse.ok({'playing': true}),
      );
      final decoded = ControlProtocol.decodeResponse(line.trim());
      expect(decoded, isNotNull);
      expect(decoded!.ok, isTrue);
      expect((decoded.data as Map)['playing'], isTrue);
    });

    test('an error response keeps its message', () {
      final line = ControlProtocol.encodeResponse(
        const ControlResponse.error('no such command'),
      );
      final decoded = ControlProtocol.decodeResponse(line.trim());
      expect(decoded, isNotNull);
      expect(decoded!.ok, isFalse);
      expect(decoded.error, 'no such command');
    });

    test('malformed input decodes to null instead of throwing', () {
      expect(ControlProtocol.decodeRequest('not json'), isNull);
      expect(ControlProtocol.decodeRequest('[1,2,3]'), isNull);
      expect(ControlProtocol.decodeResponse('{{{'), isNull);
    });

    test('a request with no arguments decodes to an empty map', () {
      final decoded = ControlProtocol.decodeRequest(
        ControlProtocol.encodeRequest(const ControlRequest('state.get')).trim(),
      );
      expect(decoded!.arguments, isEmpty);
    });
  });

  group('ControlServer', () {
    late Directory tempDir;
    late String socketPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spotube_control_test');
      socketPath = '${tempDir.path}/control.sock';
      // The socket path is process-global, so the test points it at a
      // temp directory rather than the user's real one.
      ControlChannel.socketPathOverride = socketPath;
    });

    tearDown(() {
      ControlChannel.socketPathOverride = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('a client reaches a running server and gets the answer', () async {
      final server = ControlServer((request) async {
        if (request.command == 'echo') {
          return {'said': request.arguments['value']};
        }
        throw StateError('unknown command ${request.command}');
      });

      await server.start();
      addTearDown(server.stop);

      final response = await ControlClient.send(
        const ControlRequest('echo', {'value': 'hello'}),
        timeout: const Duration(seconds: 10),
      );

      expect(response, isNotNull);
      expect(response!.ok, isTrue);
      expect((response.data as Map)['said'], 'hello');
    });

    test('a failing command comes back as an error, not a crash', () async {
      final server = ControlServer((request) {
        throw StateError('boom');
      });

      await server.start();
      addTearDown(server.stop);

      final response = await ControlClient.send(
        const ControlRequest('anything'),
        timeout: const Duration(seconds: 10),
      );

      expect(response, isNotNull);
      expect(response!.ok, isFalse);
      expect(response.error, contains('boom'));
    });

    test('no server means no answer, not an exception', () async {
      ControlChannel.socketPathOverride = '${tempDir.path}/nonexistent.sock';

      final response = await ControlClient.send(
        const ControlRequest('state.get'),
        timeout: const Duration(seconds: 5),
      );
      expect(response, isNull);
    });
  });

  group('DeviceMemoryProfile', () {
    test('a per-app heap limit drives the budget', () {
      // A 256 MB-class device: a quarter of the heap, within the bounds.
      const profile = DeviceMemoryProfile(
        appHeapLimitBytes: 256 * 1024 * 1024,
        totalPhysicalBytes: 4 * 1024 * 1024 * 1024,
      );
      expect(profile.imageCacheBudgetBytes, 64 * 1024 * 1024);
    });

    test('a small heap limit shrinks the budget', () {
      // A 64 MB-class device: a quarter of the heap is 16 MB.
      const profile = DeviceMemoryProfile(appHeapLimitBytes: 64 * 1024 * 1024);
      expect(profile.imageCacheBudgetBytes, 16 * 1024 * 1024);
    });

    test('a tiny heap limit still gets the floor', () {
      const profile = DeviceMemoryProfile(appHeapLimitBytes: 16 * 1024 * 1024);
      expect(profile.imageCacheBudgetBytes, 8 * 1024 * 1024);
    });

    test('without a heap limit the device total is used', () {
      const profile =
          DeviceMemoryProfile(totalPhysicalBytes: 2 * 1024 * 1024 * 1024);
      // A fifteenth of 2 GB, floored at 8 MB.
      expect(
          profile.imageCacheBudgetBytes, greaterThanOrEqualTo(8 * 1024 * 1024));
      expect(
          profile.imageCacheBudgetBytes, lessThanOrEqualTo(64 * 1024 * 1024));
    });

    test('an unknown device gets the conservative fallback', () {
      const profile = DeviceMemoryProfile();
      expect(profile.imageCacheBudgetBytes, 32 * 1024 * 1024);
    });

    test('the derived budgets are fractions of the image budget', () {
      const profile = DeviceMemoryProfile(appHeapLimitBytes: 256 * 1024 * 1024);
      expect(profile.decodedArtworkBudgetBytes,
          lessThan(profile.imageCacheBudgetBytes));
      expect(profile.artworkMemoBudgetBytes,
          lessThan(profile.imageCacheBudgetBytes));
      // Two caches of the same size would double the artwork footprint.
      expect(profile.decodedArtworkBudgetBytes,
          lessThan(profile.imageCacheBudgetBytes ~/ 2));
    });

    test('no budget is ever zero or negative', () {
      for (final profile in [
        const DeviceMemoryProfile(),
        const DeviceMemoryProfile(appHeapLimitBytes: 1),
        const DeviceMemoryProfile(appHeapLimitBytes: -1),
        const DeviceMemoryProfile(totalPhysicalBytes: 1),
        const DeviceMemoryProfile(
            appHeapLimitBytes: 1 << 40, totalPhysicalBytes: 1 << 40),
      ]) {
        expect(profile.imageCacheBudgetBytes, greaterThan(0));
        expect(profile.decodedArtworkBudgetBytes, greaterThan(0));
        expect(profile.artworkMemoBudgetBytes, greaterThan(0));
      }
    });
  });

  group('DeviceMemoryProbe', () {
    test('the per-app heap limit is null when the platform has none', () async {
      final probe = DeviceMemoryProbe(invoke: (_) async => null);
      expect(await probe.appHeapLimitBytes(), isNull);
    });

    test('a platform that answers with a number is used', () async {
      final probe = DeviceMemoryProbe(
        invoke: (_) async => 192 * 1024 * 1024,
      );
      expect(await probe.appHeapLimitBytes(), 192 * 1024 * 1024);
    });

    test('a nonsense answer is treated as unknown', () async {
      final probe = DeviceMemoryProbe(invoke: (_) async => 'not a number');
      expect(await probe.appHeapLimitBytes(), isNull);
    });

    test('a throwing platform does not break the probe', () async {
      final probe = DeviceMemoryProbe(
        invoke: (_) async => throw StateError('no channel'),
      );
      expect(await probe.appHeapLimitBytes(), isNull);
    });
  });

  group('MemoryBudget', () {
    tearDown(MemoryBudget.reset);

    test('the default budget is the conservative one', () {
      MemoryBudget.reset();
      expect(MemoryBudget.imageCacheBytes, 32 * 1024 * 1024);
    });

    test('an installed profile drives every cache', () {
      MemoryBudget.install(
        const DeviceMemoryProfile(appHeapLimitBytes: 128 * 1024 * 1024),
      );
      expect(MemoryBudget.imageCacheBytes, 32 * 1024 * 1024);
      expect(MemoryBudget.decodedArtworkBytes,
          lessThan(MemoryBudget.imageCacheBytes));
      expect(MemoryBudget.artworkMemoBytes,
          lessThan(MemoryBudget.imageCacheBytes));
    });
  });
}
