import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/metadata_plugins/plugin_update_available_dialog.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/updater/update_checker.dart';
import 'package:spotube/provider/server/routes/connect.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';

/// How long the app waits before it starts the update checks. Everything that
/// hangs off it is network plus, for a plugin release check, a plugin VM
/// coming online - none of which the first frame or the first playback needs.
const _startupIdleDelay = Duration(seconds: 5);

void useGlobalSubscriptions(WidgetRef ref) {
  final context = useContext();
  final theme = Theme.of(context);
  final connectRoutes = ref.watch(serverConnectRoutesProvider);

  useEffect(() {
    final idleTimer = Timer(_startupIdleDelay, () async {
      if (!context.mounted) return;
      ServiceUtils.checkForUpdates(context, ref);

      try {
        final pluginUpdate =
            await ref.read(metadataPluginUpdateCheckerProvider.future);
        // Only the Settings > Plugins badge reads this one; starting it here
        // keeps it off the launch path instead of putting it in front of the
        // first frame.
        ref.read(audioSourcePluginUpdateCheckerProvider);

        if (pluginUpdate != null) {
          final pluginConfig = await ref.read(metadataPluginsProvider.future);
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (context) => MetadataPluginUpdateAvailableDialog(
                plugin: pluginConfig.defaultMetadataPluginConfig!,
                update: pluginUpdate,
              ),
            );
          }
        }
      } catch (e, stack) {
        // Reported here because nothing awaits this future; it used to be
        // surfaced by the root widget's onError listeners.
        AppLogger.reportError(e, stack);
      }
    });

    StreamSubscription? audioPlayerSubscription;
    bool pausedByStream = false;

    final subscriptions = [
      ConnectionCheckerService.instance.onConnectivityChanged
          .listen((connected) async {
        audioPlayerSubscription?.cancel();

        /// Pausing or resuming based on connectivity to avoid MPV skipping
        /// audio while retrying to connect
        if (audioPlayer.currentIndex >= 0) {
          if (connected && audioPlayer.isPaused && pausedByStream) {
            await audioPlayer.resume();
            pausedByStream = false;
          } else if (!connected && audioPlayer.isPlaying) {
            if ((audioPlayer.bufferedPosition - const Duration(seconds: 1)) <=
                audioPlayer.position) {
              await audioPlayer.pause();
              pausedByStream = true;
            } else {
              // Raw stream on purpose: this watches the remaining buffer, so
              // pausing up to a second late (the shared tick's cadence) would
              // let mpv hit the underrun.
              audioPlayerSubscription =
                  audioPlayer.positionStream.listen((position) async {
                if (ConnectionCheckerService.instance.isConnectedSync) return;

                final bufferedPosition =
                    audioPlayer.bufferedPosition - const Duration(seconds: 1);
                final duration =
                    audioPlayer.duration - const Duration(seconds: 1);

                if (bufferedPosition <= position || position >= duration) {
                  audioPlayer.pause();
                  pausedByStream = true;
                }
              });
            }
          }
        }

        // Show notification for connection related issues
        if (!context.mounted) return;

        showToast(
          context: context,
          location: ToastLocation.bottomCenter,
          builder: (context, overlay) {
            if (connected) {
              return SurfaceCard(
                child: Basic(
                  leading: const Icon(SpotubeIcons.wifi),
                  title: Text(context.l10n.connection_restored),
                ),
              );
            }

            return SurfaceCard(
              fillColor: theme.colorScheme.destructive,
              filled: true,
              child: Basic(
                leading: const Icon(
                  SpotubeIcons.noWifi,
                  color: Colors.white,
                ),
                trailing: Text(
                  context.l10n.you_are_offline,
                  style: const TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        );
      }),
      connectRoutes.connectClientStream.listen((clientOrigin) {
        if (!context.mounted) return;
        showToast(
          context: context,
          location: ToastLocation.topRight,
          builder: (context, overlay) {
            return SurfaceCard(
              fillColor: Colors.yellow[600],
              filled: true,
              child: Basic(
                leading: const Icon(
                  SpotubeIcons.error,
                  color: Colors.black,
                ),
                title: Text(
                  context.l10n.connect_client_alert(clientOrigin),
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            );
          },
        );
      })
    ];

    return () {
      idleTimer.cancel();
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      // The connectivity listener can leave a position subscription alive;
      // it is only cancelled by the next connectivity event, so unmounting
      // while disconnected would keep it running and pausing the player.
      audioPlayerSubscription?.cancel();
    };
  }, []);
}
