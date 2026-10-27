import 'dart:async';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/dialogs/select_device_dialog.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/duration.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/artist/top_tracks.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/album.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';

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
const _leadingSlot = 34.0;

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

/// The suggestion dropdown panel: recent searches, live songs and cover-art
/// rows for matching library playlists, albums and artists, with a
/// "see all results" footer.
///
/// Rendered by [HomeSearchBar] in an anchored [OverlayPortal]; the bar
/// computes [options] fresh in build scope, so rows always reflect the
/// latest recents, live results and library snapshot. Every row reports the
/// same [onActivate] — the bar dispatches by suggestion type, which keeps
/// mouse and keyboard activation on one code path.
///
/// [activeIndex] is the keyboard-highlighted row, counted in
/// [suggestionRowsInPaintOrder] order.
class HomeSearchSuggestionsPanel extends StatelessWidget {
  final List<RecentSearchSuggestion> recents;
  final List<LiveTrackSearchSuggestion> live;
  final List<LibrarySearchSuggestion> library;
  final String query;
  final String? seeAllTerm;
  final int? activeIndex;
  final bool liveLoading;
  final void Function(HomeSearchSuggestion suggestion) onActivate;

  /// The row's play button: start playback of its song, album, playlist or
  /// artist top tracks *and* open that page. Null hides the button (tests).
  final void Function(LibrarySearchSuggestion suggestion)? onPlay;

  /// The cover's play: start playback and nothing else, so the listener stays
  /// in Browse. Null leaves the cover as decoration.
  final void Function(LibrarySearchSuggestion suggestion)? onPlayOnly;

  /// Tapping the album in a song row's subtitle opens that album. Null leaves
  /// it as plain text.
  final void Function(SpotubeSimpleAlbumObject album)? onOpenAlbum;

  /// Tapping the artist in a song row's subtitle opens that artist. The first
  /// artist is used when a song credits several. Null leaves it as plain text.
  final void Function(SpotubeSimpleArtistObject artist)? onOpenArtist;
  final void Function(String term) onRemoveRecent;
  final void Function() onClearRecents;

  /// Tallest the panel may get. The bar passes the room actually left under
  /// the search field, so a long list grows the dropdown instead of being
  /// clipped at a fixed height halfway through a row.
  final double maxHeight;

