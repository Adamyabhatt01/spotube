import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart' show Badge;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/connect/connect_device.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';

/// Width of the labelled footer row: the sidebar's width minus its own inset,
/// never narrower than the labels need. Pure so the floor and the theme width
/// can be checked without the router and profile providers this widget reads.
double sidebarFooterWidth(BuildContext context) {
  final scaling = Theme.of(context).scaling;
  return math.max(
    120 * scaling,
    context.sidebarWidth - 20 * scaling,
  );
}

class SidebarFooter extends HookConsumerWidget {
  /// Forces the icon-only form, for a sidebar whose navigation collapsed into a
  /// rail. The rail is narrower than the `md` breakpoint that this widget would
  /// otherwise use to decide, so its owner says which form the footer wants.
  final bool compact;

  const SidebarFooter({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, ref) {
    final theme = Theme.of(context);
    final router = AutoRouter.of(context, watch: true);
    final mediaQuery = MediaQuery.of(context);
    final downloadCount = ref.watch(
      downloadManagerProvider.select(
        (tasks) => tasks
            .where((e) =>
                e.status == DownloadStatus.downloading ||
                e.status == DownloadStatus.queued)
            .length,
      ),
    );
    final userSnapshot = ref.watch(metadataPluginUserProvider);
    final data = userSnapshot.asData?.value;

    final avatarImg = (data?.images).asUrlString(
      index: (data?.images.length ?? 1) - 1,
      placeholder: ImagePlaceholder.artist,
    );

    final authenticated = ref.watch(metadataPluginAuthenticatedProvider);

    if (compact || mediaQuery.mdAndDown) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          IconButton(
            variance: router.topRoute.name == SettingsEqualizerRoute.name
                ? ButtonVariance.secondary
                : ButtonVariance.ghost,
            icon: const Icon(SpotubeIcons.equalizer),
            onPressed: () => context.navigateTo(const SettingsEqualizerRoute()),
          ),
          Badge(
            isLabelVisible: downloadCount > 0,
            label: Text(downloadCount.toString()),
            child: IconButton(
              variance: router.topRoute.name == UserDownloadsRoute.name
                  ? ButtonVariance.secondary
                  : ButtonVariance.ghost,
              icon: const Icon(SpotubeIcons.download),
              onPressed: () => context.navigateTo(const UserDownloadsRoute()),
            ),
          ),
          const ConnectDeviceButton.sidebar(compact: true),
          IconButton(
            variance: ButtonVariance.ghost,
            icon: const Icon(SpotubeIcons.settings),
            onPressed: () => context.navigateTo(const SettingsRoute()),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 12),
      // Follows the sidebar's width (theme-overridable) minus this row's own
      // inset, with a floor so the labels never clip mid-word.
      width: sidebarFooterWidth(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          SizedBox(
            width: double.infinity,
            child: Button(
              style: router.topRoute.name == SettingsEqualizerRoute.name
                  ? ButtonVariance.secondary
                  : ButtonVariance.outline,
              onPressed: () {
                context.navigateTo(const SettingsEqualizerRoute());
              },
              leading: const Icon(SpotubeIcons.equalizer),
              child: Text(context.l10n.equalizer),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: Button(
              style: router.topRoute.name == UserDownloadsRoute.name
                  ? ButtonVariance.secondary
                  : ButtonVariance.outline,
              onPressed: () {
                context.navigateTo(const UserDownloadsRoute());
              },
              leading: const Icon(SpotubeIcons.download),
              trailing: downloadCount > 0
                  ? PrimaryBadge(
                      child: Text(downloadCount.toString()),
                    )
                  : null,
              child: Text(context.l10n.downloads),
            ),
          ),
          const ConnectDeviceButton.sidebar(),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (authenticated.asData?.value == true && data == null)
                const CircularProgressIndicator()
              else if (data != null)
                Flexible(
                  child: GestureDetector(
                    onTap: () {
                      context.navigateTo(const ProfileRoute());
                    },
                    child: Row(
                      children: [
                        Avatar(
                          initials: Avatar.getInitials(data.name),
                          provider: UniversalImage.imageProvider(
                            avatarImg,
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            data.name,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: theme.typography.normal
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              IconButton(
                variance: ButtonVariance.ghost,
                icon: const Icon(SpotubeIcons.settings),
                onPressed: () {
                  context.navigateTo(const SettingsRoute());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
