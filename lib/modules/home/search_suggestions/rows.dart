part of '../home_search_suggestions.dart';

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
      final bottom = child.localToGlobal(Offset.zero, ancestor: content).dy +
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

const _leadingSlot = 34.0;
