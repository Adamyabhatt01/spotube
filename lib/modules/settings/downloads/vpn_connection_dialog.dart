import 'dart:io';

import 'package:flutter/material.dart' hide AlertDialog, CircularProgressIndicator;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/services/vpn/vpn_manager_impl.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';

/// Lets the user pick the VPN target Spotube may use for protected
/// operations: either one of their system VPN connections (which Spotube
/// may activate/deactivate) or a live tunnel device from their VPN app
/// (shared as-is — never connected or disconnected by Spotube).
///
/// Lists identity fields only — authentication stays with the operating
/// system or the VPN app, and Spotube never handles credentials.
///
/// The tunnel list only offers interfaces that look like tunnels
/// (backend-verified VPN devices or name-hint matches), so a normal
/// interface such as Wi-Fi or Ethernet can never be selected here:
/// pinning one of those would protect nothing.
class VpnConnectionDialog extends ConsumerStatefulWidget {
  const VpnConnectionDialog({super.key});

  @override
  ConsumerState<VpnConnectionDialog> createState() =>
      _VpnConnectionDialogState();
}

class _TunnelRow {
  _TunnelRow(this.name, this.addresses, this.verified);

  final String name;
  final String addresses;
  final bool verified;
}

class _VpnConnectionDialogState extends ConsumerState<VpnConnectionDialog> {
  List<VpnConnection>? _connections;
  Object? _connectionsError;
  List<_TunnelRow>? _tunnels;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = ref.read(vpnManagerProvider);
    List<VpnConnection>? connections;
    Object? connectionsError;
    if (manager.isSupported) {
      try {
        connections = await manager.listConnections();
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'VpnConnectionDialog.connections');
        connectionsError = e;
      }
    }
    List<_TunnelRow> tunnels = const [];
    try {
      tunnels = await _loadTunnels(manager);
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'VpnConnectionDialog.tunnels');
    }
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _connectionsError = connectionsError;
      _tunnels = tunnels;
      _loading = false;
    });
  }

  /// Live tunnel interfaces eligible for share-only selection: interfaces
  /// the backend reports as VPN devices, plus name-hint matches for tunnels
  /// from provider apps outside NetworkManager. Anything else (Wi-Fi,
  /// Ethernet, loopback) is excluded so it cannot be picked.
  Future<List<_TunnelRow>> _loadTunnels(RefCountVpnManager manager) async {
    Set<String> verified = const {};
    try {
      verified = (await manager.vpnDeviceNames()).toSet();
    } catch (e, stack) {
      // No backend (or query failed): hint matching still applies below.
      AppLogger.reportError(e, stack, 'VpnConnectionDialog.devices');
    }
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.any,
    );
    final rows = <_TunnelRow>[];
    for (final interface in interfaces) {
      final name = interface.name;
      final isVerified = verified.contains(name);
      final isHinted = vpnInterfaceNameHints
          .any((h) => name.toLowerCase().contains(h));
      if (!isVerified && !isHinted) continue;
      final addresses =
          interface.addresses.map((a) => a.address).join(', ');
      if (addresses.isEmpty) continue;
      rows.add(_TunnelRow(name, addresses, isVerified));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(userPreferencesProvider.select(
      (p) => (
        uuid: p.vpnConnectionUuid,
        device: p.vpnDeviceName,
      ),
    ));
    final notifier = ref.watch(userPreferencesProvider.notifier);
    final manager = ref.watch(vpnManagerProvider);

    List<Widget> section(String title, String? description, List<Widget> rows) {
      return [
        Text(title).h4(),
        if (description != null) Text(description),
        ...rows,
      ];
    }

    Widget radioRow({
      required bool selected,
      required String title,
      String? subtitle,
      required void Function() onTap,
    }) {
      return ListTile(
        leading: selected
            ? const Icon(SpotubeIcons.radioChecked)
            : const Icon(SpotubeIcons.radioUnchecked),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: () {
          onTap();
          Navigator.of(context).pop();
        },
      );
    }

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      final rows = <Widget>[
        radioRow(
          selected: selection.uuid == null && selection.device == null,
          title: context.l10n.vpn_clear_selection,
          onTap: () {
            notifier.setVpnConnectionUuid(null);
            notifier.setVpnDeviceName(null);
          },
        ),
      ];
      if (manager.isSupported) {
        rows.addAll(section(
          context.l10n.vpn_system_connections,
          context.l10n.vpn_system_connections_description,
          [
            if (_connectionsError != null)
              Text(_connectionsError.toString())
            else if (_connections == null || _connections!.isEmpty)
              Text(context.l10n.vpn_no_connections_found)
            else
              for (final connection in _connections!)
                radioRow(
                  selected: connection.uuid == selection.uuid,
                  title: connection.name,
                  subtitle: connection.type,
                  onTap: () {
                    notifier.setVpnConnectionUuid(connection.uuid);
                    notifier.setVpnDeviceName(null);
                  },
                ),
          ],
        ));
      }
      rows.addAll(section(
        context.l10n.vpn_active_tunnels,
        context.l10n.vpn_active_tunnels_description,
        [
          if (_tunnels == null || _tunnels!.isEmpty)
            Text(context.l10n.vpn_no_tunnels_found)
          else
            for (final tunnel in _tunnels!)
              radioRow(
                selected: tunnel.name == selection.device,
                title: tunnel.name,
                subtitle: tunnel.addresses,
                onTap: () {
                  notifier.setVpnDeviceName(tunnel.name);
                  notifier.setVpnConnectionUuid(null);
                },
              ),
        ],
      ));
      content = Flexible(
        child: ListView(
          shrinkWrap: true,
          children: rows,
        ),
      );
    }

    return AlertDialog(
      title: Text(context.l10n.vpn_connection),
      content: content,
    );
  }
}
