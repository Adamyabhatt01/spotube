import 'dart:async';
import 'dart:io';

import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

import 'vpn_backend.dart';
import 'vpn_manager.dart';

/// NetworkManager backend shelling out to `nmcli`.
///
/// No new dependencies: `Process.run` with a wall-clock timeout (the same
/// non-cancellable constraint the YouTube engines document — the timeout
/// abandons the wait, it cannot kill the child).
///
/// Never trusts a return code alone: after `bringUp` the manager polls
/// [activeUuids] for the UUID before reporting `connected`.
class RealNmcliBackend implements VpnSystemBackend {
  /// How long one `nmcli` invocation may take before it is abandoned.
  static const Duration commandTimeout = Duration(seconds: 15);

  String? _cachedNmcliPath;

  @override
  bool get isAvailable => kIsLinux;

  /// Absolute path to a usable `nmcli`, or null if there is none.
  ///
  /// [environmentOverride] / [fallbackDirs] exist for tests; production
  /// callers use the defaults.
  Future<String?> resolveNmcliPath({
    Map<String, String>? environmentOverride,
    List<String>? fallbackDirs,
  }) async {
    if (_cachedNmcliPath != null &&
        environmentOverride == null &&
        fallbackDirs == null) {
      return _cachedNmcliPath;
    }
    final env = environmentOverride ?? Platform.environment;
    const binary = 'nmcli';
    final searchedDirs = <String>[
      ...?env['PATH']?.split(':'),
      ...fallbackDirs ??
          const ['/usr/bin', '/usr/local/bin', '/snap/bin', '/opt/bin'],
    ];
    for (final dir in searchedDirs) {
      if (dir.isEmpty) continue;
      final candidate = '$dir/$binary';
      if (await File(candidate).exists()) {
        if (environmentOverride == null && fallbackDirs == null) {
          _cachedNmcliPath = candidate;
        }
        return candidate;
      }
    }
    return null;
  }

  Future<ProcessResult> _runNmcli(List<String> args) async {
    final nmcli = await resolveNmcliPath();
    if (nmcli == null) {
      throw const VpnUnsupportedException(
        'nmcli not found: NetworkManager automation unavailable '
        '(is NetworkManager installed?)',
      );
    }
    try {
      return await Process.run(nmcli, args).timeout(commandTimeout);
    } on TimeoutException catch (e, stack) {
      AppLogger.reportError(e, stack, 'Vpn.nmcli.timeout');
      throw VpnException('nmcli ${args.first} timed out: $e');
    }
  }

  /// Splits an `nmcli -t` line on unescaped `:` and unescapes `\:`.
  /// Names may legally contain colons, so a naive `split(':')` would
  /// corrupt them (and could misalign the UUID column).
  static List<String> splitTerseLine(String line) {
    final fields = <String>[];
    final current = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '\\' && i + 1 < line.length && line[i + 1] == ':') {
        current.write(':');
        i++;
      } else if (char == ':') {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    fields.add(current.toString());
    return fields;
  }

  /// Whether an nmcli connection TYPE row describes a VPN tunnel.
  /// Accepts every known spelling rather than assuming one: the exact
  /// string for a provider's device is confirmed on first live use, and
  /// unknown shapes fall through to the interface-name hint scan instead
  /// of being claimed or rejected here.
  static bool isVpnType(String type) {
    final lower = type.toLowerCase();
    return lower.contains('vpn') ||
        lower.contains('wireguard') ||
        lower == 'tun';
  }

  @override
  Future<Set<String>> activeUuids() async {
    final result = await _runNmcli([
      '-t',
      '-f',
      'UUID,TYPE',
      'connection',
      'show',
      '--active',
    ]);
    if (result.exitCode != 0) {
      throw VpnException(
        'nmcli show --active failed: ${(result.stderr as Object).toString().trim()}',
      );
    }
    final uuids = <String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final fields = splitTerseLine(trimmed);
      if (fields.isEmpty || fields.first.isEmpty) continue;
      final type = fields.length > 1 ? fields[1] : '';
      if (isVpnType(type)) {
        uuids.add(fields.first);
      }
    }
    return uuids;
  }

  @override
  Future<List<VpnConnection>> listConnections() async {
    final result =
        await _runNmcli(['-t', '-f', 'UUID,NAME,TYPE', 'connection', 'show']);
    if (result.exitCode != 0) {
      throw VpnException(
        'nmcli connection show failed: ${(result.stderr as Object).toString().trim()}',
      );
    }
    final connections = <VpnConnection>[];
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final fields = splitTerseLine(trimmed);
      if (fields.length < 3 || fields[0].isEmpty) continue;
      if (isVpnType(fields[2])) {
        connections.add(
          VpnConnection(uuid: fields[0], name: fields[1], type: fields[2]),
        );
      }
    }
    return connections;
  }

  @override
  Future<void> bringUp(String uuid) async {
    final result = await _runNmcli(['connection', 'up', 'uuid', uuid]);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim().toLowerCase();
      if (stderr.contains('not authorized') ||
          stderr.contains('permission denied') ||
          stderr.contains('not permitted')) {
        throw VpnPermissionDeniedException(
          'NetworkManager refused VPN activation: ${(result.stderr as String).trim()}',
        );
      }
      throw VpnException(
        'nmcli connection up failed: ${(result.stderr as String).trim()}',
      );
    }
    // Success here only means the request was accepted; the manager
    // verifies the UUID actually becomes active before proceeding.
  }

  @override
  Future<void> bringDown(String uuid) async {
    final result = await _runNmcli(['connection', 'down', 'uuid', uuid]);
    if (result.exitCode != 0) {
      throw VpnException(
        'nmcli connection down failed: ${(result.stderr as String).trim()}',
      );
    }
  }

  @override
  Future<List<String>> vpnDeviceNames() async {
    // Terse DEVICE:TYPE shape verified against live `nmcli device status`
    // (non-VPN rows). VPN rows carry the same columns; the TYPE filter
    // accepts every known VPN spelling rather than assuming one.
    final result =
        await _runNmcli(['-t', '-f', 'DEVICE,TYPE', 'device', 'status']);
    if (result.exitCode != 0) {
      throw VpnException(
        'nmcli device status failed: ${(result.stderr as Object).toString().trim()}',
      );
    }
    final devices = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final fields = splitTerseLine(trimmed);
      if (fields.length < 2 || fields[0].isEmpty || fields[0] == '--') {
        continue;
      }
      if (isVpnType(fields[1])) {
        devices.add(fields[0]);
      }
    }
    return devices;
  }
}
