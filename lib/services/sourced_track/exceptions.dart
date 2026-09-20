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
