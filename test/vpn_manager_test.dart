// Unit tests for the VPN lease/reference layer.
//
// Uses a fake system backend only — no `nmcli`, no real VPN, no network.
// Covers: manager states, connect success/failure/timeout, lease
// ref-counting, idempotent release, exception/cancel safety, ownership
// (never disconnect what Spotube did not start), loss/recovery polling,
// and the nmcli terse-line parser.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/vpn/nmcli_backend.dart';
import 'package:spotube/services/vpn/unsupported_backend.dart';
import 'package:spotube/services/vpn/vpn_backend.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_manager_impl.dart';

class FakeVpnBackend implements VpnSystemBackend {
  FakeVpnBackend({bool available = true}) : _available = available;

  final bool _available;
  final Set<String> active = {};
  final List<String> broughtUp = [];
  final List<String> broughtDown = [];
  Object? bringUpError;
  Duration bringUpDelay = Duration.zero;
  List<String> devices = const ['tun0'];

  @override
  bool get isAvailable => _available;

  @override
  Future<Set<String>> activeUuids() async => Set.of(active);

  @override
  Future<List<VpnConnection>> listConnections() async => const [
        VpnConnection(uuid: 'uuid-a', name: 'Office VPN', type: 'vpn'),
        VpnConnection(
            uuid: 'uuid-b', name: 'Home WireGuard', type: 'wireguard'),
      ];

  @override
  Future<void> bringUp(String uuid) async {
    broughtUp.add(uuid);
    if (bringUpError != null) throw bringUpError!;
    await Future.delayed(bringUpDelay);
    active.add(uuid);
  }

  @override
  Future<void> bringDown(String uuid) async {
    broughtDown.add(uuid);
    active.remove(uuid);
  }

  @override
  Future<List<String>> vpnDeviceNames() async => List.of(devices);
}

/// Fake tunnel interface for pin-resolution tests.
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

Future<List<NetworkInterface>> fakeListInterfaces({
  bool includeLoopback = false,
  bool includeLinkLocal = false,
  InternetAddressType type = InternetAddressType.any,
}) async =>
    [
      FakeNetworkInterface('tun0', ['10.8.0.2'])
    ];

Future<List<NetworkInterface>> emptyListInterfaces({
  bool includeLoopback = false,
  bool includeLinkLocal = false,
  InternetAddressType type = InternetAddressType.any,
}) async =>
    <NetworkInterface>[];

VpnConfig _config({
  String? uuid = 'uuid-a',
  String? device,
  bool autoDisconnect = true,
  Duration waitTimeout = const Duration(seconds: 5),
}) =>
    VpnConfig(
      connectionUuid: uuid,
      deviceName: device,
      autoDisconnect: autoDisconnect,
      waitTimeout: waitTimeout,
    );