  const HomeSearchSuggestionsPanel({
    required this.recents,
    required this.live,
    required this.library,
    required this.query,
    required this.onActivate,
    this.seeAllTerm,
    this.activeIndex,
    this.liveLoading = false,
    this.onPlay,
    this.onPlayOnly,
    this.onOpenAlbum,
    this.onOpenArtist,
    required this.onRemoveRecent,
    required this.onClearRecents,
    this.maxHeight = searchSuggestionPanelMaxHeight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Bumped once per row as it is emitted, which is what makes [activeIndex]
    // mean the same thing here and in the bar. Paint order must stay in step
    // with [suggestionRowsInPaintOrder].
    var painted = 0;
    bool nextSelected() => activeIndex == painted++;
    // Local alias so the null-check survives into the row closures.
    final onPlay = this.onPlay;
    final onPlayOnly = this.onPlayOnly;
    final onOpenAlbum = this.onOpenAlbum;
    final onOpenArtist = this.onOpenArtist;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      // The card clips nothing by default, so the rows used to paint square
      // corners straight over its own rounding.
      clipBehavior: Clip.antiAlias,
      child: _RowSnappedScrollView(
        maxHeight: maxHeight,
        maxWidth: 520,
        // One gutter for the whole panel: durations and the "Clear all"
        // button no longer sit against the card's border.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recents.isNotEmpty) ...[
                _SectionHeader(
                  icon: SpotubeIcons.history,
                  title: context.l10n.recent_searches,
                  trailing: OutlineButton(
                    size: ButtonSize.small,
                    density: ButtonDensity.compact,
                    onPressed: onClearRecents,
                    child: Text(context.l10n.clear_all),
                  ),
                ),
                for (final recent in recents)
                  _SuggestionRow(
                    selected: nextSelected(),
                    leading: const Icon(SpotubeIcons.history),
                    title: _highlightedTitle(context, recent.term, query),
                    onTap: () => onActivate(recent),
                    trailing: IconButton.ghost(
                      size: ButtonSize.small,
                      density: ButtonDensity.compact,
                      icon: const Icon(SpotubeIcons.close),
                      onPressed: () => onRemoveRecent(recent.term),
                    ),
                  ),
              ],
              if (live.isNotEmpty || liveLoading) ...[
                if (recents.isNotEmpty) const _GroupDivider(),
                _SectionHeader(
                  icon: SpotubeIcons.music,
                  title: context.l10n.songs,
                ),
                if (liveLoading && live.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(size: 2),
                      ),
                    ),
                  ),
                for (final option in live)
                  _TrackRow(
                    selected: nextSelected(),
                    query: query,
                    track: option.track,
                    onTap: () => onActivate(option),
                    onPlay: onPlay == null ? null : () => onPlay(option),
                    onPlayOnly:
                        onPlayOnly == null ? null : () => onPlayOnly(option),
                    onOpenAlbum: onOpenAlbum,
                    onOpenArtist: onOpenArtist,
                  ),
              ],
              if (library.isNotEmpty) ...[
                if (recents.isNotEmpty || live.isNotEmpty)
                  const _GroupDivider(),
                _SectionHeader(
                  icon: SpotubeIcons.library,
                  title: context.l10n.from_your_library,
                ),
                for (final option in library)
                  switch (option) {
                    TrackSearchSuggestion(:final track) => _TrackRow(
                        selected: nextSelected(),
                        query: query,
                        track: track,
                        onTap: () => onActivate(option),
                        onPlay: onPlay == null ? null : () => onPlay(option),
                        onPlayOnly: onPlayOnly == null
                            ? null
                            : () => onPlayOnly(option),
                        onOpenAlbum: onOpenAlbum,
                        onOpenArtist: onOpenArtist,
                      ),
                    PlaylistSearchSuggestion(:final playlist) => _SuggestionRow(
                        selected: nextSelected(),
                        leading: _CoverArt(
                          onTap: onPlayOnly == null
                              ? null
                              : () => onPlayOnly(option),
                          imageUrl:
                              playlist.images.from200PxTo300PxOrSmallestImage(
                            ImagePlaceholder.collection,
                          ),
                        ),
                        title: _highlightedTitle(context, playlist.name, query),
                        subtitle: Text(
                          context.l10n.playlist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _RowActions(
                          onPlay: onPlay == null ? null : () => onPlay(option),
                        ),
                        onTap: () => onActivate(option),
                      ),
                    AlbumSearchSuggestion(:final album) => _SuggestionRow(
                        selected: nextSelected(),
                        leading: _CoverArt(
                          onTap: onPlayOnly == null
                              ? null
                              : () => onPlayOnly(option),
                          imageUrl:
                              album.images.from200PxTo300PxOrSmallestImage(
                            ImagePlaceholder.albumArt,
                          ),
                        ),
                        title: _highlightedTitle(context, album.name, query),
                        subtitle: _SubtitleLink(
                          label: album.artists.asString(),
                          onTap: onOpenArtist == null || album.artists.isEmpty
                              ? null
                              : () => onOpenArtist(album.artists.first),
                        ),
                        trailing: _RowActions(
                          onPlay: onPlay == null ? null : () => onPlay(option),
                        ),
                        onTap: () => onActivate(option),
                      ),
                    ArtistSearchSuggestion(:final artist) => _SuggestionRow(
                        selected: nextSelected(),
                        leading: _CoverArt(
                          round: true,
                          onTap: onPlayOnly == null
                              ? null
                              : () => onPlayOnly(option),
                          imageUrl:
                              artist.images.from200PxTo300PxOrSmallestImage(
                            ImagePlaceholder.artist,
                          ),
                        ),
                        title: _highlightedTitle(context, artist.name, query),
                        subtitle: Text(
                          context.l10n.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _RowActions(
                          onPlay: onPlay == null ? null : () => onPlay(option),
                        ),
                        onTap: () => onActivate(option),
                      ),
                  },
              ],
              // The only thing on screen when a query matches nothing, so
              // typing never looks like a dead field.
              if (seeAllTerm != null) ...[
                if (recents.isNotEmpty || live.isNotEmpty || library.isNotEmpty)
                  const _GroupDivider(),
                _SuggestionRow(
                  selected: nextSelected(),
                  leading: const Icon(SpotubeIcons.search),
                  title: Text(context.l10n.see_all_results_for(seeAllTerm!)),
                  onTap: () => onActivate(SeeAllSearchSuggestion(seeAllTerm!)),
                ),
              ],
            ],
          ),
      ),
    );
  }
}

