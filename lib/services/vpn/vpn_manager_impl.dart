import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:spotube/services/logger/logger.dart';

import 'vpn_backend.dart';
import 'vpn_lease.dart';
import 'vpn_manager.dart';
import 'vpn_pin.dart';

/// Reference-counted [VpnManager].
///
/// Lease model (mirrors the download pool's single-writer discipline):
/// - `acquire()` registers a lease synchronously, then ensures the VPN.
/// - The first live lease triggers at most one `bringUp`; concurrent leases
///   share it via [waitUntilConnected].
/// - The last [VpnLease.release] tears down only what Spotube started.
/// - `release()` is idempotent and never throws.
///
/// Ownership: the active set is snapshotted before `bringUp`. A connection
/// that was already active is used but never brought down by us. When
/// ownership cannot be established, we leave the system state unchanged.
class RefCountVpnManager implements VpnManager {
  final VpnSystemBackend backend;
  final VpnConfig Function() readConfig;

  /// Interface listing override for tests (fake tunnel devices).
  /// Null means the real `NetworkInterface.list` via [resolveVpnEndpoint].
  final ListInterfaces? listInterfaces;

  /// How often the active set is re-checked while leases are held.
  /// Event-driven monitoring (e.g. `nmcli monitor`) would be nicer, but a
  /// slow poll only while protected work is live is simple, bounded, and
  /// leaves zero timers behind when idle.
  static const Duration watchInterval = Duration(seconds: 5);

  /// How often waiters re-check state / cancellation.
  static const Duration waitPollInterval = Duration(milliseconds: 500);

  /// Cap on one activation poll round after `bringUp` was accepted.
  static const Duration activationPollInterval = Duration(seconds: 1);

  VpnStatus _status = VpnStatus.unknown;
  final StreamController<VpnStatus> _statusController =
      StreamController<VpnStatus>.broadcast();

  final Map<String, bool> _leases = {};
  int _leaseSerial = 0;

  /// UUID this manager brought up and may therefore bring down. Null when
  /// the connection was already active (unowned) or nothing is held.
  String? _ownedUuid;

  /// Tunnel endpoint sockets are source-pinned to while leases are held.
  /// Null means unresolvable — acquisition fails closed in that case, so a
  /// null pin with live leases is impossible outside dispose/release.
  VpnEndpoint? _pin;

  /// UUID currently tracked by the watch loop (the selected connection).
  String? _watchedUuid;

  /// Tunnel device tracked by the watch loop (share-only flow). Exactly one
  /// of [_watchedUuid]/[_watchedDevice] is set while leases are held.
  String? _watchedDevice;

  Timer? _watchTimer;

  RefCountVpnManager({
    required this.backend,
    required this.readConfig,
    this.listInterfaces,
  });

  @override
  bool get isSupported => backend.isAvailable;

  @override
  bool get supportsDeviceTargets => true;

  @override
  VpnStatus get currentStatus => _status;

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  @override
  int get activeLeaseCount => _leases.length;

  /// Address to source-pin sockets to, or null when no lease is held (or
  /// after disposal). Adapters read this live per connection.
  InternetAddress? readPin() => _leases.isEmpty ? null : _pin?.address;

  /// Best-effort pin refresh for long-held leases (VPN addresses change on
  /// reconnect). Keeps the old pin on failure and never throws — the next
  /// connection attempt fails closed on its own if the pin went stale.
  /// Called after every protection wait; cheap (one interface listing).
  /// Resolves against the currently watched target (UUID flow or exact
  /// device), so a renamed/recreated tunnel heals instead of sticking to a
  /// dead address.
  Future<void> refreshPin() async {
    if (_leases.isEmpty || _pin == null) return;
    try {
      final endpoint = await _resolvePin(deviceName: _watchedDevice);
      if (endpoint.address.address != _pin!.address.address) {
        AppLogger.log.i(
          'Vpn pin moved: ${_pin!.address.address} -> ${endpoint.address.address}',
        );
        _pin = endpoint;
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.refreshPin');
    }
  }

  Future<VpnEndpoint> _resolvePin({String? deviceName}) {
    final lister = listInterfaces;
    if (lister == null) {
      return resolveVpnEndpoint(backend: backend, deviceName: deviceName);
    }
    return resolveVpnEndpoint(
      backend: backend,
      deviceName: deviceName,
      listInterfaces: lister,
    );
  }

  /// Resolves the source pin after the connection is verified active.
  /// Throws [VpnNoRouteException] (failing the acquire closed) when no
  /// tunnel address can be found — a connected-but-unpinnable state must
  /// never authorize protected traffic.
  Future<void> _establishPin(String uuid) async {
    try {
      _pin = await _resolvePin();
    } catch (e, stack) {
      _setStatus(VpnStatus.error);
      AppLogger.reportError(e, stack, 'Vpn.establishPin');
      if (_ownedUuid == uuid) {
        try {
          await backend.bringDown(uuid);
        } catch (downError, downStack) {
          AppLogger.reportError(downError, downStack, 'Vpn.establishPin.undo');
        }
        _ownedUuid = null;
      }
      throw e is VpnException
          ? e
          : VpnNoRouteException('Cannot pin to VPN $uuid: $e');
    }
  }

  void _setStatus(VpnStatus status) {
    if (_status == status) return;
    _status = status;
    AppLogger.log.i('Vpn status -> $status');
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const VpnCancelledException();
    }
  }

