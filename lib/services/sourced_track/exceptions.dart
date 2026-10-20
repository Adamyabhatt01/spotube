import 'package:spotube/models/metadata/metadata.dart';

class TrackNotFoundError extends Error {
  final SpotubeTrackObject track;

  TrackNotFoundError(this.track);

  @override
  String toString() {
    return '[TrackNotFoundError] ${track.name} - ${track.artists.join(", ")}';
  }
}

/// Thrown when a track has no usable stream URL: every candidate URL was
/// rejected by validation (e.g. 403 from the upstream CDN) across all
/// manifest re-fetches. Surfacing this instead of returning unvalidated
/// URLs is what stops playback from looping on a dead manifest forever.
class NoValidStreamError extends Error {
  final String message;

  NoValidStreamError(this.message);

  @override
  String toString() {
    return '[NoValidStreamError] $message';
  }
}

/// Thrown when the yt-dlp engine is asked to do work but no usable binary
/// is reachable (no stored custom path, nothing on PATH or the well-known
/// install dirs). A missing binary is blockage, never a miss: it must not
/// become a cached "not found", and it reads in the log as itself instead
/// of the package's null binary-location crash.
class YtDlpNotInstalledError extends Error {
  @override
  String toString() => '[YtDlpNotInstalledError] yt-dlp binary not found';
}
