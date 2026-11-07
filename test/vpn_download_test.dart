// Integration tests for the download VPN gate in DownloadManagerNotifier.
//
// Drives addToQueue/cancel against a real loopback HTTP server (same
// harness as download_cancel_test.dart) with a fake VPN backend injected
// through vpnManagerProvider — no `nmcli`, no real VPN.
//
// Covered:
//  - VPN disabled: download completes, backend untouched.
//  - VPN required + already active: shared (no up), never brought down.
//  - VPN required + inactive: one up, completes, one down on final release.
//  - Two concurrent downloads: one up shared, down only after both finish.
//  - Cancel during the VPN wait: task `canceled`, never `failed`.
//  - Unsupported backend while gated: task `failed` with an explicit error.
//  - VPN loss mid-download with a retryable failure: the retry waits for
//    recovery (pause-and-wait) instead of proceeding outside the VPN.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/services/vpn/unsupported_backend.dart';
import 'package:spotube/services/vpn/vpn_backend.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_manager_impl.dart';

import 'support/common_fakes.dart';

class FakeVpnBackend implements VpnSystemBackend {
  final Set<String> active = {};
  final List<String> broughtUp = [];
  final List<String> broughtDown = [];
  Completer<void>? blockBringUp;

  @override
  bool get isAvailable => true;

  @override
  Future<Set<String>> activeUuids() async => Set.of(active);

  @override
  Future<List<VpnConnection>> listConnections() async => const [
        VpnConnection(uuid: 'uuid-a', name: 'Test VPN', type: 'vpn'),
      ];

  @override
  Future<void> bringUp(String uuid) async {
    broughtUp.add(uuid);
    final block = blockBringUp;
    if (block != null) await block.future;
    active.add(uuid);
  }

  @override
  Future<void> bringDown(String uuid) async {
    broughtDown.add(uuid);
    active.remove(uuid);
  }

  @override
  Future<List<String>> vpnDeviceNames() async => devices;

  List<String> devices = const ['tun0'];
}

/// Loopback-backed tunnel device: pinning to 127.0.0.1 keeps the test
/// loopback server reachable, so gated downloads run genuinely pinned
/// end to end. A 192.0.2.x address instead proves fail-closed behavior.
class FakeNetworkInterface implements NetworkInterface {
  FakeNetworkInterface(this.name, List<String> addresses)
      : addresses = addresses.map((a) => InternetAddress(a)).toList();

  @override
  final String name;

  @override
  int get index => 0;

  @override
  final List<InternetAddress> addresses;
}

List<String> fakeTunnelAddresses = ['127.0.0.1'];

Future<List<NetworkInterface>> fakeListInterfaces({
  bool includeLoopback = false,
  bool includeLinkLocal = false,
  InternetAddressType type = InternetAddressType.any,
}) async =>
    [FakeNetworkInterface('tun0', fakeTunnelAddresses)];

class _FixedUrlSourcedTrackNotifier extends SourcedTrackNotifier {
  _FixedUrlSourcedTrackNotifier(this.sourceRef, this.url);

  final Ref sourceRef;
  final String url;

  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) {
    return SourcedTrack(
      deps: sourceRef.sourceDeps,
      info: SpotubeAudioSourceMatchObject(
        id: 'match-vpn',
        title: query.name,
        artists: const ['Test Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/vpn',
      ),
      query: query,
      source: 'youtube',
      siblings: const [],
      sources: [
        SpotubeAudioSourceStreamObject(
          url: url,
          container: 'weba',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ],
    );
  }
}

SpotubeFullTrackObject _testTrack(String id, String name) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'alb1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000$id',
    explicit: false,
  );
}

/// Loopback server answering HEAD plus a full-body GET. When [failFirstGet]
/// is true the first GET fails with 500 (retryable) and later ones succeed.
Future<HttpServer> _startServer(List<int> payload,
    {bool failFirstGet = false}) {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    var gets = 0;
    server.listen((req) async {
      if (req.method == 'HEAD') {
        req.response
          ..headers.set('content-length', '${payload.length}')
          ..headers.set('accept-ranges', 'bytes');
        await req.response.close();
        return;
      }
      gets++;
      if (failFirstGet && gets == 1) {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
        return;
      }
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.set('content-length', '${payload.length}');
      req.response.add(payload);
      await req.response.close();
    });
    return server;
  });
}

