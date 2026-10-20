import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/radio/radio_playback.dart';

/// Which source currently owns the (single) audio focus. The now-playing and
/// player widgets branch on this to decide whether to render the music
/// `activeTrack` or the radio `activeStation`, without either ever entering
/// the other's data model.
enum PlaybackSource { music, radio }

/// Immutable snapshot of the radio playback controller.
class RadioPlaybackState {
  const RadioPlaybackState({
    this.source = PlaybackSource.music,
    this.activeStation,
    this.playing = false,
    this.buffering = false,
    this.liveTitle,
    this.error,
    this.volume = 1.0,
  });

  final PlaybackSource source;
  final RadioStation? activeStation;
  final bool playing;

  /// Stream is (re)connecting or stalled — surfaced from the backend's
  /// buffering stream, since a live stream has no seekable progress.
  final bool buffering;

  /// Best-effort now-playing title from the stream (ICY), null until wired.
  final String? liveTitle;

  /// Last playback error, kept so the UI can show "station unavailable"
  /// without a crash. Cleared on the next play.
  final Object? error;

  /// Output level as a 0.0–1.0 fraction, independent of the music player's
  /// volume. Re-applied to each fresh backend on play.
  final double volume;

  bool get isRadio => source == PlaybackSource.radio;
  bool get hasActiveStation => activeStation != null;

  RadioPlaybackState copyWith({
    PlaybackSource? source,
    RadioStation? activeStation,
    bool clearStation = false,
    bool? playing,
    bool? buffering,
    String? liveTitle,
    bool clearTitle = false,
    Object? error,
    bool clearError = false,
    double? volume,
  }) {
    return RadioPlaybackState(
      source: source ?? this.source,
      activeStation: clearStation ? null : (activeStation ?? this.activeStation),
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      liveTitle: clearTitle ? null : (liveTitle ?? this.liveTitle),
      error: clearError ? null : (error ?? this.error),
      volume: volume ?? this.volume,
    );
  }

  /// Value equality over every field, as `@freezed` would generate for the
  /// music player state.
  ///
  /// Required because [RadioPlaybackNotifier.updateShouldNotify] compares with
  /// `==`, and because this state is a `Notifier` payload whose emissions fan
  /// out to every station tile. A `copyWith` that changes nothing still yields a
  /// fresh instance, so without this a redundant backend event (a repeated
  /// `playing == true`, a repeated ICY title) reads as a real change.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioPlaybackState &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          activeStation == other.activeStation &&
          playing == other.playing &&
          buffering == other.buffering &&
          liveTitle == other.liveTitle &&
          error == other.error &&
          volume == other.volume;

  @override
  int get hashCode => Object.hash(
        source,
        activeStation,
        playing,
        buffering,
        liveTitle,
        error,
        volume,
      );
}

/// The transport state one station's controls need, derived from the whole
/// [RadioPlaybackState] but keyed by station.
///
/// A record so it compares by value, which is what lets [radioStationStatusProvider]
/// stay quiet when playback moves somewhere unrelated to the station. Every
/// station card, tile and sidebar pin watches this instead of the controller
/// directly: `setVolume` writes state on every slider frame and ICY titles
/// arrive many times per station, and the controller has no equality by default
/// (`Notifier.updateShouldNotify` is `!identical(previous, next)`), so an
/// unwatched controller rebuilds every mounted control per event.
typedef RadioStationStatus = ({
  bool isActive,
  bool isPlaying,
  bool isLoading,
});

/// Per-station transport status. See [RadioStationStatus].
final radioStationStatusProvider =
    Provider.family<RadioStationStatus, String>((ref, favoriteKey) {
  final playback = ref.watch(radioPlaybackControllerProvider);
  final isActive = playback.activeStation?.favoriteKey == favoriteKey;
  final isPlaying = isActive && playback.playing;
  return (
    isActive: isActive,
    isPlaying: isPlaying,
    isLoading: isActive && playback.buffering && !playback.playing,
  );
});
