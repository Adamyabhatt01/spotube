import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/discord_provider.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/core/scrobble.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/skip_segments/skip_segments.dart';
import 'package:spotube/provider/scrobbler/scrobbler.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_services/audio_services.dart';
import 'package:spotube/services/logger/logger.dart';

class AudioPlayerStreamListeners {
  final Ref ref;

  /// Created asynchronously: playlist events arriving before it resolves
  /// are buffered in [_pendingNotification] and flushed on readiness
  /// instead of being lost to a LateInitializationError (the previous
  /// `late final` dropped early notifications into a logged error).
  AudioServices? notificationService;
  final _pendingNotification = PendingNotificationBuffer();

  /// Segments cached per track: the provider future is awaited only when
  /// [shouldRefreshSegments] reports a track change, not on every
  /// ~200ms position tick.
  String? _segmentsForTrackId;
  dynamic _cachedSegments;

  /// Guards the sponsor seek loop: ticks arriving mid-seek skip instead
  /// of piling up concurrent seeks.
  bool _seekingSponsorSkip = false;

  AudioPlayerStreamListeners(this.ref) {
    AudioServices.create(ref, ref.read(audioPlayerProvider.notifier)).then(
      (value) {
        notificationService = value;
        final pending = _pendingNotification.take();
        if (pending != null) {
          try {
            value.addTrack(pending);
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
          }
        }
      },
    );

    final subscriptions = [
      subscribeToPlaylist(),
      subscribeToSkipSponsor(),
      subscribeToScrobbleChanged(),
      subscribeToPosition(),
      subscribeToPlayerError(),
    ];

    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
  }

  ScrobblerNotifier get scrobbler => ref.read(scrobblerProvider.notifier);
  DiscordNotifier get discord => ref.read(discordProvider.notifier);
  AudioPlayerState get audioPlayerState => ref.read(audioPlayerProvider);
  PlaybackHistoryActions get history =>
      ref.read(playbackHistoryActionsProvider);