/// Scroll viewport that stops at the last row which fits whole.
///
/// A dropdown capped at a pixel height slices whichever row lands on the fold,
/// which is what made the last song look abruptly cut. This measures the rows
/// after layout and trims the viewport to the gutter between two of them, so
/// the fold never crosses a row. The rows that no longer fit still scroll.
class _RowSnappedScrollView extends StatefulWidget {
  const _RowSnappedScrollView({
    required this.maxHeight,
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxHeight;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<_RowSnappedScrollView> createState() => _RowSnappedScrollViewState();
}

class _RowSnappedScrollViewState extends State<_RowSnappedScrollView> {
  final _contentKey = GlobalKey();

  /// Null means "use [widget.maxHeight]": either everything fits already, or
  /// not even one row does.
  double? _snapped;

  @override
  Widget build(BuildContext context) {
    // Row heights follow text scale, width and which sections are present, so
    // the boundary is re-derived after every layout instead of cached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _snapToRows());
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: _snapped ?? widget.maxHeight,
        maxWidth: widget.maxWidth,
      ),
      // The gutter sits outside the viewport on purpose: padding inside a
      // scroll view is part of the content, so at the fold it would show a
      // few pixels of the next row instead of a clean row edge.
      child: Padding(
        padding: widget.padding,
        child: SingleChildScrollView(
          child: KeyedSubtree(key: _contentKey, child: widget.child),
        ),
      ),
    );
  }

  void _snapToRows() {
    if (!mounted) return;
    final content = _contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox || !content.hasSize) return;

    final gutters = widget.padding.vertical;
    final usable = widget.maxHeight - gutters;

    // Everything already fits: the scroll view shrink-wraps, nothing to trim.
    if (content.size.height <= usable) {
      if (_snapped != null) setState(() => _snapped = null);
      return;
    }

    var boundary = 0.0;
    content.visitChildren((child) {
      if (child is! RenderBox || !child.hasSize) return;
      final bottom =
          child.localToGlobal(Offset.zero, ancestor: content).dy +
              child.size.height;
      if (bottom <= usable) boundary = max(boundary, bottom);
    });

    // A single row taller than the whole panel cannot be shown whole; showing
    // a slice beats collapsing the dropdown to its padding.
    final next = boundary <= 0 ? null : gutters + boundary;
    if (next != _snapped) setState(() => _snapped = next);
  }

  @override
  void didUpdateWidget(covariant _RowSnappedScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxHeight != widget.maxHeight) _snapped = null;
  }
}

/// Title with the first case-insensitive occurrence of [query] bolded.
/// Falls back to plain text when there is no literal overlap (fuzzy hit).
Widget _highlightedTitle(BuildContext context, String title, String query) {
  final q = query.trim();
  final index = q.isEmpty ? -1 : title.toLowerCase().indexOf(q.toLowerCase());
  final text = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
  if (index == -1) return text;
  return RichText(
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    text: TextSpan(
      style: DefaultTextStyle.of(context).style,
      children: [
        TextSpan(text: title.substring(0, index)),
        TextSpan(
          text: title.substring(index, index + q.length),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: title.substring(index + q.length)),
      ],
    ),
  );
}

/// A song row: cover (which plays without navigating), title (match bolded),
/// a subtitle whose two halves open that artist and album, and a trailing play
/// button in front of the duration. Shared by live and library songs.
class _TrackRow extends StatelessWidget {
  final String query;
  final SpotubeFullTrackObject track;
  final void Function() onTap;
  final void Function()? onPlay;
  final void Function()? onPlayOnly;
  final void Function(SpotubeSimpleAlbumObject album)? onOpenAlbum;
  final void Function(SpotubeSimpleArtistObject artist)? onOpenArtist;
  final bool selected;