  /// Completes with [VpnCancelledException] once [isCancelled] fires, or
  /// never when no cancellation source was given. Lets [Future.any] abort
  /// an in-flight activation wait without cancelling the backend call
  /// itself (which may not support cancellation).
  Future<void> _cancelSignal(bool Function()? isCancelled) async {
    if (isCancelled == null) {
      await Completer<void>().future;
      return;
    }
    while (!isCancelled()) {
      await Future.delayed(waitPollInterval);
    }
    throw const VpnCancelledException();
  }

  @override
  Future<void> waitUntilConnected({
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    final budget = timeout ?? readConfig().waitTimeout;
    final deadline = DateTime.now().add(budget);
    while (true) {
      _throwIfCancelled(isCancelled);
      // Ground the wait on the backend, not just the cached status: the
      // periodic watch (5 s) may not have observed a fresh loss yet, and a
      // retry hook must never mistake a stale `connected` for permission
      // to proceed outside the VPN.
      await _reconcileWithBackend();
      if (_status == VpnStatus.connected) return;
      if (DateTime.now().isAfter(deadline)) {
        throw VpnConnectTimeoutException(
          'VPN did not reach connected within ${budget.inSeconds}s',
        );
      }
      await Future.delayed(waitPollInterval);
    }
  }

  @override
  Future<VpnLease> acquire({bool Function()? isCancelled}) async {
    final config = readConfig();
    final uuid = (config.connectionUuid ?? '').isEmpty
        ? null
        : config.connectionUuid;
    // UUID wins when both are set: the managed flow is strictly stronger
    // (activation + verification) than sharing a live device.
    final device = uuid != null
        ? null
        : ((config.deviceName ?? '').isEmpty ? null : config.deviceName);
    if (uuid == null && device == null) {
      throw const VpnNoConnectionConfiguredException();
    }

    if (uuid != null && !backend.isAvailable) {
      throw const VpnUnsupportedException(
        'Automatic VPN is not supported on this platform yet',
      );
    }
    // Note: the device flow intentionally skips the availability check —
    // sharing a live tunnel needs no backend, only interface listing, so
    // it works wherever Dart lists interfaces (including non-Linux and
    // nmcli-less hosts).

    // Synchronous registration: no await before this runs, so two
    // concurrent acquirers cannot both believe they are first.
    final id = 'vpn-lease-${_leaseSerial++}';
    _leases[id] = true;
    AppLogger.log.i('Vpn lease acquired: $id (${_leases.length} live)');
    final isFirst = _leases.length == 1;

    try {
      if (isFirst) {
        if (uuid != null) {
          await _ensureConnected(uuid, config, isCancelled);
        } else {
          await _ensureDeviceConnected(device!, config, isCancelled);
        }
      } else {
        // Shared target: normally already up; if it flapped, wait
        // for recovery instead of issuing a second bringUp.
        await waitUntilConnected(
          timeout: config.waitTimeout,
          isCancelled: isCancelled,
        );
      }
    } catch (_) {
      _leases.remove(id);
      if (_leases.isEmpty) {
        _stopWatch();
        _ownedUuid = null;
      }
      rethrow;
    }
    return VpnLease(id, _release);
  }

  /// Bring [uuid] up unless it is already active. Verifies via the active
  /// set afterwards — a successful return code alone is never trusted.
  Future<void> _ensureConnected(
    String uuid,
    VpnConfig config,
    bool Function()? isCancelled,
  ) async {
    _throwIfCancelled(isCancelled);

    Set<String> active;
    try {
      active = await backend.activeUuids();
    } catch (e, stack) {
      _setStatus(VpnStatus.error);
      AppLogger.reportError(e, stack, 'Vpn.activeUuids');
      rethrow;
    }

    if (active.contains(uuid)) {
      _ownedUuid = null;
      await _establishPin(uuid);
      _setStatus(VpnStatus.connected);
      AppLogger.log.i('Vpn already connected (unowned, shared)');
      _startWatch(uuid: uuid);
      unawaited(_corroborateInterface());
      return;
    }

    _throwIfCancelled(isCancelled);
    _setStatus(VpnStatus.connecting);
    AppLogger.log.i('Vpn connection requested');

    // Activation races cancellation: a cancel during bringUp must abort
    // promptly (backends like Process.run cannot be cancelled, only
    // abandoned) and must not orphan a connection that did come up.
    var activated = false;
    try {
      await Future.any([
        backend.bringUp(uuid),
        _cancelSignal(isCancelled),
      ]);
      activated = true;
      _throwIfCancelled(isCancelled);
    } on VpnCancelledException {
      _setStatus(VpnStatus.disconnected);
      if (activated) {
        try {
          await backend.bringDown(uuid);
        } catch (e, stack) {
          AppLogger.reportError(e, stack, 'Vpn.bringUp.cancel.undo');
        }
      }
      rethrow;
    } catch (e, stack) {
      _setStatus(VpnStatus.error);
      AppLogger.reportError(e, stack, 'Vpn.bringUp');
      rethrow;
    }

    final deadline = DateTime.now().add(config.waitTimeout);
    while (true) {
      _throwIfCancelled(isCancelled);
      Set<String> current;
      try {
        current = await backend.activeUuids();
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'Vpn.activeUuids.poll');
        current = const {};
      }
      if (current.contains(uuid)) {
        _ownedUuid = uuid;
        await _establishPin(uuid);
        _setStatus(VpnStatus.connected);
        AppLogger.log.i('Vpn connection established (owned)');
        _startWatch(uuid: uuid);
        unawaited(_corroborateInterface());
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        _setStatus(VpnStatus.error);
        throw VpnConnectTimeoutException(
          'VPN did not become active within ${config.waitTimeout.inSeconds}s',
        );
      }
      await Future.delayed(activationPollInterval);
    }
  }

