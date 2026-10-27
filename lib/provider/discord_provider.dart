import 'dart:async';

import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

/// A position step larger than one whole-second tick plus slack, i.e. a
/// discontinuity (seek) rather than normal playback advancement.
const presenceSeekThreshold = Duration(milliseconds: 1500);

/// How often the library's `autoRetry` wakes to re-attempt a Discord
/// connection, and how many attempts Spotube tolerates before giving up.
const discordRetryDelay = Duration(seconds: 5);
const discordMaxConnectAttempts = 12;

class DiscordNotifier extends AsyncNotifier<void> {
  AudioPlayerPort get player => ref.read(audioPlayerPortProvider);

  @override
  FutureOr<void> build() async {
    if (!kIsDesktop) return;

    final enabled = ref.watch(
        userPreferencesProvider.select((s) => s.discordPresence && kIsDesktop));

    var lastPosition = player.position;

    final subscriptions = [
      FlutterDiscordRPC.instance.isConnectedStream.listen((connected) async {
        try {
          final playback = ref.read(audioPlayerProvider);
          if (connected && playback.activeTrack != null) {
            await updatePresence(playback.activeTrack!);
          }
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
      player.playerStateStream.listen((state) async {
        try {
          final playback = ref.read(audioPlayerProvider);
          if (playback.activeTrack == null) return;

          await updatePresence(ref.read(audioPlayerProvider).activeTrack!);
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      }),
      // Runs on the shared ~1 Hz tick stream rather than the raw ~5 Hz one.
      // The point is discontinuity detection, not periodic refresh: presence
      // is re-published when the position moved by more than a tick plus
      // slack (a seek), which is the only thing the previous ±500 ms test on
      // consecutive raw events ever matched, since a raw step is ~200 ms.
      // Track changes and play/pause are covered by the two listeners above.
      player.positionTickStream.listen((position) async {
        try {
          final playback = ref.read(audioPlayerProvider);
          if (playback.activeTrack != null) {
            final diff = position.inMilliseconds - lastPosition.inMilliseconds;
            if (diff > presenceSeekThreshold.inMilliseconds ||
                diff < -presenceSeekThreshold.inMilliseconds) {
              await updatePresence(ref.read(audioPlayerProvider).activeTrack!);
            }
          }
          lastPosition = position;
        } catch (e, stack) {
          AppLogger.reportError(e, stack);
        }
      })
    ];

    ref.onDispose(() async {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      await clear();
      await close();
      await FlutterDiscordRPC.instance.dispose();
    });

    if (!enabled && FlutterDiscordRPC.instance.isConnected) {
      await clear();
      await close();
    } else if (enabled) {
      await _connectWithCappedRetry();
    }
  }

  /// `flutter_discord_rpc`'s `autoRetry` is a `Timer.periodic` that only
  /// ends on success: with Discord closed for the session it re-runs the
  /// native connect every 5 seconds forever, burning a timer and a local
  /// socket attempt indefinitely. This wrapper stops it after
  /// [discordMaxConnectAttempts] by calling `disconnect()` (which cancels
  /// the library's timer). A later toggle of the preference, or a
  /// presence-bearing action after Discord reopens, can still reconnect.
  Future<void> _connectWithCappedRetry() async {
    var attempts = 0;
    var connected = FlutterDiscordRPC.instance.isConnected;
    late final StreamSubscription<bool> sub;
    sub = FlutterDiscordRPC.instance.isConnectedStream.listen((isConnected) {
      connected = isConnected;
    });
    try {
      await FlutterDiscordRPC.instance.connect(
        autoRetry: true,
        retryDelay: discordRetryDelay,
      );
      while (!connected && attempts < discordMaxConnectAttempts) {
        await Future.delayed(discordRetryDelay);
        if (connected) break;
        attempts++;
      }
      if (!connected) {
        await close();
        AppLogger.log.d(
          'Discord presence paused after $attempts retries',
        );
      }
    } finally {
      await sub.cancel();
    }
  }

  Future<void> updatePresence(SpotubeTrackObject track) async {
    if (!kIsDesktop) return;
    if (FlutterDiscordRPC.instance.isConnected == false) return;
    final artistNames = track.artists.asString();
    final isPlaying = player.isPlaying;
    final position = player.position;

    await FlutterDiscordRPC.instance.setActivity(
      activity: RPCActivity(
        details: track.name,
        state: artistNames,
        assets: RPCAssets(
          largeImage:
              track.album.images.firstOrNull?.url ?? "spotube-logo-foreground",
          largeText: track.album.name,
          smallImage: "spotube-logo-foreground",
          smallText: "Spotube",
        ),
        buttons: [
          RPCButton(
            label: "Listen on Spotube",
            url: track.externalUri,
          ),
        ],
        timestamps: RPCTimestamps(
          start: isPlaying
              ? DateTime.now().millisecondsSinceEpoch - position.inMilliseconds
              : null,
        ),
        activityType: ActivityType.listening,
      ),
    );
  }

  Future<void> clear() async {
    if (!kIsDesktop) return;
    await FlutterDiscordRPC.instance.clearActivity();
  }

  Future<void> close() async {
    if (!kIsDesktop) return;
    await FlutterDiscordRPC.instance.disconnect();
  }
}

final discordProvider =
    AsyncNotifierProvider<DiscordNotifier, void>(() => DiscordNotifier());
