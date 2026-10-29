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
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/modules/theme_ui/theme_ui_render_points.dart';
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

part 'search_suggestions/model.dart';
part 'search_suggestions/rows.dart';
part 'search_suggestions/actions.dart';

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
  /// Render-point runtime inherited from the bar.
  ///
  /// Null keeps every shipped widget: a panel pumped on its own (tests,
  /// previews) does not need a theme document to render.
  final ThemeUiRuntime? runtime;
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
    this.runtime,
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
    final runtime = this.runtime;

    final recentTerms = [for (final recent in recents) recent.term];
    final hasQuery = query.trim().isNotEmpty;
    final suggestions = [
      for (final option in suggestionRowsInPaintOrder(
        (recents: recents, live: live, library: library),
        seeAllTerm: seeAllTerm,
      ))
        searchSuggestionContext(option, selectedIndex: activeIndex),
    ];
    final searchBindings = <String, Object?>{
      'search.query': query,
      'search.suggestions': suggestions,
      'search.selectedIndex': activeIndex ?? -1,
      'search.loading': liveLoading,
      'search.hasQuery': hasQuery,
      'search.recent': recentTerms,
      'search.error': '',
    };

    Map<String, Object?> itemOf(HomeSearchSuggestion option, bool selected) {
      return searchSuggestionContext(
        option,
        selectedIndex: activeIndex,
        selected: selected,
      );
    }

    Widget groupHeader({
      required String id,
      required IconData icon,
      required String title,
      required int count,
      String? preferredRenderPoint,
      Widget? trailing,
      Map<String, Object?> extra = const {},
    }) {
      return _SectionHeader(
        icon: icon,
        title: title,
        trailing: trailing,
        runtime: runtime,
        renderPoint: 'search.suggestion.group',
        preferredRenderPoint: preferredRenderPoint,
        bindings: {
          'group.id': id,
          'group.title': title,
          'group.count': count,
          ...extra,
        },
      );
    }

    Widget recentRow(RecentSearchSuggestion recent) {
      final selected = nextSelected();
      return _SuggestionRow(
        runtime: runtime,
        item: itemOf(recent, selected),
        selected: selected,
        leading: const Icon(SpotubeIcons.history),
        title: _highlightedTitle(context, recent.term, query),
        onTap: () => onActivate(recent),
        trailing: IconButton.ghost(
          size: ButtonSize.small,
          density: ButtonDensity.compact,
          icon: const Icon(SpotubeIcons.close),
          onPressed: () => onRemoveRecent(recent.term),
        ),
      );
    }

    Widget trackRow(
      LibrarySearchSuggestion option,
      SpotubeFullTrackObject track,
    ) {
      final selected = nextSelected();
      return _TrackRow(
        runtime: runtime,
        item: itemOf(option, selected),
        selected: selected,
        query: query,
        track: track,
        onTap: () => onActivate(option),
        onPlay: onPlay == null ? null : () => onPlay(option),
        onPlayOnly: onPlayOnly == null ? null : () => onPlayOnly(option),
        onOpenAlbum: onOpenAlbum,
        onOpenArtist: onOpenArtist,
      );
    }

    Widget libraryRow(LibrarySearchSuggestion option) {
      final selected = nextSelected();
      return switch (option) {
        TrackSearchSuggestion(:final track) => _TrackRow(
            runtime: runtime,
            item: itemOf(option, selected),
            selected: selected,
            query: query,
            track: track,
            onTap: () => onActivate(option),
            onPlay: onPlay == null ? null : () => onPlay(option),
            onPlayOnly: onPlayOnly == null ? null : () => onPlayOnly(option),
            onOpenAlbum: onOpenAlbum,
            onOpenArtist: onOpenArtist,
          ),
        PlaylistSearchSuggestion(:final playlist) => _SuggestionRow(
            runtime: runtime,
            item: itemOf(option, selected),
            selected: selected,
            leading: _CoverArt(
              onTap: onPlayOnly == null ? null : () => onPlayOnly(option),
              imageUrl: playlist.images.from200PxTo300PxOrSmallestImage(
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
            runtime: runtime,
            item: itemOf(option, selected),
            selected: selected,
            leading: _CoverArt(
              onTap: onPlayOnly == null ? null : () => onPlayOnly(option),
              imageUrl: album.images.from200PxTo300PxOrSmallestImage(
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
            runtime: runtime,
            item: itemOf(option, selected),
            selected: selected,
            leading: _CoverArt(
              round: true,
              onTap: onPlayOnly == null ? null : () => onPlayOnly(option),
              imageUrl: artist.images.from200PxTo300PxOrSmallestImage(
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
      };
    }

    Widget seeAllRow(String term) {
      final option = SeeAllSearchSuggestion(term);
      final selected = nextSelected();
      return _SuggestionRow(
        runtime: runtime,
        item: itemOf(option, selected),
        selected: selected,
        leading: const Icon(SpotubeIcons.search),
        title: Text(context.l10n.see_all_results_for(term)),
        onTap: () => onActivate(option),
      );
    }

    Widget loading = const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(size: 2),
        ),
      ),
    );
    if (runtime != null) {
      loading = ThemeUiTemplateHost(
        runtime: runtime,
        renderPoint: 'search.loading',
        bindings: {
          'search.query': query,
          'search.loading': true,
        },
        fallback: loading,
      );
    }

    // A query that matched nothing still gets the see-all footer, so the
    // empty state is a hint above it rather than a replacement for it.
    final showEmpty = hasQuery &&
        recents.isEmpty &&
        live.isEmpty &&
        library.isEmpty &&
        !liveLoading;

    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recents.isNotEmpty) ...[
          groupHeader(
            id: 'recent',
            icon: SpotubeIcons.history,
            title: context.l10n.recent_searches,
            count: recents.length,
            preferredRenderPoint: 'search.recent',
            extra: {'search.recent': recentTerms},
            trailing: OutlineButton(
              size: ButtonSize.small,
              density: ButtonDensity.compact,
              onPressed: onClearRecents,
              child: Text(context.l10n.clear_all),
            ),
          ),
          for (final recent in recents) recentRow(recent),
        ],
        if (live.isNotEmpty || liveLoading) ...[
          if (recents.isNotEmpty) const _GroupDivider(),
          groupHeader(
            id: 'songs',
            icon: SpotubeIcons.music,
            title: context.l10n.songs,
            count: live.length,
          ),
          if (liveLoading && live.isEmpty) loading,
          for (final option in live) trackRow(option, option.track),
        ],
        if (library.isNotEmpty) ...[
          if (recents.isNotEmpty || live.isNotEmpty) const _GroupDivider(),
          groupHeader(
            id: 'library',
            icon: SpotubeIcons.library,
            title: context.l10n.from_your_library,
            count: library.length,
          ),
          for (final option in library) libraryRow(option),
        ],
        if (showEmpty) ...[
          const _GroupDivider(),
          if (runtime != null)
            ThemeUiTemplateHost(
              runtime: runtime,
              renderPoint: 'search.empty',
              bindings: {'search.query': query},
              fallback: const SizedBox.shrink(),
            ),
        ],
        // The only thing on screen when a query matches nothing, so
        // typing never looks like a dead field.
        if (seeAllTerm != null) ...[
          if (recents.isNotEmpty || live.isNotEmpty || library.isNotEmpty)
            const _GroupDivider(),
          seeAllRow(seeAllTerm!),
        ],
      ],
    );

    Widget content = _RowSnappedScrollView(
      maxHeight: maxHeight,
      maxWidth: 520,
      // One gutter for the whole panel: durations and the "Clear all"
      // button no longer sit against the card's border.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: rows,
    );

    final suggestionsResolution = runtime == null
        ? null
        : resolveThemeUiRenderPoint(
            renderPoints: runtime.renderPoints,
            templates: runtime.templates,
            renderPoint: 'search.suggestions',
          );

    if (suggestionsResolution != null) {
      reportThemeUiRenderPointFallback(suggestionsResolution);
    }

    if (suggestionsResolution?.hasTemplate == true) {
      // The template paints the panel; the host still owns the anchored
      // placement and every row's gesture.
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ThemeUiTemplateHost(
                runtime: runtime!,
                renderPoint: 'search.suggestions',
                resolution: suggestionsResolution,
                bindings: searchBindings,
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
          content,
        ],
      );
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      // The card clips nothing by default, so the rows used to paint square
      // corners straight over its own rounding.
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
