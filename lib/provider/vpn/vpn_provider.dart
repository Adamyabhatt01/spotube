import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/vpn/nmcli_backend.dart';
import 'package:spotube/services/vpn/unsupported_backend.dart';
import 'package:spotube/services/vpn/vpn_backend.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_manager_impl.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';
import 'package:spotube/utils/platform.dart';

/// Session-singleton VPN manager. Created once; settings are read live via
/// the [VpnConfig] callback on every acquire, so a settings change applies
/// to the next operation without dropping the live lease count.
///
/// Lifecycle: [Ref.onDispose] tears down polling, lease bookkeeping and the
/// status stream (mirrors `bonsoirProvider` / download-task disposal).
final vpnManagerProvider = Provider<RefCountVpnManager>((ref) {
  final VpnSystemBackend backend =
      kIsLinux ? RealNmcliBackend() : const UnsupportedVpnBackend();

  VpnConfig readConfig() {
    final prefs = ref.read(userPreferencesProvider);
    return VpnConfig(
      connectionUuid: prefs.vpnConnectionUuid,
      deviceName: prefs.vpnDeviceName,
      autoDisconnect: prefs.vpnAutoDisconnect,
      waitTimeout: Duration(seconds: prefs.vpnWaitTimeoutSec),
    );
  }

  final manager = RefCountVpnManager(
    backend: backend,
    readConfig: readConfig,
  );
  // Lets Dio instances without Riverpod access (globalDio) source-pin to
  // the held lease. Null with no leases: adapters delegate unpinned.
  final readPin = manager.readPin;
  VpnPinHolder.reader = readPin;
  ref.onDispose(() {
    if (identical(VpnPinHolder.reader, readPin)) {
      VpnPinHolder.reader = null;
    }
    manager.dispose();
  });
  return manager;
});

/// Whether track downloads must hold a VPN lease for [prefs].
///
/// Pure helper so the download worker and tests share one rule.
/// Disabled modes, and modes with no target selected (neither a system
/// connection nor a tunnel device), return false — zero behavioral change.
bool vpnGatesDownloadsPrefs(UserPreferences prefs) {
  if (prefs.vpnMode == VpnMode.disabled) return false;
  if (!vpnTargetSelected(prefs)) return false;
  return vpnModeGatesDownloads(prefs.vpnMode);
}

/// Whether playback upstream fetches must hold a VPN lease for [prefs].
bool vpnGatesPlaybackPrefs(UserPreferences prefs) {
  if (prefs.vpnMode == VpnMode.disabled) return false;
  if (!vpnTargetSelected(prefs)) return false;
  return vpnModeGatesPlayback(prefs.vpnMode);
}

/// Whether any VPN target is selected: a system connection UUID (managed
/// flow) or a tunnel device name (share-only flow). When both are set the
/// UUID wins — see [VpnConfig].
bool vpnTargetSelected(UserPreferences prefs) =>
    (prefs.vpnConnectionUuid ?? '').isNotEmpty ||
    (prefs.vpnDeviceName ?? '').isNotEmpty;

/// Whether track downloads must hold a VPN lease right now.
bool vpnGatesDownloads(Ref ref) =>
    vpnGatesDownloadsPrefs(ref.read(userPreferencesProvider));

/// Whether playback upstream fetches must hold a VPN lease right now.
bool vpnGatesPlayback(Ref ref) =>
    vpnGatesPlaybackPrefs(ref.read(userPreferencesProvider));
