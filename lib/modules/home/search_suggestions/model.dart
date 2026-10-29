part of '../home_search_suggestions.dart';

/// Fuzzy score cutoff shared by recents filtering and library matching —
/// the same `> 50` threshold the old string-only dropdown used.
const searchSuggestionScoreCutoff = 50;

/// Max rows per library group (playlists / albums / artists) in the panel.
const searchSuggestionGroupCap = 3;

/// Max live-song rows in the panel. Live results are one gated network call
/// per debounced term, so they get their own slightly larger cap.
const searchSuggestionLiveCap = 4;

/// Fallback height cap for the panel. The bar normally passes the room that is
/// really left under the field, so the dropdown grows with its content instead
/// of being cut off at a fixed pixel height; this is only used when nothing
/// measured that room (first frame, or a panel built on its own in a test).
const searchSuggestionPanelMaxHeight = 360.0;

/// Space kept clear between the panel's bottom edge and the window's bottom,
/// so a full-height dropdown never looks glued to the edge of the screen.
const searchSuggestionPanelBottomGutter = 16.0;

/// Width of a row's leading slot, shared by cover art and plain icons.
int suggestionScore(String haystack, String query) =>
    weightedRatio(haystack.toLowerCase(), query.trim().toLowerCase());

/// Best-N fuzzy matches of [query] across [items], ranked by the best score
/// of any of the item's [fields] (e.g. album name + artist names). Below the
/// cutoff scores nothing; a blank query matches nothing — recents own the
/// empty state. Never mutates the input.
List<T> topMatches<T>(
  Iterable<T> items,
  String query,
  List<String> Function(T item) fields, {
  int limit = searchSuggestionGroupCap,
}) {
  if (query.trim().isEmpty) return [];
  final scored = <({int score, T item})>[];
  for (final item in items) {
    var best = 0;
    for (final field in fields(item)) {
      final score = suggestionScore(field, query);
      if (score > best) best = score;
    }
    if (best > searchSuggestionScoreCutoff) {
      scored.add((score: best, item: item));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return [for (final entry in scored.take(limit)) entry.item];
}

/// Recent-search filtering with the old dropdown's semantics: empty text
/// shows everything, otherwise the fuzzy cutoff applies.
List<String> filterRecentSearches(List<String> recents, String text) {
  if (text.trim().isEmpty) return List.of(recents);
  return [
    for (final term in recents)
      if (suggestionScore(term, text) > searchSuggestionScoreCutoff) term,
  ];
}

/// One row of the search suggestion panel.
sealed class HomeSearchSuggestion {
  /// Text written into the field when a recent row is picked.
  String get fillText;
}

/// Library rows (playlist / album / artist / track). Recent and live rows
/// are not members, so a group typed as [LibrarySearchSuggestion] is
/// exhaustive with no impossible case.
sealed class LibrarySearchSuggestion extends HomeSearchSuggestion {}

/// Pre-grouped suggestion lists. Built directly at each loop site in
/// [buildSearchSuggestions] — never by post-hoc `is`-splitting a flat list,
/// which is what let the old `RecentSearchSuggestion() => SizedBox.shrink()`
/// dead branch exist.
typedef SearchSuggestions = ({
  List<RecentSearchSuggestion> recents,
  List<LiveTrackSearchSuggestion> live,
  List<LibrarySearchSuggestion> library,
});

class RecentSearchSuggestion extends HomeSearchSuggestion {
  final String term;
  RecentSearchSuggestion(this.term);

  @override
  String get fillText => term;
}

class PlaylistSearchSuggestion extends LibrarySearchSuggestion {
  final SpotubeSimplePlaylistObject playlist;
  PlaylistSearchSuggestion(this.playlist);

  @override
  String get fillText => playlist.name;
}

class AlbumSearchSuggestion extends LibrarySearchSuggestion {
  final SpotubeSimpleAlbumObject album;
  AlbumSearchSuggestion(this.album);

  @override
  String get fillText => album.name;
}

class ArtistSearchSuggestion extends LibrarySearchSuggestion {
  final SpotubeFullArtistObject artist;
  ArtistSearchSuggestion(this.artist);

  @override
  String get fillText => artist.name;
}

class TrackSearchSuggestion extends LibrarySearchSuggestion {
  final SpotubeFullTrackObject track;
  TrackSearchSuggestion(this.track);

  @override
  String get fillText => track.name;
}

/// A live (network) song match. Renders exactly like [TrackSearchSuggestion]
/// but groups under the panel's Songs header instead of the library group.
class LiveTrackSearchSuggestion extends TrackSearchSuggestion {
  LiveTrackSearchSuggestion(super.track);
}

/// The panel's "see all results" footer. A suggestion like any other, so
/// arrow keys reach it and activation stays a single dispatch in the bar.
class SeeAllSearchSuggestion extends HomeSearchSuggestion {
  final String term;
  SeeAllSearchSuggestion(this.term);

  @override
  String get fillText => term;
}

/// The panel's rows in the order they are painted: recents, live songs,
/// library matches, then the see-all footer. Keyboard navigation counts
/// through this and the panel counts the same way as it emits rows, so a row
/// number cannot mean two different things.
List<HomeSearchSuggestion> suggestionRowsInPaintOrder(
  SearchSuggestions options, {
  String? seeAllTerm,
}) =>
    [
      ...options.recents,
      ...options.live,
      ...options.library,
      if (seeAllTerm != null) SeeAllSearchSuggestion(seeAllTerm),
    ];

/// The `item.*` and `search.selectedIndex` context a render-point template
/// receives for one suggestion row.
///
/// The map is read-only data. The host keeps activation and keyboard focus
/// around the template, so a template that ignores every binding still
/// behaves like the shipped row.
Map<String, Object?> searchSuggestionContext(
  HomeSearchSuggestion option, {
  int? selectedIndex,
  bool selected = false,
}) {
  final values = <String, Object?>{
    'search.selectedIndex': selectedIndex ?? -1,
    'item.selected': selected,
    'item.isActive': false,
  };

  void put({
    required String id,
    required String type,
    required String title,
    String subtitle = '',
    String artwork = '',
    int duration = 0,
  }) {
    values
      ..['item.id'] = id
      ..['item.type'] = type
      ..['item.title'] = title
      ..['item.subtitle'] = subtitle
      ..['item.artwork'] = artwork
      ..['item.duration'] = duration;
  }

  switch (option) {
    case RecentSearchSuggestion(:final term):
      put(id: term, type: 'recent', title: term);
    case SeeAllSearchSuggestion(:final term):
      put(id: term, type: 'seeAll', title: term);
    case LiveTrackSearchSuggestion(:final track):
      put(
        id: track.id,
        type: 'track',
        title: track.name,
        subtitle: '${track.artists.asString()} · ${track.album.name}',
        artwork: track.album.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.albumArt,
        ),
        duration: (track.durationMs / 1000).round(),
      );
      values
        ..['item.live'] = true
        ..['item.artist'] = track.artists.asString()
        ..['item.album'] = track.album.name;
    case TrackSearchSuggestion(:final track):
      put(
        id: track.id,
        type: 'track',
        title: track.name,
        subtitle: '${track.artists.asString()} · ${track.album.name}',
        artwork: track.album.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.albumArt,
        ),
        duration: (track.durationMs / 1000).round(),
      );
      values
        ..['item.artist'] = track.artists.asString()
        ..['item.album'] = track.album.name;
    case PlaylistSearchSuggestion(:final playlist):
      put(
        id: playlist.id,
        type: 'playlist',
        title: playlist.name,
        subtitle: 'Playlist',
        artwork: playlist.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.collection,
        ),
      );
    case AlbumSearchSuggestion(:final album):
      put(
        id: album.id,
        type: 'album',
        title: album.name,
        subtitle: album.artists.asString(),
        artwork: album.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.albumArt,
        ),
      );
      values['item.artist'] = album.artists.asString();
    case ArtistSearchSuggestion(:final artist):
      put(
        id: artist.id,
        type: 'artist',
        title: artist.name,
        subtitle: 'Artist',
        artwork: artist.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.artist,
        ),
      );
  }

  return values;
}
