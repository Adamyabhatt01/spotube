import 'vpn_lease.dart';

export 'vpn_mode.dart';

/// Observable VPN state. Kept deliberately small: callers only need to know
/// whether protected work may proceed (`connected`) or must wait/fail.
enum VpnStatus {
  unknown,
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

/// A user-owned system VPN connectionendum, as listed by the backend.
///
/// Only identity fields — never credentials. Authentication stays with the
/// operating system / NetworkManager; Spotube never sees secrets.
class VpnConnection {
  final String uuid;
  final String name;
  final String type;

  const VpnConnection({
    required this.uuid,
    required this.name,
    required this.type,
  });

  @override
  String toString() => 'VpnConnection(name: $name, uuid: $uuid, type: $type)';
}

/// Snapshot of the automation settings relevant to one VPN operation.
///
/// Read live (via a callback) at every acquire so a settings change applies
/// to the next operation without rebuilding the manager — rebuilding would
/// drop the live lease count.
///
/// Two target kinds: [connectionUuid] is a NetworkManager connection the
/// manager may activate/deactivate; [deviceName] is a live tunnel device
/// (e.g. a provider app's interface) the manager only waits for and shares,
/// never touching system state. When both are set, the UUID wins.
class VpnConfig {
  final String? connectionUuid;
  final String? deviceName;
  final bool autoDisconnect;
  final Duration waitTimeout;

  const VpnConfig({
    required this.connectionUuid,
    this.deviceName,
    required this.autoDisconnect,
    required this.waitTimeout,
  });

  /// Whether any target is selected at all.
  bool get hasTarget =>
      (connectionUuid ?? '').isNotEmpty || (deviceName ?? '').isNotEmpty;
}

/// Base for all VPN failures. Protected operations fail closed with one of
/// these — never silently continue outside the VPN.
class VpnException implements Exception {
  final String message;
  const VpnException(this.message);

  @override
  String toString() => 'VpnException: $message';
}

/// Thrown when the platform/backend cannot automate a VPN at all
/// (non-Linux today, or no `nmcli` on PATH).
class VpnUnsupportedException extends VpnException {
  const VpnUnsupportedException(super.message);
}

/// Thrown when automation is on but no target was selected — neither a
/// system connection nor a tunnel device.
class VpnNoConnectionConfiguredException extends VpnException {
  const VpnNoConnectionConfiguredException()
      : super('No VPN connection or tunnel device selected in settings');
}

/// Thrown when the VPN did not reach `connected` inside the wait budget,
/// or disappeared and did not return inside it.
class VpnConnectTimeoutException extends VpnException {
  const VpnConnectTimeoutException(super.message);
}

/// Thrown when the VPN disappeared while a protected operation was running.
/// Callers using the pause-and-wait policy wait first; this is what surfaces
/// when the wait budget expires.
class VpnLostDuringOperationException extends VpnException {
  const VpnLostDuringOperationException()
      : super('VPN connection lost during protected operation');
}

/// Thrown when the VPN permission check or activation is refused by the
/// system. Never retried silently.
class VpnPermissionDeniedException extends VpnException {
  const VpnPermissionDeniedException(super.message);
}

/// Thrown when protection is required but no source-IP pin can be resolved
/// (no VPN interface address found). The operation fails closed rather
/// than transmitting unpinned.
class VpnNoRouteException extends VpnException {
  const VpnNoRouteException(super.message);
}

/// Thrown when a pinned request would have to traverse an HTTP proxy, which
/// the pinning factory cannot see through. Fail-closed by design: proxy +
/// gated traffic is a corner with no silent-safe answer.
class VpnProxyConflictException extends VpnException {
  const VpnProxyConflictException()
      : super('Pinned request cannot traverse a configured HTTP proxy');
}

/// Thrown to abort a VPN wait when the protected operation was cancelled.
/// Carries no error semantics — callers translate it to their own
/// cancellation path (e.g. the download `canceled` status).
class VpnCancelledException extends VpnException {
  const VpnCancelledException() : super('VPN wait cancelled');
}

/// Platform-independent VPN automation.
///
/// All protected work goes through [acquire]: the first live lease brings
/// the VPN up, concurrent leases share it, and the last release drops it
/// (only when Spotube itself brought it up — see ownership notes on the
/// implementation). This makes connect/disconnect flapping structurally
/// impossible: there is no public bare `connect()`/`disconnect()` path.
abstract interface class VpnManager {
  /// Synchronous capability flag. False on platforms with no backend.
  /// (A true value does not guarantee the helper binary exists — that is
  /// checked at operation time and fails closed.)
  bool get isSupported;

  /// Whether share-only tunnel-device targets work here. Pure-Dart path
  /// (interface listing + socket pinning), so true everywhere — including
  /// platforms where [isSupported] is false and nmcli-less hosts.
  bool get supportsDeviceTargets;

  /// Last known state. Transitions are broadcast on [statusStream].
  VpnStatus get currentStatus;

  /// Broadcast of every state transition. No per-poll spam: the manager
  /// only polls while at least one lease is live.
  Stream<VpnStatus> get statusStream;

  /// Number of currently held leases (diagnostics/tests).
  int get activeLeaseCount;

  /// Acquire one lease on the VPN, ensuring it is connected first.
  ///
  /// Pause-and-wait: when the VPN is down this waits (bounded by the
  /// configured wait timeout) instead of failing immediately. [isCancelled]
  /// is polled during the wait so download cancellation aborts promptly.
  ///
  /// Throws a [VpnException] on any failure — callers fail the protected
  /// operation closed, never fall back to clearnet.
  Future<VpnLease> acquire({bool Function()? isCancelled});

  /// Wait until [currentStatus] is `connected`, bounded by [timeout] (or the
  /// configured wait timeout when null). Used before retry attempts so a
  /// mid-operation VPN loss pauses instead of hammering clearnet.
  Future<void> waitUntilConnected({
    Duration? timeout,
    bool Function()? isCancelled,
  });

  /// User-visible system connections for the settings picker.
  Future<List<VpnConnection>> listConnections();

  /// Synchronous shutdown: stops status polling, drops lease bookkeeping,
  /// closes the status stream. A Spotube-owned connection is brought down
  /// best-effort (unawaited, bounded) when auto-disconnect is on.
  void dispose();
}