  const _TrackRow({
    required this.query,
    required this.track,
    required this.onTap,
    this.onPlay,
    this.onPlayOnly,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return _SuggestionRow(
      selected: selected,
      leading: _CoverArt(
        onTap: onPlayOnly,
        imageUrl: track.album.images.from200PxTo300PxOrSmallestImage(
          ImagePlaceholder.albumArt,
        ),
      ),
      title: _highlightedTitle(context, track.name, query),
      subtitle: _TrackSubtitle(
        artist: track.artists.asString(),
        creditedArtist: track.artists.firstOrNull,
        album: track.album,
        onOpenAlbum: onOpenAlbum,
        onOpenArtist: onOpenArtist,
      ),
      trailing: _RowActions(
        onPlay: onPlay,
        duration: Duration(milliseconds: track.durationMs)
            .toHumanReadableString(padZero: false),
      ),
      onTap: onTap,
    );
  }
}

/// "artist • album" with both halves tappable, so a song row can drop you
/// straight into the collection it came from or onto whoever performed it.
/// A credit lists several artists but the row only has one target, so the
/// first is the one that opens. Spotube tracks carry album provenance only —
/// playlist membership is not on the model.
class _TrackSubtitle extends StatelessWidget {
  final String artist;
  final SpotubeSimpleArtistObject? creditedArtist;
  final SpotubeSimpleAlbumObject album;
  final void Function(SpotubeSimpleAlbumObject album)? onOpenAlbum;
  final void Function(SpotubeSimpleArtistObject artist)? onOpenArtist;

  const _TrackSubtitle({
    required this.artist,
    required this.creditedArtist,
    required this.album,
    required this.onOpenAlbum,
    required this.onOpenArtist,
  });

  @override
  Widget build(BuildContext context) {
    final onOpenArtist = creditedArtist == null ? null : this.onOpenArtist;
    final onOpenAlbum = this.onOpenAlbum;

    return Row(
      spacing: 6,
      children: [
        Flexible(
          child: _SubtitleLink(
            label: artist,
            onTap: onOpenArtist == null
                ? null
                : () => onOpenArtist(creditedArtist!),
          ),
        ),
        const Text('•').small().muted(),
        Flexible(
          child: _SubtitleLink(
            label: album.name,
            onTap: onOpenAlbum == null ? null : () => onOpenAlbum(album),
          ),
        ),
      ],
    );
  }
}

/// One word of a subtitle that doubles as a route: underlined and clickable
/// when [onTap] is given, indistinguishable from its surroundings when not.
class _SubtitleLink extends StatelessWidget {
  final String label;
  final void Function()? onTap;

  const _SubtitleLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: onTap == null
          ? null
          : const TextStyle(decoration: TextDecoration.underline),
    );
    if (onTap == null) return text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Semantics(label: context.l10n.open, button: true, child: text),
      ),
    );
  }
}

/// The trailing cluster: a play button, then the track's length. The button
/// sits in front of the duration and is always drawn — revealing it on hover
/// left a stale highlight on every row after a panel rebuild.
class _RowActions extends StatelessWidget {
  final VoidCallback? onPlay;
  final String? duration;

  const _RowActions({this.onPlay, this.duration});

