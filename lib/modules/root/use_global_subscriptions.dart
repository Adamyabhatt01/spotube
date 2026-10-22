import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/configurators/use_window_listener.dart';
import 'package:spotube/modules/metadata_plugins/plugin_update_available_dialog.dart';
import 'package:spotube/provider/metadata_plugin/library/library_refresh.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/updater/update_checker.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/server/routes/connect.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/service_utils.dart';

/// How long the app waits before it starts the update checks. Everything that
/// hangs off it is network plus, for a plugin release check, a plugin VM
/// coming online - none of which the first frame or the first playback needs.
const _startupIdleDelay = Duration(seconds: 5);

/// How many times [useGlobalSubscriptions] pushes the burst back when it fires
/// during active playback, before running it regardless. Bounds the deferral so
/// a long-listening session still gets its once-a-day check.
const _maxIdleDeferrals = 3;

/// How often the saved library is re-read while the app is in the foreground.
///
/// Long enough to be cheap, short enough that a playlist created on a phone
/// shows up on a desktop that was left open. The library is small — a user
/// has tens of playlists, not thousands — and the re-read is one request for
/// anyone whose library fits on a page.
const _libraryRefreshHeartbeat = Duration(minutes: 10);

void useGlobalSubscriptions(WidgetRef ref) {
  final context = useContext();
  final theme = Theme.of(context);
  final connectRoutes = ref.watch(serverConnectRoutesProvider);

  // The saved library is read once per app session, so a device that stays
  // open never learns about a playlist created on another one. This is the
  // single owner of every "the library may have changed" trigger.
  final libraryRefresher = ref.read(savedLibraryRefreshProvider);

  // Window focus is the desktop equivalent of the app coming back to the
  // foreground. The callback is stabilized so the listener is registered
  // once instead of on every rebuild.
  final onWindowFocus = useCallback(() {
    unawaited(libraryRefresher.refreshAll());
  }, [libraryRefresher]);

  useWindowListener(onWindowFocus: onWindowFocus);

  useEffect(() {
    Timer? idleTimer;
    var deferrals = 0;

    Future<void> runUpdateChecks() async {
      if (!context.mounted) return;
      // Don't run the network + plugin-VM burst while audio is playing: the
      // first playback must not contend with it. Reschedule to the next idle
      // beat, capped so the once-a-day check still eventually lands.
      if (audioPlayer.isPlaying && deferrals < _maxIdleDeferrals) {
        deferrals++;
        idleTimer = Timer(_startupIdleDelay, runUpdateChecks);
        return;
      }
      // One burst a day, not one per launch: skip all three checks when the
      // interval has not elapsed. The stamp records the attempt (not success)
      // so an offline week does not queue a burst per launch either.
      final lastCheck = ref.read(
        userPreferencesProvider.select((p) => p.lastUpdateCheckMs),
      );
      if (!isUpdateCheckDue(lastCheck, DateTime.now())) return;
      ref
          .read(userPreferencesProvider.notifier)
          .setLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);

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
    }

    idleTimer = Timer(_startupIdleDelay, runUpdateChecks);

    // Background playlist maintenance starts after the first frame burst, and
    // never blocks it: network reads and downloads are queued from here.
    final autoDownloadTimer = Timer(_startupIdleDelay, () {
      unawaited(
        ref
            .read(playlistMirrorServiceProvider)
            .syncAutoDownloadPlaylists(force: true),
      );
    });

    // Coming back to the app is the moment a user expects to see what their
    // other devices did while they were away.
    final lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(libraryRefresher.refreshAll()),
    );

    // A device that was closed while another one changed the account has to
    // re-read it when it comes back: the saved lists are otherwise read once
    // per session, so a playlist created in the meantime would never arrive.
    final librarySyncTimer = Timer(_startupIdleDelay, () {
      unawaited(libraryRefresher.refreshAll());
    });

    // The heartbeat covers the case no event covers: the app was left open
    // and in the foreground the whole time, on a device that made a change
    // somewhere else.
    final libraryHeartbeat = Timer.periodic(
      _libraryRefreshHeartbeat,
      (_) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) {
          return;
        }
        unawaited(libraryRefresher.refreshAll());
      },
    );

    StreamSubscription? audioPlayerSubscription;
    bool pausedByStream = false;
    var wasConnected = ConnectionCheckerService.instance.isConnectedSync;

    // A single failed probe is not an offline episode. The banner is a
    // full-width destructive surface sliding over the bottom of the screen,
    // so drawing it for one DNS hiccup read as the app flashing every few
    // minutes. Wait for a fresh confirmation probe before announcing, and
    // only announce "restored" when the banner actually appeared.
    const connectivityConfirmDelay = Duration(seconds: 4);
    Timer? connectivityToastTimer;
    var offlineToastShown = false;

    final subscriptions = [
      ConnectionCheckerService.instance.onConnectivityChanged
          .listen((connected) async {
        final restored = connected && !wasConnected;
        wasConnected = connected;
        if (restored) {
          unawaited(
            ref
                .read(playlistMirrorServiceProvider)
                .syncAutoDownloadPlaylists(retryIfBusy: true),
          );
          // The network was down, so the library could not be read while it
          // was. Whatever another device did in the meantime is only
          // visible now.
          unawaited(libraryRefresher.refreshAll());
        }

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

        if (!context.mounted) return;

        if (connected) {
          connectivityToastTimer?.cancel();
          connectivityToastTimer = null;
          // Nothing was announced for this episode: this was a flap, so
          // there is no recovery to tell the user about either.
          if (!offlineToastShown) return;
          offlineToastShown = false;

          showToast(
            context: context,
            location: ToastLocation.bottomCenter,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Basic(
                  leading: const Icon(SpotubeIcons.wifi),
                  title: Text(context.l10n.connection_restored),
                ),
              );
            },
          );
          return;
        }

        // One banner per offline episode: repeated probes that agree must not
        // restart the wait.
        if (offlineToastShown || connectivityToastTimer != null) return;

        connectivityToastTimer = Timer(connectivityConfirmDelay, () async {
          connectivityToastTimer = null;
          // Confirm with a fresh probe instead of trusting the one failure
          // that started this wait. If the network is back, the listener
          // clears the episode without the banner ever being drawn.
          final online = await ConnectionCheckerService.instance.isConnected;
          if (!context.mounted || online) return;

          offlineToastShown = true;
          showToast(
            context: context,
            location: ToastLocation.bottomCenter,
            builder: (context, overlay) {
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
        });
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
      idleTimer?.cancel();
      autoDownloadTimer.cancel();
      connectivityToastTimer?.cancel();
      librarySyncTimer.cancel();
      libraryHeartbeat.cancel();
      lifecycleListener.dispose();
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
