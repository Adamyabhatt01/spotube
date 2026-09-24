import 'vpn_manager.dart';

/// Test seam between [VpnManager] and the operating system.
///
/// Production code gets `RealNmcliBackend` (Linux/NetworkManager) or
/// `UnsupportedVpnManager`-style backends; unit tests get a fake. No unit
/// test may depend on a real VPN, a real `nmcli`, or real system state.
abstract interface class VpnSystemBackend {
  /// Synchronous platform capability: does this backend even apply here?
  /// (Whether the helper binary exists is checked per operation.)
  bool get isAvailable;

  /// UUIDs of currently active (connected) VPN connections.
  Future<Set<String>> activeUuids();

  /// All known VPN connections (active or not) for the settings picker.
  Future<List<VpnConnection>> listConnections();

  /// Request activation of [uuid]. Returning does NOT mean usable — the
  /// manager verifies via [activeUuids] afterwards.
  Future<void> bringUp(String uuid);

  /// Request deactivation of [uuid]. Best-effort from the manager's side.
  Future<void> bringDown(String uuid);

  /// OS device names (e.g. `tun0`, `wg0`) currently owned by VPN-type
  /// connections. Used to bind the source-IP pin to a real tunnel device.
  /// Never throws a "connected" claim — callers treat an empty or stale
  /// list as unresolvable and fail closed.
  Future<List<String>> vpnDeviceNames();
}