  @override
  Widget build(BuildContext context) {
    final onPlay = this.onPlay;
    if (onPlay == null && duration == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (onPlay != null)
          IconButton.ghost(
            size: ButtonSize.small,
            density: ButtonDensity.compact,
            icon: const Icon(SpotubeIcons.play),
            onPressed: onPlay,
          ),
        if (duration != null) Text(duration!).small().muted(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 14),
          Expanded(child: Text(title).small().muted()),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A hairline between suggestion groups. The group headers alone did not read
/// as a boundary once the panel could hold three groups at once.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Theme.of(context).colorScheme.border,
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final void Function() onTap;

  /// The keyboard-highlighted row.
  final bool selected;

  const _SuggestionRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.selected = false,
  });

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(covariant _SuggestionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Arrow keys walk past the panel's own scroll extent, so the highlighted
  /// row has to follow the selection.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.05,
        duration: const Duration(milliseconds: 120),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Inset, so the keyboard highlight reads as a row inside the panel
      // rather than a band painted edge to edge over the card.
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A tint rather than the raw accent: a solid accent fill puts the
          // row's own text on lavender and it stops being readable, which is
          // exactly when you need to read it.
          color: widget.selected
              ? Theme.of(context).colorScheme.accent.withValues(alpha: 0.28)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: GhostButton(
          density: ButtonDensity.compact,
          onPressed: widget.onTap,
          child: Row(
            spacing: 10,
            children: [
              // Covers and plain icons share one slot, or the titles of
              // groups that mix them start at different columns.
              SizedBox(
                width: _leadingSlot,
                child: Center(child: widget.leading),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: DefaultTextStyle.of(context).style,
                      child: widget.title,
                    ),
                    if (widget.subtitle != null)
                      DefaultTextStyle(
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(fontSize: 12),
                        child: widget.subtitle!,
                      ).muted(),
                  ],
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Cover art, which plays the row without navigating anywhere.
///
/// The badge only appears while the pointer is over the cover, so it is
/// invisible until asked for. Hover-revealed controls lived here once before
/// and misbehaved: `_hovering` outlived the cover it belonged to, because a
/// panel rebuild reuses these elements by position and `onExit` never fires
/// for a widget that simply changed underneath the pointer. `didUpdateWidget`
/// clears it whenever the artwork changes, which is the only way this cover
/// can be showing something other than what was hovered.
class _CoverArt extends StatefulWidget {
  final String imageUrl;
  final bool round;
  final VoidCallback? onTap;

  const _CoverArt({
    required this.imageUrl,
    this.round = false,
    this.onTap,
  });

  @override
  State<_CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<_CoverArt> {
  bool _hovering = false;

  @override
  void didUpdateWidget(_CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl && _hovering) {
      _hovering = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const side = _leadingSlot;
    final onTap = widget.onTap;
    final art = Container(
      width: side,
      height: side,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.round ? side / 2 : 5),
        image: DecorationImage(
          image: UniversalImage.imageProvider(widget.imageUrl),
          fit: BoxFit.cover,
        ),
      ),
      // Fixed black-on-white: it sits over arbitrary album art, so neither
      // theme's palette is the right contrast anchor here.
      child: onTap == null || !_hovering
          ? null
          : Center(
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xCC000000),
                ),
                child: const Icon(
                  SpotubeIcons.play,
                  size: 10,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
    );
    if (onTap == null) return art;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // A bare glyph says nothing to a screen reader, and the badge is only
      // drawn while hovered, so this label is the whole announcement.
      child: Semantics(
        button: true,
        label: context.l10n.play,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: art,
        ),
      ),
    );
  }
}

/// Builds the pre-grouped suggestions for the search panel: filtered recents
/// (instant, cheap), live songs (one gated call per debounce pause), then up
/// to [searchSuggestionGroupCap] library matches per group.
///
/// Two query strings split cheap from expensive work: [text] is the raw field
/// (recents filter runs per keystroke) while [libraryQueryText] is the
/// debounced term (the `weightedRatio` fuzzy match runs once per pause, on
/// the same cadence as the live network call). A blank [text] force-clears
/// the library and live groups regardless of a stale debounce value, so
/// clearing the field never leaves rows lingering for a beat.
/// All-empty when there is nothing to show, so the panel stays hidden
/// (logged out / still loading reads as empty, never an error).
SearchSuggestions buildSearchSuggestions({
  required String text,
  required String libraryQueryText,
  required List<String> recents,
  List<SpotubeFullTrackObject> liveTracks = const [],
  List<SpotubeFullTrackObject> tracks = const [],
  List<SpotubeSimplePlaylistObject> playlists = const [],
  List<SpotubeSimpleAlbumObject> albums = const [],
  List<SpotubeFullArtistObject> artists = const [],
}) {
  // Clear-path guard: recents own the empty state; library/live clear now.
  final libraryQuery = text.trim().isEmpty ? '' : libraryQueryText;
  return (
    recents: [
      for (final term in filterRecentSearches(recents, text))
        RecentSearchSuggestion(term),
    ],
    live: [
      if (text.trim().isNotEmpty)
        for (final track in liveTracks.take(searchSuggestionLiveCap))
          LiveTrackSearchSuggestion(track),
    ],
    library: [
      if (libraryQuery.trim().isNotEmpty) ...[
        for (final track in topMatches(
            tracks, libraryQuery, (t) => [t.name, t.artists.asString()]))
          TrackSearchSuggestion(track),
        for (final playlist
            in topMatches(playlists, libraryQuery, (p) => [p.name]))
          PlaylistSearchSuggestion(playlist),
        for (final album in topMatches(
            albums, libraryQuery, (a) => [a.name, a.artists.asString()]))
          AlbumSearchSuggestion(album),
        for (final artist in topMatches(artists, libraryQuery, (a) => [a.name]))
          ArtistSearchSuggestion(artist),
      ],
    ],
  );
}

/// Reads the currently loaded library lists without subscribing — the panel
/// only lives while typing, and the enclosing bar rebuilds (recreating the
/// closure) on every keystroke anyway.
({
  List<SpotubeFullTrackObject> tracks,
  List<SpotubeSimplePlaylistObject> playlists,
  List<SpotubeSimpleAlbumObject> albums,
  List<SpotubeFullArtistObject> artists,
}) readLibrarySnapshot(WidgetRef ref) {
  return (
    tracks: ref.read(metadataPluginSavedTracksProvider).asData?.value.items ??
        const <SpotubeFullTrackObject>[],
    playlists:
        ref.read(metadataPluginSavedPlaylistsProvider).asData?.value.items ??
            const <SpotubeSimplePlaylistObject>[],
    albums: ref.read(metadataPluginSavedAlbumsProvider).asData?.value.items ??
        const <SpotubeSimpleAlbumObject>[],
    artists: ref.read(metadataPluginSavedArtistsProvider).asData?.value.items ??
        const <SpotubeFullArtistObject>[],
  );
}

/// Opens a library suggestion's page. Recent and see-all rows are submits,
/// not navigations, so they never reach this — [LibrarySearchSuggestion] is
/// the exhaustive set.
void openLibrarySuggestion(
  BuildContext context,
  FocusNode focusNode,
  LibrarySearchSuggestion option,
) {
  focusNode.unfocus();
  switch (option) {
    case TrackSearchSuggestion(:final track):
      context.navigateTo(TrackRoute(trackId: track.id));
    case PlaylistSearchSuggestion(:final playlist):
      context.navigateTo(
        PlaylistRoute(id: playlist.id, playlist: playlist),
      );
    case AlbumSearchSuggestion(:final album):
      context.navigateTo(AlbumRoute(id: album.id, album: album));
    case ArtistSearchSuggestion(:final artist):
      context.navigateTo(ArtistRoute(artistId: artist.id));
  }
}

/// Opens an artist credited on a row. Song and album credits carry the
/// lighter [SpotubeSimpleArtistObject], not the full object a search hit
/// produces, so they cannot go through [openLibrarySuggestion] — but they end
/// up on the same route.
void openCreditedArtist(
  BuildContext context,
  FocusNode focusNode,
  SpotubeSimpleArtistObject artist,
) {
  focusNode.unfocus();
  context.navigateTo(ArtistRoute(artistId: artist.id));
}

/// The panel's play button: songs play directly, albums and playlists load
/// their collection, artists load their top tracks — the same actions the grid
/// cards' play buttons perform. The caller opens the page alongside it.
Future<void> playLibrarySuggestion(
  BuildContext context,
  WidgetRef ref,
  LibrarySearchSuggestion option,
) async {
  switch (option) {
    case TrackSearchSuggestion(:final track):
      final notifier = ref.read(audioPlayerProvider.notifier);
      final queue = ref.read(audioPlayerProvider);
      if (queue.tracks.any((element) => element.id == track.id)) {
        await notifier.jumpToTrack(track);
        return;
      }
      await notifier.load([track], autoPlay: true);
      unawaited(ref.read(playbackHistoryActionsProvider).addTrack(track));
    case AlbumSearchSuggestion(:final album):
      if (_resumeIfLoaded(ref, album.id)) return;
      Future<List<SpotubeFullTrackObject>> fetchInitial() async =>
          (await ref.read(metadataPluginAlbumTracksProvider(album.id).future))
              .items;
      Future<List<SpotubeFullTrackObject>> fetchAll() async {
        await fetchInitial();
        return ref
            .read(metadataPluginAlbumTracksProvider(album.id).notifier)
            .fetchAll();
      }

      await _playCollection(
        context,
        ref,
        collectionId: album.id,
        fetchInitial: fetchInitial,
        fetchAll: fetchAll,
        loadRemote: (tracks) => ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.album(
                tracks: tracks,
                collection: album,
              ),
            ),
        recordHistory: () =>
            ref.read(playbackHistoryActionsProvider).addAlbums([album]),
      );
    case PlaylistSearchSuggestion(:final playlist):
      if (_resumeIfLoaded(ref, playlist.id)) return;
      final isLiked = playlist.id == 'user-liked-tracks';
      Future<List<SpotubeFullTrackObject>> fetchInitial() async => isLiked
          ? (await ref.read(metadataPluginSavedTracksProvider.future)).items
          : (await ref.read(
                  metadataPluginPlaylistTracksProvider(playlist.id).future))
              .items;
      Future<List<SpotubeFullTrackObject>> fetchAll() async {
        await fetchInitial();
        return isLiked
            ? ref.read(metadataPluginSavedTracksProvider.notifier).fetchAll()
            : ref
                .read(
                  metadataPluginPlaylistTracksProvider(playlist.id).notifier,
                )
                .fetchAll();
      }

      await _playCollection(
        context,
        ref,
        collectionId: playlist.id,
        fetchInitial: fetchInitial,
        fetchAll: fetchAll,
        loadRemote: (tracks) => ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.playlist(
                tracks: tracks,
                collection: playlist,
              ),
            ),
        recordHistory: () =>
            ref.read(playbackHistoryActionsProvider).addPlaylists([playlist]),
      );
    case ArtistSearchSuggestion(:final artist):
      // Artists own no collection id, so this is a plain queue load of their
      // top tracks rather than [_playCollection].
      final topTracks = (await ref
              .read(metadataPluginArtistTopTracksProvider(artist.id).future))
          .items
          .toList();
      if (topTracks.isEmpty || !context.mounted) return;

