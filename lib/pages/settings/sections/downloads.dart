import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show ListTile;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/adaptive/adaptive_select_tile.dart';
import 'package:spotube/modules/settings/downloads/vpn_connection_dialog.dart';
import 'package:spotube/modules/settings/section_card_with_heading.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/vpn/vpn_manager.dart';
import 'package:spotube/utils/platform.dart';

class SettingsDownloadsSection extends HookConsumerWidget {
  const SettingsDownloadsSection({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final preferencesNotifier = ref.watch(userPreferencesProvider.notifier);
    // Narrow slice: a write to any other preference must not rebuild
    // this whole section (the row notifier emits on every write).
    final preferences = ref.watch(userPreferencesProvider.select(
      (p) => (
        downloadLocation: p.downloadLocation,
        vpnMode: p.vpnMode,
        vpnConnectionUuid: p.vpnConnectionUuid,
        vpnDeviceName: p.vpnDeviceName,
        vpnAutoDisconnect: p.vpnAutoDisconnect,
      ),
    ));

    final vpnManager = ref.watch(vpnManagerProvider);
    // System connections need a backend; share-only tunnels work wherever
    // Dart lists interfaces (see RefCountVpnManager.supportsDeviceTargets).
    final vpnUsable =
        vpnManager.isSupported || vpnManager.supportsDeviceTargets;

    final pickDownloadLocation = useCallback(() async {
      if (kIsMobile || kIsMacOS) {
        final dirStr = await FilePicker.platform.getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        preferencesNotifier.setDownloadLocation(dirStr);
      } else {
        String? dirStr = await getDirectoryPath(
          initialDirectory: preferences.downloadLocation,
        );
        if (dirStr == null) return;
        preferencesNotifier.setDownloadLocation(dirStr);
      }
    }, [preferences.downloadLocation]);

    String vpnModeLabel(VpnMode mode) {
      return switch (mode) {
        VpnMode.disabled => context.l10n.vpn_disabled,
        VpnMode.downloadsOnly => context.l10n.vpn_downloads_only,
        VpnMode.playbackOnly => context.l10n.vpn_playback_only,
        VpnMode.downloadsAndPlayback => context.l10n.vpn_downloads_and_playback,
      };
    }

    final vpnEnabled = preferences.vpnMode != VpnMode.disabled;

    return SectionCardWithHeading(
      heading: context.l10n.downloads,
      children: [
        ListTile(
          leading: const Icon(SpotubeIcons.download),
          title: Text(context.l10n.download_location),
          subtitle: Text(preferences.downloadLocation),
          trailing: IconButton.secondary(
            onPressed: pickDownloadLocation,
            icon: const Icon(SpotubeIcons.folder),
          ),
          onTap: pickDownloadLocation,
        ),
        AdaptiveSelectTile<VpnMode>(
          secondary: const Icon(SpotubeIcons.wifi),
          title: Text(context.l10n.automatic_vpn),
          subtitle: vpnUsable
              ? Text(context.l10n.automatic_vpn_description)
              : Text(context.l10n.vpn_unsupported),
          value: preferences.vpnMode,
          onChanged: !vpnUsable
              ? null
              : (value) {
                  if (value != null) {
                    preferencesNotifier.setVpnMode(value);
                  }
                },
          options: VpnMode.values
              .map((mode) => SelectItemButton(
                    value: mode,
                    child: Text(vpnModeLabel(mode)),
                  ))
              .toList(),
        ),
        if (vpnEnabled && vpnUsable)
          ListTile(
            leading: const Icon(SpotubeIcons.wifi),
            title: Text(context.l10n.vpn_connection),
            subtitle: Text(
              preferences.vpnDeviceName == null
                  ? (preferences.vpnConnectionUuid == null
                      ? context.l10n.vpn_no_connection_selected
                      : context.l10n.vpn_selected_system)
                  : context.l10n.vpn_selected_tunnel(
                      preferences.vpnDeviceName!,
                    ),
            ),
            trailing: const Icon(SpotubeIcons.angleRight),
            onTap: () {
              showDialog(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.5),
                builder: (context) => const VpnConnectionDialog(),
              );
            },
          ),
        if (vpnEnabled && vpnUsable)
          ListTile(
            leading: const Icon(SpotubeIcons.wifi),
            title: Text(context.l10n.vpn_auto_disconnect),
            subtitle: Text(context.l10n.vpn_auto_disconnect_description),
            trailing: Switch(
              value: preferences.vpnAutoDisconnect,
              onChanged: preferencesNotifier.setVpnAutoDisconnect,
            ),
          ),
      ],
    );
  }
}