void main() {
  AppLogger.initialize(false);

  group('VpnMode helpers', () {
    test('gate matrix', () {
      expect(vpnModeGatesDownloads(VpnMode.disabled), isFalse);
      expect(vpnModeGatesDownloads(VpnMode.downloadsOnly), isTrue);
      expect(vpnModeGatesDownloads(VpnMode.playbackOnly), isFalse);
      expect(vpnModeGatesDownloads(VpnMode.downloadsAndPlayback), isTrue);

      expect(vpnModeGatesPlayback(VpnMode.disabled), isFalse);
      expect(vpnModeGatesPlayback(VpnMode.downloadsOnly), isFalse);
      expect(vpnModeGatesPlayback(VpnMode.playbackOnly), isTrue);
      expect(vpnModeGatesPlayback(VpnMode.downloadsAndPlayback), isTrue);
    });
  });

  group('RefCountVpnManager states', () {
    test('starts unknown with no leases', () {
      final manager = RefCountVpnManager(
        backend: FakeVpnBackend(),
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      expect(manager.currentStatus, VpnStatus.unknown);
      expect(manager.activeLeaseCount, 0);
      expect(manager.isSupported, isTrue);
      manager.dispose();
    });

    test('unsupported backend fails acquire closed', () async {
      final manager = RefCountVpnManager(
        backend: const UnsupportedVpnBackend(),
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      expect(manager.isSupported, isFalse);
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnUnsupportedException>()),
      );
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('missing connection selection fails closed', () async {
      final manager = RefCountVpnManager(
        backend: FakeVpnBackend(),
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(uuid: null),
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnNoConnectionConfiguredException>()),
      );
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('already-connected VPN is shared, never owned', () async {
      final backend = FakeVpnBackend()..active.add('uuid-a');
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(backend.broughtUp, isEmpty);

      await lease.release();
      expect(backend.broughtDown, isEmpty,
          reason: 'must not disconnect a VPN Spotube did not start');
      manager.dispose();
    });

    test('first acquire connects, final release disconnects', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(backend.broughtUp, ['uuid-a']);

      await lease.release();
      expect(backend.broughtDown, ['uuid-a']);
      expect(manager.currentStatus, VpnStatus.disconnected);
      manager.dispose();
    });

    test('bringUp failure surfaces and drops the lease', () async {
      final backend = FakeVpnBackend()
        ..bringUpError = const VpnPermissionDeniedException('denied');
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnPermissionDeniedException>()),
      );
      expect(manager.currentStatus, VpnStatus.error);
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('activation that never appears times out', () async {
      final backend = FakeVpnBackend();
      // bringUp "succeeds" but the UUID never joins the active set.
      final manager = RefCountVpnManager(
        backend: _NeverActiveBackend(backend),
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(waitTimeout: const Duration(seconds: 2)),
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnConnectTimeoutException>()),
      );
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('cancel during connect wait aborts as cancelled', () async {
      var cancelled = false;
      final backend = FakeVpnBackend()
        ..bringUpDelay = const Duration(seconds: 5);
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      // Cancel fires while bringUp is still in flight.
      unawaited(Future.delayed(
        const Duration(milliseconds: 200),
        () => cancelled = true,
      ));
      await expectLater(
        manager.acquire(isCancelled: () => cancelled),
        throwsA(isA<VpnCancelledException>()),
      );
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test(
        'a won activation releases its cancel signal instead of polling '
        'forever', () async {
      // The leak: `_cancelSignal` was the `Future.any` loser whenever
      // `bringUp` won — i.e. on every successful VPN-gated download — and its
      // `while (!isCancelled())` loop had no exit for that case, because a
      // download that completes never reports itself cancelled. One 2 Hz loop
      // leaked per download, for the life of the process.
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );

      final lease = await manager.acquire(isCancelled: () => false);
      expect(lease, isNotNull);

      // The race has settled, so the signal must be finished, not polling.
      final settledAt = manager.debugCancelPolls;
      await Future<void>.delayed(
        RefCountVpnManager.waitPollInterval * 4,
      );
      expect(
        manager.debugCancelPolls,
        settledAt,
        reason: 'the cancel-signal poll kept running after bringUp won',
      );

      await lease.release();
      manager.dispose();
    });
  });

  group('lease ref-counting', () {
    test('second acquire reuses, first release keeps, last release drops',
        () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final a = await manager.acquire();
      final b = await manager.acquire();
      expect(backend.broughtUp, ['uuid-a']);
      expect(manager.activeLeaseCount, 2);

      await a.release();
      expect(backend.broughtDown, isEmpty);
      expect(manager.currentStatus, VpnStatus.connected);

      await b.release();
      expect(backend.broughtDown, ['uuid-a']);
      manager.dispose();
    });

    test('double release is safe', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      await lease.release();
      await lease.release();
      expect(backend.broughtDown, ['uuid-a']);
      manager.dispose();
    });

    test('exception inside the guarded block still releases', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      try {
        throw StateError('work failed');
      } catch (_) {
        // Simulated protected-work failure: the finally below must
        // still release the lease.
      } finally {
        await lease.release();
      }
      expect(manager.activeLeaseCount, 0);
      expect(backend.broughtDown, ['uuid-a']);
      manager.dispose();
    });

    test('autoDisconnect off leaves an owned connection up', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(autoDisconnect: false),
      );
      final lease = await manager.acquire();
      await lease.release();
      expect(backend.broughtUp, ['uuid-a']);
      expect(backend.broughtDown, isEmpty);
      expect(backend.active, contains('uuid-a'));
      manager.dispose();
    });

    test('acquire/acquire/release/release and acquire/release/acquire',
        () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final a = await manager.acquire();
      final b = await manager.acquire();
      await a.release();
      await b.release();
      expect(backend.broughtUp, ['uuid-a']);
      expect(backend.broughtDown, ['uuid-a']);

      final c = await manager.acquire();
      expect(backend.broughtUp, ['uuid-a', 'uuid-a']);
      await c.release();
      expect(backend.broughtDown, ['uuid-a', 'uuid-a']);
      manager.dispose();
    });
  });

  group('waitUntilConnected', () {
    test('returns immediately when connected', () async {
      final backend = FakeVpnBackend()..active.add('uuid-a');
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      await manager.waitUntilConnected(
        timeout: const Duration(seconds: 3),
      );
      await lease.release();
      manager.dispose();
    });

    test('waits for recovery, then returns', () async {
      final backend = FakeVpnBackend()..active.add('uuid-a');
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      // Simulate a drop observed by the watcher.
      backend.active.remove('uuid-a');
      await manager.pollOnce();
      expect(manager.currentStatus, VpnStatus.disconnected);

      unawaited(Future.delayed(
        const Duration(milliseconds: 300),
        () => backend.active.add('uuid-a'),
      ));
      // Recovery is observed by polling, so drive one round after the add.
      unawaited(Future.delayed(
        const Duration(milliseconds: 600),
        () => manager.pollOnce(),
      ));
      await manager.waitUntilConnected(
        timeout: const Duration(seconds: 5),
      );
      expect(manager.currentStatus, VpnStatus.connected);
      await lease.release();
      manager.dispose();
    });

    test('times out when the VPN stays down', () async {
      final backend = FakeVpnBackend()..active.add('uuid-a');
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      backend.active.remove('uuid-a');
      await manager.pollOnce();
      await expectLater(
        manager.waitUntilConnected(
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<VpnConnectTimeoutException>()),
      );
      await lease.release();
      manager.dispose();
    });
  });

  group('loss / recovery polling', () {
    test('external disappearance flips state, return restores it', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);

      backend.active.remove('uuid-a');
      await manager.pollOnce();
      expect(manager.currentStatus, VpnStatus.disconnected);

      backend.active.add('uuid-a');
      await manager.pollOnce();
      expect(manager.currentStatus, VpnStatus.connected);
      await lease.release();
      manager.dispose();
    });

    test('status transitions are broadcast', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        listInterfaces: fakeListInterfaces,
        readConfig: () => _config(),
      );
      final seen = <VpnStatus>[];
      final sub = manager.statusStream.listen(seen.add);
      final lease = await manager.acquire();
      backend.active.remove('uuid-a');
      await manager.pollOnce();
      await lease.release();
      manager.dispose();
      await sub.cancel();
      expect(seen, containsAll([VpnStatus.connected, VpnStatus.disconnected]));
    });
  });
  group('provider gates', () {
    test('disabled or unconfigured modes gate nothing', () {
      var prefs = PreferencesTable.defaults();
      expect(vpnGatesDownloadsPrefs(prefs), isFalse);
      expect(vpnGatesPlaybackPrefs(prefs), isFalse);

      prefs = prefs.copyWith(vpnMode: VpnMode.downloadsOnly);
      expect(vpnGatesDownloadsPrefs(prefs), isFalse,
          reason: 'mode without a target must not gate');

      prefs = prefs.copyWith(
        vpnConnectionUuid: const Value('uuid-a'),
      );
      expect(vpnGatesDownloadsPrefs(prefs), isTrue);
      expect(vpnGatesPlaybackPrefs(prefs), isFalse);
    });

    test('device-only targets gate without a uuid', () {
      final prefs = PreferencesTable.defaults().copyWith(
        vpnMode: VpnMode.downloadsOnly,
        vpnDeviceName: const Value('tun0'),
      );
      expect(vpnGatesDownloadsPrefs(prefs), isTrue);
      expect(vpnGatesPlaybackPrefs(prefs), isFalse);
      expect(vpnTargetSelected(prefs), isTrue);

      final neither = PreferencesTable.defaults().copyWith(
        vpnMode: VpnMode.downloadsAndPlayback,
      );
      expect(vpnGatesDownloadsPrefs(neither), isFalse);
      expect(vpnTargetSelected(neither), isFalse);
    });

    test('configured modes gate their operations', () {
      final prefs = PreferencesTable.defaults().copyWith(
        vpnMode: VpnMode.downloadsAndPlayback,
        vpnConnectionUuid: const Value('uuid-a'),
      );
      expect(vpnGatesDownloadsPrefs(prefs), isTrue);
      expect(vpnGatesPlaybackPrefs(prefs), isTrue);

      final playbackOnly = prefs.copyWith(vpnMode: VpnMode.playbackOnly);
      expect(vpnGatesDownloadsPrefs(playbackOnly), isFalse);
      expect(vpnGatesPlaybackPrefs(playbackOnly), isTrue);
    });
  });

  group('nmcli terse parser', () {
    test('splits plain and escaped lines', () {
      expect(
        RealNmcliBackend.splitTerseLine('uuid-a:Office VPN:vpn'),
        ['uuid-a', 'Office VPN', 'vpn'],
      );
      expect(
        RealNmcliBackend.splitTerseLine(
          'uuid-b:Name\\: with\\: colons:wireguard',
        ),
        ['uuid-b', 'Name: with: colons', 'wireguard'],
      );
      expect(RealNmcliBackend.splitTerseLine(''), ['']);
    });

    test('recognizes vpn device types', () {
      expect(RealNmcliBackend.isVpnType('vpn'), isTrue);
      expect(RealNmcliBackend.isVpnType('wireguard'), isTrue);
      expect(RealNmcliBackend.isVpnType('tun'), isTrue);
      expect(RealNmcliBackend.isVpnType('WireGuard'), isTrue);
      expect(RealNmcliBackend.isVpnType('wifi'), isFalse);
      expect(RealNmcliBackend.isVpnType('ethernet'), isFalse);
      expect(RealNmcliBackend.isVpnType('loopback'), isFalse);
    });
  });

  group('source pin', () {
    test('readPin tracks the held lease', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(),
        listInterfaces: fakeListInterfaces,
      );
      expect(manager.readPin(), isNull);

      final lease = await manager.acquire();
      expect(manager.readPin()?.address, '10.8.0.2');

      await lease.release();
      expect(manager.readPin(), isNull);
      manager.dispose();
    });

    test('unresolvable pin fails the acquire closed', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(),
        listInterfaces: emptyListInterfaces,
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnNoRouteException>()),
      );
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('unresolvable pin undoes an owned activation', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(),
        listInterfaces: emptyListInterfaces,
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnNoRouteException>()),
      );
      // The activation went through before pin resolution failed, so the
      // manager must undo what it started rather than orphan it.
      expect(backend.broughtUp, ['uuid-a']);
      expect(backend.broughtDown, ['uuid-a']);
      expect(backend.active, isNot(contains('uuid-a')));
      manager.dispose();
    });

    test('refreshPin follows a changed address', () async {
      var addresses = ['10.8.0.2'];
      Future<List<NetworkInterface>> movingInterfaces({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async =>
          [FakeNetworkInterface('tun0', addresses)];
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(),
        listInterfaces: movingInterfaces,
      );
      final lease = await manager.acquire();
      expect(manager.readPin()?.address, '10.8.0.2');

      addresses = ['10.8.0.7'];
      await manager.refreshPin();
      expect(manager.readPin()?.address, '10.8.0.7');

      await lease.release();
      manager.dispose();
    });

    test('refreshPin keeps the old pin when resolution fails', () async {
      var fail = false;
      Future<List<NetworkInterface>> flakyInterfaces({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async {
        if (fail) throw const SocketException('interfaces gone');
        return [
          FakeNetworkInterface('tun0', ['10.8.0.2'])
        ];
      }

      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(),
        listInterfaces: flakyInterfaces,
      );
      final lease = await manager.acquire();
      fail = true;
      await manager.refreshPin();
      expect(manager.readPin()?.address, '10.8.0.2');
      await lease.release();
      manager.dispose();
    });
  });

  group('share-only device targets', () {
    test('live device is shared without backend calls', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(uuid: null, device: 'tun0'),
        listInterfaces: fakeListInterfaces,
      );
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(manager.readPin()?.address, '10.8.0.2');
      expect(backend.broughtUp, isEmpty);

      await lease.release();
      expect(backend.broughtDown, isEmpty,
          reason: 'device flow never touches activation state');
      expect(manager.readPin(), isNull);
      expect(manager.activeLeaseCount, 0);
      manager.dispose();
    });

    test('device appearing during the wait is picked up', () async {
      var present = false;
      Future<List<NetworkInterface>> appearingInterfaces({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async =>
          present
              ? [
                  FakeNetworkInterface('tun0', ['10.8.0.2'])
                ]
              : <NetworkInterface>[];
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(uuid: null, device: 'tun0'),
        listInterfaces: appearingInterfaces,
      );
      unawaited(Future.delayed(
        const Duration(milliseconds: 300),
        () => present = true,
      ));
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(backend.broughtUp, isEmpty);
      await lease.release();
      manager.dispose();
    });

    test('device that never appears times out fail-closed', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(
          uuid: null,
          device: 'tun0',
          waitTimeout: const Duration(seconds: 2),
        ),
        listInterfaces: emptyListInterfaces,
      );
      await expectLater(
        manager.acquire(),
        throwsA(isA<VpnConnectTimeoutException>()),
      );
      expect(manager.activeLeaseCount, 0);
      expect(backend.broughtUp, isEmpty);
      expect(backend.broughtDown, isEmpty);
      manager.dispose();
    });

    test('device loss pauses, return with new address recovers + repins',
        () async {
      var addresses = ['10.8.0.2'];
      Future<List<NetworkInterface>> movingInterfaces({
        bool includeLoopback = false,
        bool includeLinkLocal = false,
        InternetAddressType type = InternetAddressType.any,
      }) async =>
          [FakeNetworkInterface('tun0', addresses)];
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(uuid: null, device: 'tun0'),
        listInterfaces: movingInterfaces,
      );
      final lease = await manager.acquire();
      expect(manager.readPin()?.address, '10.8.0.2');

      // Tunnel drops: empty address list is "device without route".
      addresses = [];
      await manager.pollOnce();
      expect(manager.currentStatus, VpnStatus.disconnected);

      // Tunnel returns with a rotated address: recovery must re-pin.
      addresses = ['10.8.0.9'];
      await manager.pollOnce();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(manager.readPin()?.address, '10.8.0.9');

      await lease.release();
      expect(backend.broughtUp, isEmpty);
      expect(backend.broughtDown, isEmpty);
      manager.dispose();
    });

    test('uuid wins when both targets are set', () async {
      final backend = FakeVpnBackend();
      final manager = RefCountVpnManager(
        backend: backend,
        readConfig: () => _config(uuid: 'uuid-a', device: 'tun0'),
        listInterfaces: fakeListInterfaces,
      );
      final lease = await manager.acquire();
      expect(backend.broughtUp, ['uuid-a'],
          reason: 'managed flow takes precedence over device sharing');
      await lease.release();
      expect(backend.broughtDown, ['uuid-a']);
      manager.dispose();
    });

    test('device flow works with an unsupported backend', () async {
      // The whole point: provider-app tunnels need no NM backend.
      final manager = RefCountVpnManager(
        backend: const UnsupportedVpnBackend(),
        readConfig: () => _config(uuid: null, device: 'tun0'),
        listInterfaces: fakeListInterfaces,
      );
      expect(manager.isSupported, isFalse);
      expect(manager.supportsDeviceTargets, isTrue);
      final lease = await manager.acquire();
      expect(manager.currentStatus, VpnStatus.connected);
      expect(manager.readPin()?.address, '10.8.0.2');
      await lease.release();
      manager.dispose();
    });
  });
}

/// Backend whose `bringUp` reports success but never activates the UUID,
/// exercising the manager's verify-after-up path (a return code alone is
/// never trusted).
class _NeverActiveBackend implements VpnSystemBackend {
  _NeverActiveBackend(this.inner);

  final FakeVpnBackend inner;

  @override
  bool get isAvailable => inner.isAvailable;

  @override
  Future<Set<String>> activeUuids() async => const {};

  @override
  Future<List<VpnConnection>> listConnections() => inner.listConnections();

  @override
  Future<void> bringUp(String uuid) async {
    inner.broughtUp.add(uuid);
  }

  @override
  Future<void> bringDown(String uuid) => inner.bringDown(uuid);

  @override
  Future<List<String>> vpnDeviceNames() => inner.vpnDeviceNames();
}