void main() {
  AppLogger.initialize(false);

  group('isVpnProtectionError', () {
    test('classifies direct and Dio-wrapped vpn failures', () {
      expect(
        isVpnProtectionError(const VpnProxyConflictException()),
        isTrue,
      );
      expect(
        isVpnProtectionError(const VpnNoRouteException('x')),
        isTrue,
      );
      expect(
        isVpnProtectionError(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.unknown,
            error: const VpnProxyConflictException(),
          ),
        ),
        isTrue,
        reason: 'Dio normalizes adapter throws to unknown, keeping .error',
      );
      expect(
        isVpnProtectionError(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionError,
            error: const SocketException('down'),
          ),
        ),
        isFalse,
        reason: 'plain transport failures stay retryable',
      );
      expect(isVpnProtectionError(StateError('x')), isFalse);
    });
  });

  late Directory tempRoot;
  late HttpServer server;
  late List<int> payload;
  ProviderContainer? container;
  late StubPrefsNotifier prefs;
  late FakeVpnBackend vpnBackend;
  late AppDatabase db;

  PreferencesTableData prefsBase() =>
      PreferencesTable.defaults().copyWith(downloadLocation: tempRoot.path);

  void buildTestContainer({
    required PreferencesTableData prefsData,
    VpnSystemBackend? backend,
  }) {
    prefs = StubPrefsNotifier(prefsData);
    final activeBackend = backend ?? vpnBackend;
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        userPreferencesProvider.overrideWith(() => prefs),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
        audioSourcePresetsProvider.overrideWith(
          () => FixedPresetsNotifier(
            AudioSourcePresetsState(
              presets: [
                SpotubeAudioSourceContainerPreset.lossy(
                  type: SpotubeMediaCompressionType.lossy,
                  name: 'weba',
                  qualities: [
                    SpotubeAudioLossyContainerQuality(bitrate: 128000)
                  ],
                ),
              ],
            ),
          ),
        ),
        sourcedTrackProvider.overrideWith(
          () => _FixedUrlSourcedTrackNotifier(
            container!.read(_refProbeProvider),
            'http://${server.address.host}:${server.port}/stream.weba',
          ),
        ),
        vpnManagerProvider.overrideWith(
          (ref) => RefCountVpnManager(
            backend: activeBackend,
            listInterfaces: fakeListInterfaces,
            readConfig: () {
              final p = ref.read(userPreferencesProvider);
              return VpnConfig(
                connectionUuid: p.vpnConnectionUuid,
                deviceName: p.vpnDeviceName,
                autoDisconnect: p.vpnAutoDisconnect,
                waitTimeout: Duration(seconds: p.vpnWaitTimeoutSec),
              );
            },
          ),
        ),
      ],
    );
  }

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('dl_vpn_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);
    payload = List.generate(32 * 1024, (i) => i % 256);
    server = await _startServer(payload);
    vpnBackend = FakeVpnBackend();
  });

  tearDown(() async {
    container?.dispose();
    container = null;
    await db.close();
    await server.close(force: true);
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  DownloadTask? taskState(String id) => container!
      .read(downloadManagerProvider)
      .firstWhereOrNull((e) => e.track.id == id);

  test('vpn disabled: download completes, backend untouched', () async {
    buildTestContainer(prefsData: prefsBase());
    final track = _testTrack('vpn-off-1', 'Vpn Off Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.completed,
      'ungated download to complete',
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
    expect(vpnBackend.broughtUp, isEmpty);
    expect(vpnBackend.broughtDown, isEmpty);
    expect(
      container!.read(vpnManagerProvider).activeLeaseCount,
      0,
      reason: 'no lease may leak when the gate is off',
    );
  });

  test('vpn required + already active: shared, never disconnected', () async {
    vpnBackend.active.add('uuid-a');
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
      ),
    );

    final track = _testTrack('vpn-shared-1', 'Vpn Shared Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.completed,
      'gated download on pre-existing VPN to complete',
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
    expect(vpnBackend.broughtUp, isEmpty);
    expect(vpnBackend.broughtDown, isEmpty,
        reason: 'must not disconnect a VPN Spotube did not start');
    expect(vpnBackend.active, contains('uuid-a'));
    expect(container!.read(vpnManagerProvider).activeLeaseCount, 0);
  });

  test('vpn required + inactive: connects once, disconnects when done',
      () async {
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
      ),
    );

    final track = _testTrack('vpn-owned-1', 'Vpn Owned Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.completed,
      'gated download to complete',
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
    expect(vpnBackend.broughtUp, ['uuid-a']);
    expect(vpnBackend.broughtDown, ['uuid-a']);
    expect(container!.read(vpnManagerProvider).activeLeaseCount, 0);
  });

  test('two concurrent downloads share one connection', () async {
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
      ),
    );

    final a = _testTrack('vpn-multi-a', 'Vpn Multi A');
    final b = _testTrack('vpn-multi-b', 'Vpn Multi B');
    final notifier = container!.read(downloadManagerProvider.notifier);
    notifier.addToQueue(a);
    notifier.addToQueue(b);

    await _waitFor(
      () =>
          taskState(a.id)?.status == DownloadStatus.completed &&
          taskState(b.id)?.status == DownloadStatus.completed,
      'both gated downloads to complete',
      timeoutMs: 15000,
      describe: () =>
          'a: ${taskState(a.id)?.status}, b: ${taskState(b.id)?.status}',
    );
    expect(vpnBackend.broughtUp, ['uuid-a'],
        reason: 'concurrent downloads must not flap the VPN');
    expect(vpnBackend.broughtDown, ['uuid-a'],
        reason: 'disconnect only after the final lease releases');
  });

  test('cancel during the vpn wait ends canceled, not failed', () async {
    vpnBackend.blockBringUp = Completer<void>();
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
        vpnWaitTimeoutSec: 30,
      ),
    );

    final track = _testTrack('vpn-cancel-1', 'Vpn Cancel Track');
    final notifier = container!.read(downloadManagerProvider.notifier);
    notifier.addToQueue(track);

    // The pool claims synchronously, so the task is `downloading` while
    // parked in the VPN wait — pre-transfer, nothing on disk yet.
    await Future.delayed(const Duration(milliseconds: 500));
    expect(taskState(track.id)?.status, DownloadStatus.downloading);

    notifier.cancel(track);

    // Status flips synchronously on cancel, but the parked acquire needs
    // one poll round to observe it — wait for the lease to drain too.
    await _waitFor(
      () =>
          taskState(track.id)?.status == DownloadStatus.canceled &&
          container!.read(vpnManagerProvider).activeLeaseCount == 0,
      'wait to observe cancellation and lease release',
      describe: () => 'last state: ${taskState(track.id)?.status}, '
          'leases: ${container!.read(vpnManagerProvider).activeLeaseCount}',
    );
  });

  test('unsupported backend while gated fails closed with vpn error', () async {
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
      ),
      backend: const UnsupportedVpnBackend(),
    );

    final track = _testTrack('vpn-unsupported-1', 'Vpn Unsupported Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.failed,
      'gated download on an unsupported platform to fail',
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
  });

  test('unresolvable pin fails the download closed', () async {
    vpnBackend.devices = const [];
    fakeTunnelAddresses = const [];
    try {
      buildTestContainer(
        prefsData: prefsBase().copyWith(
          vpnMode: VpnMode.downloadsOnly,
          vpnConnectionUuid: const Value('uuid-a'),
        ),
      );

      final track = _testTrack('vpn-nopin-1', 'Vpn NoPin Track');
      container!.read(downloadManagerProvider.notifier).addToQueue(track);

      await _waitFor(
        () => taskState(track.id)?.status == DownloadStatus.failed,
        'gated download without a pinnable interface to fail',
        describe: () => 'last state: ${taskState(track.id)?.status}',
      );
      // Connected but unpinnable must never authorize traffic: the owned
      // activation is undone rather than left running unpinned.
      expect(vpnBackend.broughtDown, ['uuid-a']);
      expect(container!.read(vpnManagerProvider).activeLeaseCount, 0);
    } finally {
      fakeTunnelAddresses = const ['127.0.0.1'];
    }
  });

  test('vpn loss mid-download pauses the retry until recovery', () async {
    await server.close(force: true);
    server = await _startServer(payload, failFirstGet: true);

    vpnBackend.active.add('uuid-a');
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnConnectionUuid: const Value('uuid-a'),
        vpnWaitTimeoutSec: 15,
      ),
    );

    final track = _testTrack('vpn-loss-1', 'Vpn Loss Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    // First GET fails (500, retryable) while the VPN drops; the retry must
    // wait for recovery rather than proceeding outside the VPN.
    await Future.delayed(const Duration(milliseconds: 300));
    vpnBackend.active.remove('uuid-a');
    await Future.delayed(const Duration(seconds: 4));
    expect(
      taskState(track.id)?.status,
      isNot(DownloadStatus.completed),
      reason: 'retry must pause while the VPN is down',
    );
    vpnBackend.active.add('uuid-a');

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.completed,
      'download to complete after VPN recovery',
      timeoutMs: 20000,
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
    // Recovery came from the environment, not a second activation.
    expect(vpnBackend.broughtUp, isEmpty);
    // Completion is published before the download loop's `finally` releases
    // the lease, so wait for the drain instead of racing that ordering.
    await _waitFor(
      () => container!.read(vpnManagerProvider).activeLeaseCount == 0,
      'lease to drain after recovery',
      describe: () => 'leases: ${container!.read(vpnManagerProvider).activeLeaseCount}',
    );
  });

  test('device target downloads pinned with no NM backend involved', () async {
    buildTestContainer(
      prefsData: prefsBase().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnDeviceName: const Value('tun0'),
      ),
      // Unsupported backend on purpose: the device flow must never need it.
      backend: const UnsupportedVpnBackend(),
    );

    final track = _testTrack('vpn-device-1', 'Vpn Device Track');
    container!.read(downloadManagerProvider.notifier).addToQueue(track);

    await _waitFor(
      () => taskState(track.id)?.status == DownloadStatus.completed,
      'device-gated download to complete',
      describe: () => 'last state: ${taskState(track.id)?.status}',
    );
    // Pinned to the loopback fake tunnel; nothing activated or dropped.
    expect(vpnBackend.broughtUp, isEmpty);
    expect(vpnBackend.broughtDown, isEmpty);
    expect(container!.read(vpnManagerProvider).activeLeaseCount, 0);
  });

  test('device target waits for the tunnel to appear', () async {
    fakeTunnelAddresses = const [];
    try {
      buildTestContainer(
        prefsData: prefsBase().copyWith(
          vpnMode: VpnMode.downloadsOnly,
          vpnDeviceName: const Value('tun0'),
          vpnWaitTimeoutSec: 15,
        ),
      );

      final track = _testTrack('vpn-device-wait-1', 'Vpn Device Wait Track');
      container!.read(downloadManagerProvider.notifier).addToQueue(track);

      await Future.delayed(const Duration(seconds: 1));
      expect(taskState(track.id)?.status, isNot(DownloadStatus.completed));

      fakeTunnelAddresses = const ['127.0.0.1'];
      await _waitFor(
        () => taskState(track.id)?.status == DownloadStatus.completed,
        'download to complete after the tunnel appears',
        timeoutMs: 20000,
        describe: () => 'last state: ${taskState(track.id)?.status}',
      );
    } finally {
      fakeTunnelAddresses = const ['127.0.0.1'];
    }
  });
}

final _refProbeProvider = Provider<Ref>((ref) => ref);

Future<void> _waitFor(
  bool Function() condition,
  String what, {
  int timeoutMs = 8000,
  required String Function() describe,
}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Timed out waiting for $what; ${describe()}');
}
