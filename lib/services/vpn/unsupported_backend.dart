import 'vpn_backend.dart';
import 'vpn_manager.dart';

/// Backend for every platform Spotube cannot automate safely (Android,
/// Windows, macOS, iOS, Web today).
///
/// Reports unavailable and fails every operation closed with
/// [VpnUnsupportedException] — never a fake "connected".
class UnsupportedVpnBackend implements VpnSystemBackend {
  const UnsupportedVpnBackend();

  @override
  bool get isAvailable => false;

  static const _message = 'Automatic VPN is not supported on this platform yet';

  @override
  Future<Set<String>> activeUuids() async {
    throw const VpnUnsupportedException(_message);
  }

  @override
  Future<List<VpnConnection>> listConnections() async {
    throw const VpnUnsupportedException(_message);
  }

  @override
  Future<void> bringUp(String uuid) async {
    throw const VpnUnsupportedException(_message);
  }

  @override
  Future<void> bringDown(String uuid) async {
    throw const VpnUnsupportedException(_message);
  }

  @override
  Future<List<String>> vpnDeviceNames() async {
    throw const VpnUnsupportedException(_message);
  }
}
