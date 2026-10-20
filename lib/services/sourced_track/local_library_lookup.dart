import 'dart:io';

import 'package:spotube/models/metadata/metadata.dart';

/// Finds a track in the user's local library by its metadata.
///
/// The local library is the folder the user pointed Spotube at (Settings →
/// Storage → Local library). A track that is already on disk needs no
/// YouTube lookup, no manifest extraction and no upstream stream: the file
/// is right there. That is the difference between playing a local file and
/// resolving one over the network, and it is why a local match has to be
/// preferred over the remote one.
///
/// The match is on the track's own identity — its title and artists — and
/// not on its Spotify id: a local file has no Spotify id. The comparison
/// is therefore forgiving (case, punctuation and spacing) because the
/// filename and the embedded tags rarely agree exactly with the metadata
/// the track was queued under.
class LocalLibraryMatch {
  /// The local track that was found.
  final SpotubeLocalTrackObject track;

  /// How confident the match is. Higher is better.
  final int score;

  const LocalLibraryMatch(this.track, this.score);
}

/// The local-library lookup.
///
/// Pure and synchronous over a prepared index, so it is testable without a
/// device: the caller supplies the tracks the library scan produced.
class LocalLibraryLookup {
  /// Normalizes a name for comparison: case, punctuation and spacing
  /// differences between a filename and a metadata title are noise.
  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Finds the best local match for [track] among [localTracks].
  ///
  /// Returns null when the library holds no equivalent of the track. A
  /// candidate scores on:
  ///
  ///  - the title matching exactly (the strongest signal — it is what the
  ///    file is named after),
  ///  - the title matching after normalization (case/punctuation only),
  ///  - the title containing the other, for a file named
  ///    "Song (feat. X)" against a track called "Song",
  ///  - every artist of the track appearing in the candidate's artists.
  ///
  /// A candidate that matches none of those does not match at all: the
  /// point is to serve the right file, and a loose guess would play the
  /// wrong song.
  static LocalLibraryMatch? find(
    SpotubeFullTrackObject track,
    Iterable<SpotubeLocalTrackObject> localTracks,
  ) {
    final trackName = _normalize(track.name);
    if (trackName.isEmpty) return null;

    final trackArtists =
        track.artists.map((a) => _normalize(a.name)).where((a) => a.isNotEmpty).toList();

    LocalLibraryMatch? best;

    for (final candidate in localTracks) {
      final candidateName = _normalize(candidate.name);
      if (candidateName.isEmpty) continue;

      var score = 0;
      if (candidate.name.trim() == track.name.trim()) {
        score += 100;
      } else if (candidateName == trackName) {
        score += 60;
      } else if (candidateName.contains(trackName) || trackName.contains(candidateName)) {
        score += 20;
      } else {
        // Not the same title: an artist match alone is not enough. The
        // library holds many files by the same artist.
        continue;
      }

      final candidateArtists =
          candidate.artists.map((a) => _normalize(a.name)).toSet();
      if (trackArtists.isNotEmpty &&
          trackArtists.every((artist) => candidateArtists.contains(artist))) {
        score += 30;
      } else if (trackArtists.isNotEmpty &&
          candidateArtists.any((artist) => trackArtists.contains(artist))) {
        score += 10;
      }

      if (best == null || score > best.score) {
        best = LocalLibraryMatch(candidate, score);
      }
    }

    return best;
  }

  /// Whether [path] names a file the local library would accept.
  ///
  /// Used to confirm a matched file is still there: the index is a scan
  /// result and the file can be gone by the time the track is played.
  static bool fileExists(SpotubeLocalTrackObject track) {
    try {
      return File(track.path).existsSync();
    } catch (_) {
      return false;
    }
  }
}