  StreamSubscription subscribeToPlaylist() {
    return audioPlayer.playlistStream.listen((mpvPlaylist) {
      try {
        if (audioPlayerState.activeTrack == null) return;
        final service = notificationService;
        if (service == null) {
          // Service not ready yet: buffer the latest track for flush.
          _pendingNotification.stage(audioPlayerState.activeTrack!);
          return;
        }
        service.addTrack(audioPlayerState.activeTrack!);
        discord.updatePresence(audioPlayerState.activeTrack!);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  /// Pure per-tick sponsor decision: segments are (re)fetched only when
  /// the active track changed since the last fetch. Unit-tested; the
  /// listener below applies it.
  bool shouldRefreshSegments(String? activeTrackId) {
    return shouldRefreshSponsorSegments(
      activeTrackId: activeTrackId,
      cachedTrackId: _segmentsForTrackId,
    );
  }

  void _noteSegmentsRefreshed(String? activeTrackId, dynamic segments) {
    _segmentsForTrackId = activeTrackId;
    _cachedSegments = segments;
  }

  StreamSubscription subscribeToSkipSponsor() {
    return audioPlayer.positionStream.listen((position) async {
      try {
        if (_seekingSponsorSkip) return;
        final activeTrackId = audioPlayerState.activeTrack?.id;
        final currentSegments = shouldRefreshSegments(activeTrackId)
            ? await ref.read(segmentProvider.future).then((segments) {
                _noteSegmentsRefreshed(activeTrackId, segments);
                return segments;
              })
            : _cachedSegments;

        if (currentSegments?.segments.isNotEmpty != true ||
            position < const Duration(seconds: 3)) {
          return;
        }

        _seekingSponsorSkip = true;
        try {
          for (final segment in currentSegments!.segments) {
            final seconds = position.inSeconds;

            if (seconds < segment.start || seconds >= segment.end) continue;

            await audioPlayer.seek(Duration(seconds: segment.end + 1));
          }
        } finally {
          _seekingSponsorSkip = false;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToScrobbleChanged() {
    String? lastScrobbled;
    return audioPlayer.positionStream.listen((position) async {
      try {
        final uid = audioPlayerState.activeTrack is SpotubeLocalTrackObject
            ? (audioPlayerState.activeTrack as SpotubeLocalTrackObject).path
            : audioPlayerState.activeTrack?.id;

        /// According to Listenbrainz and Last.fm, a scrobble should be sent
        /// after 4 minutes of listening or 50% of the track duration,
        /// whichever is less.
        final minimumListenTime = min(audioPlayer.duration.inSeconds ~/ 2, 240);

        if (audioPlayerState.activeTrack == null ||
            lastScrobbled == uid ||
            position.inSeconds < minimumListenTime ||
            audioPlayer.duration == Duration.zero ||
            position == Duration.zero) {
          return;
        }

        scrobbler.scrobble(audioPlayerState.activeTrack!);
        ref
            .read(metadataPluginScrobbleProvider.notifier)
            .scrobble(audioPlayerState.activeTrack!);
        lastScrobbled = uid;

        /// The [Track] from Playlist.getTracks doesn't contain artist images
        /// so we need to fetch them from the API
        var activeTrack = audioPlayerState.activeTrack!;
        if (activeTrack.artists.any((a) => a.images == null)) {
          final metadataPlugin = await ref.read(metadataPluginProvider.future);
          final artists = await Future.wait(
            activeTrack.artists
                .map((artist) => metadataPlugin!.artist.getArtist(artist.id)),
          );
          activeTrack = activeTrack.copyWith(
            artists: artists
                .map((e) => SpotubeSimpleArtistObject.fromJson(e.toJson()))
                .toList(),
          );
        }

        await history.addTrack(activeTrack);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPosition() {
    String lastTrack = ""; // used to prevent multiple calls to the same track
    return audioPlayer.positionStream.listen((event) async {
      final percentProgress =
          (event.inSeconds / max(audioPlayer.duration.inSeconds, 1)) * 100;
      try {
        if (percentProgress < 80 ||
            audioPlayerState.currentIndex == -1 ||
            audioPlayerState.currentIndex ==
                audioPlayerState.tracks.length - 1) {
          return;
        }
        final nextTrack = audioPlayerState.tracks
            .elementAtOrNull(audioPlayerState.currentIndex + 1);

        if (nextTrack == null ||
            lastTrack == nextTrack.id ||
            nextTrack is SpotubeLocalTrackObject) {
          return;
        }

        try {
          await ref.read(
            sourcedTrackProvider(nextTrack as SpotubeFullTrackObject).future,
          );
        } finally {
          lastTrack = nextTrack.id;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPlayerError() {
    return audioPlayer.errorStream.listen((event) {});
  }
}

final audioPlayerStreamListenersProvider =
    Provider<AudioPlayerStreamListeners>(AudioPlayerStreamListeners.new);

/// Pure per-tick sponsor-segment decision: (re)fetch only when the active
/// track differs from the track whose segments are cached (including the
/// initial null state). Keeps the ~200ms position ticks from awaiting the
/// segment provider future every tick.
bool shouldRefreshSponsorSegments({
  required String? activeTrackId,
  required String? cachedTrackId,
}) {
  return activeTrackId != cachedTrackId;
}

/// Buffers at most the latest track until the notification service is
/// ready, then flushes exactly once. Replaces the previous `late final`
/// service field, which dropped early playlist events into a logged
/// LateInitializationError instead of delivering them.
class PendingNotificationBuffer {
  SpotubeTrackObject? _pending;

  bool get hasPending => _pending != null;

  void stage(SpotubeTrackObject track) => _pending = track;

  /// Returns the buffered track (if any), clearing the buffer. Later
  /// stages overwrite earlier ones: only the latest track matters.
  SpotubeTrackObject? take() {
    final track = _pending;
    _pending = null;
    return track;
  }
}
