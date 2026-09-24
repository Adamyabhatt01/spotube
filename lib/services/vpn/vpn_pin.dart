import 'dart:async';
import 'dart:io';

import 'package:spotube/services/logger/logger.dart';

import 'vpn_backend.dart';
import 'vpn_manager.dart';

/// A resolved tunnel endpoint to pin sockets to: the OS device plus one of
/// its current addresses. Re-resolved per operation — VPN addresses change
/// on reconnect, so a cached pin is never trusted across operations.
typedef VpnEndpoint = ({String ifname, InternetAddress address});

/// Process-wide holder letting Dio instances without Riverpod access (notably
/// the global `globalDio`) read the currently held pin.
///
/// Set exactly once by `vpnManagerProvider` on build and cleared on dispose.
/// Single-threaded Dart makes the nullable-function read race-free. Null
/// reader — or a null return — means "no lease held": adapters delegate
/// unpinned, byte-identical to pre-VPN behavior.
abstract final class VpnPinHolder {
  static InternetAddress? Function()? reader;

  static InternetAddress? current() {
    try {
      return reader?.call();
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'VpnPinHolder.current');
      return null;
    }
  }
}

/// Lists interfaces for [resolveVpnEndpoint]. Production passes
/// `NetworkInterface.list`; tests inject fakes (`NetworkInterface` is an
/// interface class, so it is implementable).
typedef ListInterfaces = Future<List<NetworkInterface>> Function({
  bool includeLoopback,
  bool includeLinkLocal,
  InternetAddressType type,
});

Future<List<NetworkInterface>> _defaultListInterfaces({
  bool includeLoopback = false,
  bool includeLinkLocal = false,
  InternetAddressType type = InternetAddressType.any,
}) =>
    NetworkInterface.list(
      includeLoopback: includeLoopback,
      includeLinkLocal: includeLinkLocal,
      type: type,
    );

/// Name fragments identifying tunnel interfaces. Same precedent as
/// `ConnectionCheckerService.vpnNames`: advisory matching, never a
/// security claim on its own — the lease gate (selected UUID active) is
/// what authorizes, this only locates the device to pin to.
const vpnInterfaceNameHints = [
  'tun',
  'tap',
  'ppp',
  'vpn',
  'wireguard',
  'wg',
  'ipsec',
];

/// Resolves one local address living on a VPN tunnel device.
///
/// Two selection modes:
/// - [deviceName] set: **only that device**, no fallback. An explicitly
///   selected tunnel must never resolve to a different interface — failure
///   is [VpnNoRouteException] naming the device.
/// - [deviceName] null (UUID flow): (1) devices reported by the backend
///   that exist locally with addresses; (2) name-hint scan as fallback
///   when the backend query fails.
///
/// Prefers IPv4 (typical for managed tunnels); ambiguity fails closed
/// with [VpnNoRouteException], never with a guess.
///
/// Throws [VpnNoRouteException] when nothing resolves — callers fail the
/// protected operation closed.
Future<VpnEndpoint> resolveVpnEndpoint({
  required VpnSystemBackend backend,
  String? deviceName,
  ListInterfaces listInterfaces = _defaultListInterfaces,
}) async {
  List<NetworkInterface> interfaces;
  try {
    interfaces = await listInterfaces(includeLoopback: false);
  } catch (e, stack) {
    AppLogger.reportError(e, stack, 'Vpn.resolveVpnEndpoint.interfaces');
    throw VpnNoRouteException('Cannot list network interfaces: $e');
  }

  NetworkInterface? byName(String name) {
    for (final candidate in interfaces) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  // Explicit device selection: this device or failure, nothing else.
  if (deviceName != null && deviceName.isNotEmpty) {
    final address = _firstUsableAddress(byName(deviceName));
    if (address != null) {
      AppLogger.log.i('Vpn pin: $deviceName (${address.address})');
      return (ifname: deviceName, address: address);
    }
    throw VpnNoRouteException(
      'Selected VPN device "$deviceName" has no usable address '
      '(is the tunnel connected?)',
    );
  }

  List<String> devices = const [];
  try {
    devices = await backend.vpnDeviceNames();
  } catch (e, stack) {
    // Backend query failed: fall through to the hint scan rather than
    // failing outright. A failure to resolve there still fails closed.
    AppLogger.reportError(e, stack, 'Vpn.resolveVpnEndpoint.devices');
  }

  // 1. Backend-reported tunnel devices.
  for (final device in devices) {
    final address = _firstUsableAddress(byName(device));
    if (address != null) {
      AppLogger.log.i('Vpn pin: $device (${address.address})');
      return (ifname: device, address: address);
    }
  }

  // 2. Name-hint fallback.
  for (final candidate in interfaces) {
    final name = candidate.name.toLowerCase();
    if (!vpnInterfaceNameHints.any(name.contains)) continue;
    final address = _firstUsableAddress(candidate);
    if (address != null) {
      AppLogger.log.i('Vpn pin (hint): ${candidate.name} (${address.address})');
      return (ifname: candidate.name, address: address);
    }
  }

  throw const VpnNoRouteException(
    'No VPN interface address found to pin connections to',
  );
}

/// First IPv4 address, else first IPv6, else null. Link-local excluded by
/// the listing flags at the call site.
InternetAddress? _firstUsableAddress(NetworkInterface? interface) {
  if (interface == null) return null;
  for (final address in interface.addresses) {
    if (address.type == InternetAddressType.IPv4) return address;
  }
  for (final address in interface.addresses) {
    if (address.type == InternetAddressType.IPv6) return address;
  }
  return null;
}