      final isRemoteDevice = await showSelectDeviceDialog(context, ref);
      if (isRemoteDevice == null) return;

      if (isRemoteDevice) {
        await ref.read(connectProvider.notifier).load(
              WebSocketLoadEventData.playlist(
                tracks: topTracks,
                collection: null,
              ),
            );
        return;
      }

      final notifier = ref.read(audioPlayerProvider.notifier);
      final queue = ref.read(audioPlayerProvider);
      if (queue.tracks.any((element) => element.id == topTracks.first.id)) {
        await notifier.jumpToTrack(topTracks.first);
        return;
      }
      await notifier.load(topTracks, autoPlay: true);
  }
}

/// True when the collection is already the active queue: the cover then just
/// resumes it (a no-op while playing) instead of restarting from the top.
bool _resumeIfLoaded(WidgetRef ref, String collectionId) {
  if (!ref.read(audioPlayerProvider).collections.contains(collectionId)) {
    return false;
  }
  final player = ref.read(audioPlayerPortProvider);
  if (!player.isPlaying) {
    unawaited(player.resume());
  }
  return true;
}

Future<void> _playCollection(
  BuildContext context,
  WidgetRef ref, {
  required String collectionId,
  required Future<List<SpotubeFullTrackObject>> Function() fetchInitial,
  required Future<List<SpotubeFullTrackObject>> Function() fetchAll,
  required Future<void> Function(List<SpotubeFullTrackObject>) loadRemote,
  required void Function() recordHistory,
}) async {
  final initialTracks = await fetchInitial();
  if (initialTracks.isEmpty || !context.mounted) return;

  final isRemoteDevice = await showSelectDeviceDialog(context, ref);
  if (isRemoteDevice == null) return;

  if (isRemoteDevice) {
    await loadRemote(await fetchAll());
    return;
  }

  final notifier = ref.read(audioPlayerProvider.notifier);
  await notifier.load(initialTracks, autoPlay: true);
  notifier.addCollection(collectionId);
  recordHistory();

  unawaited(appendCollectionTail(
    appendTail: (tail) => notifier.addTracks(tail),
    readCollections: () => ref.read(audioPlayerProvider).collections,
    collectionId: collectionId,
    alreadyLoaded: initialTracks,
    fetchAll: fetchAll,
  ));
}