  /// Best-effort corroboration that a VPN interface exists. Advisory only:
  /// interface naming varies by provider, so absence is logged, never fatal.
  /// Uses the shared hint list so device naming stays in one place.
  Future<void> _corroborateInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      final found = interfaces.any(
        (i) => vpnInterfaceNameHints
            .any((h) => i.name.toLowerCase().contains(h)),
      );
      if (!found) {
        AppLogger.log.w(
          'Vpn connected but no VPN interface name detected; '
          'routing is managed by the system',
        );
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.corroborateInterface');
    }
  }

  /// Share-only acquisition for a tunnel device (e.g. a provider app's
  /// interface). Waits — bounded, cancellable — for the device to exist
  /// with addresses, then pins to it. Never activates, deactivates, or
  /// otherwise touches system state: there is no `bringUp`/`bringDown` on
  /// this path by construction, so ownership bugs are impossible.
  Future<void> _ensureDeviceConnected(
    String device,
    VpnConfig config,
    bool Function()? isCancelled,
  ) async {
    _throwIfCancelled(isCancelled);
    _setStatus(VpnStatus.connecting);
    AppLogger.log.i('Vpn waiting for tunnel device $device (app-managed)');

    final deadline = DateTime.now().add(config.waitTimeout);
    while (true) {
      _throwIfCancelled(isCancelled);
      try {
        _pin = await _resolvePin(deviceName: device);
        _watchedUuid = null;
        _watchedDevice = device;
        _setStatus(VpnStatus.connected);
        AppLogger.log.i('Vpn sharing active tunnel $device (app-managed)');
        _startWatch(device: device);
        return;
      } on VpnNoRouteException {
        // Device not (yet) present with addresses — keep waiting.
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'Vpn.ensureDevice');
      }
      if (DateTime.now().isAfter(deadline)) {
        _setStatus(VpnStatus.error);
        throw VpnConnectTimeoutException(
          'VPN device "$device" did not appear within '
          '${config.waitTimeout.inSeconds}s (is the tunnel connected?)',
        );
      }
      await Future.delayed(activationPollInterval);
    }
  }

  void _startWatch({String? uuid, String? device}) {
    assert(
      (uuid == null) != (device == null),
      'watch exactly one target: uuid or device',
    );
    _stopWatch();
    _watchedUuid = uuid;
    _watchedDevice = device;
    _watchTimer = Timer.periodic(watchInterval, (_) => unawaited(pollOnce()));
  }

  /// One watch round: reconcile [_status] with the backend's active set.
  /// The periodic timer calls this; tests drive it directly so no
  /// wall-clock wait is needed to cover loss/recovery.
  @visibleForTesting
  Future<void> pollOnce() async {
    if (_leases.isEmpty) {
      _stopWatch();
      return;
    }
    await _reconcileWithBackend();
  }

  /// Reconciles [_status] with live system state and flips
  /// `connected <-> disconnected` on change. UUID targets are checked
  /// against the backend's active set; device targets are re-resolved
  /// (presence + addresses), which also refreshes the pin — reconnects
  /// usually rotate the tunnel address.
  ///
  /// Best-effort: backend errors are reported, never thrown — a failed poll
  /// must not fail or unblock a protection wait by itself.
  Future<void> _reconcileWithBackend() async {
    try {
      final device = _watchedDevice;
      if (device != null) {
        await _reconcileDevice(device);
        return;
      }
      final watched = _watchedUuid;
      if (watched == null) return;
      final active = await backend.activeUuids();
      if (!active.contains(watched)) {
        if (_status == VpnStatus.connected) {
          AppLogger.log.w('Vpn connection lost during protected work');
          _setStatus(VpnStatus.disconnected);
        }
      } else {
        if (_status == VpnStatus.disconnected ||
            _status == VpnStatus.error) {
          AppLogger.log.i('Vpn connection recovered');
          _setStatus(VpnStatus.connected);
        }
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.watch');
    }
  }

  Future<void> _reconcileDevice(String device) async {
    VpnEndpoint endpoint;
    try {
      endpoint = await _resolvePin(deviceName: device);
    } on VpnException {
      // Tunnel gone (or unresolvable): mark the loss, keep waiting.
      // Non-Vpn backend errors fall through to the outer report.
      if (_status == VpnStatus.connected) {
        AppLogger.log.w('Vpn tunnel device $device lost during protected work');
        _setStatus(VpnStatus.disconnected);
      }
      return;
    }
    _pin = endpoint;
    if (_status == VpnStatus.disconnected || _status == VpnStatus.error) {
      AppLogger.log.i(
        'Vpn tunnel device $device recovered (${endpoint.address.address})',
      );
      _setStatus(VpnStatus.connected);
    }
  }

  void _stopWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _watchedUuid = null;
    _watchedDevice = null;
  }

  /// Release side of [VpnLease]. Idempotent (unknown ids are a no-op) and
  /// never throws, so `finally` blocks stay safe.
  Future<void> _release(String id) async {
    if (!_leases.containsKey(id)) {
      AppLogger.log.w('Vpn double release ignored: $id');
      return;
    }
    _leases.remove(id);
    AppLogger.log.i('Vpn lease released: $id (${_leases.length} live)');
    if (_leases.isNotEmpty) return;

    _stopWatch();
    final owned = _ownedUuid;
    _ownedUuid = null;
    // Drop the pin with the last lease: adapters delegate unpinned again
    // from here on (readPin returns null with no leases).
    _pin = null;
    if (owned == null) {
      // Unowned (pre-existing) connection: leave the user's state alone.
      return;
    }
    if (!readConfig().autoDisconnect) {
      AppLogger.log.i('Vpn left connected (auto-disconnect off)');
      return;
    }
    _setStatus(VpnStatus.disconnecting);
    AppLogger.log.i('Vpn disconnect requested (owned)');
    try {
      await backend.bringDown(owned);
      _setStatus(VpnStatus.disconnected);
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.bringDown');
      _setStatus(VpnStatus.error);
    }
  }

  @override
  Future<List<VpnConnection>> listConnections() => backend.listConnections();

  /// Tunnel device names known to the backend (NetworkManager device table).
  /// Used by the settings picker to mark verified tunnels. Throws
  /// [VpnUnsupportedException] where no backend exists — callers isolate
  /// that per UI section rather than failing the whole picker.
  Future<List<String>> vpnDeviceNames() => backend.vpnDeviceNames();

  @override
  void dispose() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _leases.clear();
    _pin = null;
    final owned = _ownedUuid;
    _ownedUuid = null;
    if (owned != null && readConfig().autoDisconnect) {
      // Best-effort: shutdown must not hang on the network.
      unawaited(_guardedBringDown(owned));
    }
    if (!_statusController.isClosed) {
      unawaited(_statusController.close());
    }
  }

  Future<void> _guardedBringDown(String uuid) async {
    try {
      await backend.bringDown(uuid).timeout(
            RealNmcliTimeouts.disposeBringDown,
          );
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.dispose.bringDown');
    }
  }
}

/// Bounds kept next to the manager so tests import one file.
abstract final class RealNmcliTimeouts {
  static const Duration disposeBringDown = Duration(seconds: 10);
}
