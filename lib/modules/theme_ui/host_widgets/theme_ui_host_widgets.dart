import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:spotube/components/playbutton_view/collection_row_policy.dart';
import 'package:spotube/components/playbutton_view/playbutton_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/string.dart';
import 'package:spotube/models/equalizer/equalizer.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/album/album_card.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/artist/artist_card.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/player/player_controls.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/modules/player/player_queue.dart';
import 'package:spotube/modules/player/volume_slider.dart';
import 'package:spotube/modules/playlist/playlist_card.dart';
import 'package:spotube/modules/playlist/playlist_create_dialog.dart';
import 'package:spotube/modules/theme_ui/host_widgets/theme_ui_settings_body.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/theme_ui/host_item_context_menu.dart';
import 'package:spotube/modules/theme_ui/theme_pins.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/modules/theme_ui/theme_ui_runtime.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/crossfade_duration_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/albums.dart';
import 'package:spotube/provider/metadata_plugin/library/artists.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/sleep_timer_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/volume_provider.dart';

/// The closed set of host widgets a v4 theme may mount (§4.9 of the contract).
///
/// A theme composes its screens out of nodes; `hostWidget` is the one escape
/// hatch, kept deliberately short so it cannot become a second UI framework.
/// Every entry is a presentation wrapper over a widget the host already draws —
/// a re-implementation of the player or the library would drift from the real
/// one the first time the app changes.
///
/// Prop values are clamped rather than trusted. The authoring validator rejects
/// a typo in a prop name, but an installed plugin built against a different
/// host still has to render something sane.
class ThemeUiHostWidgets {
  const ThemeUiHostWidgets._();

  /// Mirrors `v4HostWidgetIds` in the authoring validator.
  static const ids = <String>{
    'library.playlists',
    'library.pins',
    'library.albums',
    'library.artists',
    'player.controls',
    'audio.bass',
    'audio.equalizer',
    'audio.crossfade',
    'audio.sleepTimer',
    'queue.list',
    'search.field',
    'theme.settings',
  };

  /// Mirrors `v4HostWidgetProps` — a prop outside this table is ignored here
  /// and an error in the validator.
  static const allowedProps = <String, Set<String>>{
    'library.playlists': {
      'compact',
      'showSearch',
      'showCreate',
      'limit',
      'filter',
      'pinTarget',
      'direction',
      'showPin',
      'showQueue',
      'showPlay',
      'coverPlays',
      'showTitle',
      'showSubtitle',
      'density',
      'coverSize',
      'coverRadius',
      'showDividers',
      'rowSpacing',
    },
    'library.pins': {
      'compact',
      'target',
      'direction',
      'showPin',
      'showQueue',
      'showPlay',
      'coverPlays',
      'showTitle',
      'showSubtitle',
      'density',
      'coverSize',
      'coverRadius',
      'showDividers',
      'rowSpacing',
    },
    'library.albums': {
      'compact',
      'showQueue',
      'showPlay',
      'coverPlays',
      'showTitle',
      'showSubtitle',
      'density',
      'coverSize',
      'coverRadius',
      'showDividers',
      'rowSpacing',
    },
    'library.artists': {
      'compact',
      'showPlay',
      'coverPlays',
      'showTitle',
      'showSubtitle',
      'density',
      'coverSize',
      'coverRadius',
      'showDividers',
      'rowSpacing',
    },
    'player.controls': {'compact', 'showProgress', 'showVolume'},
    'audio.bass': {'compact'},
    'audio.equalizer': {'bands'},
    'audio.crossfade': {},
    'audio.sleepTimer': {},
    'queue.list': {'compact'},
    'search.field': {'placeholder', 'scope'},
    'theme.settings': {},
  };

  /// Capabilities a widget needs on top of `ui.hostWidgets`.
  ///
  /// Only the ones the contract does not grant by default are listed: gating
  /// `library.read` or `player.control` here would hide the widget for a theme
  /// that never mentioned a default capability, which is not what §4.10 means.
  static const requiredCapabilities = <String, String>{
    'audio.bass': 'audio.effects',
    'audio.equalizer': 'audio.effects',
    'audio.crossfade': 'audio.effects',
    'audio.sleepTimer': 'audio.effects',
  };

  static bool isKnown(String id) => ids.contains(id);

  /// Prop names [id] does not read — for tests and for the debug overlay.
  static List<String> unknownProps(String id, Map<String, dynamic> props) {
    final allowed = allowedProps[id] ?? const <String>{};
    return [
      for (final key in props.keys)
        if (!allowed.contains(key)) key,
    ];
  }

  static bool boolProp(Object? raw, {bool fallback = false}) =>
      raw is bool ? raw : fallback;

  /// A whole-number prop, snapped into the range the host can honor.
  static int intProp(
    Object? raw, {
    required int min,
    required int max,
    required int fallback,
  }) {
    if (raw is! num || !raw.isFinite) return fallback;
    return raw.round().clamp(min, max);
  }

  static String enumProp(
    Object? raw, {
    required Set<String> values,
    required String fallback,
  }) {
    return raw is String && values.contains(raw) ? raw : fallback;
  }

  /// A string prop, trimmed, capped, and null when it carries nothing usable.
  static String? stringProp(Object? raw, {int maxLength = 80}) {
    if (raw is! String) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }

  /// The widget for [id], or nothing when it may not be mounted.
  ///
  /// Unknown ids, a missing capability and a document without `ui.hostWidgets`
  /// all render an empty box rather than failing: a theme authored against a
  /// newer host still loads, and the slot simply stays quiet.
  static Widget build({
    required ThemeUiRuntime runtime,
    required String id,
    required Map<String, dynamic> props,
  }) {
    if (!runtime.canUseHostWidgets || !isKnown(id)) {
      return const SizedBox.shrink();
    }
    final required = requiredCapabilities[id];
    if (required != null && !runtime.capabilities.contains(required)) {
      return const SizedBox.shrink();
    }

    final allowed = allowedProps[id]!;
    final clean = <String, dynamic>{
      for (final entry in props.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };

    return switch (id) {
      'library.playlists' => _ThemeUiPlaylists(clean),
      'library.pins' => _ThemeUiPlaylists(_pinProps(clean)),
      'library.albums' => _ThemeUiAlbums(clean),
      'library.artists' => _ThemeUiArtists(clean),
      'player.controls' => _ThemeUiPlayerControls(clean),
      'audio.bass' => _ThemeUiBass(clean),
      'audio.equalizer' => _ThemeUiEqualizer(clean),
      'audio.crossfade' => const _ThemeUiCrossfade(),
      'audio.sleepTimer' => const _ThemeUiSleepTimer(),
      'queue.list' => _ThemeUiQueue(clean),
      'search.field' => _ThemeUiSearchField(clean, runtime),
      'theme.settings' => const _ThemeUiSettings(),
      _ => const SizedBox.shrink(),
    };
  }

  /// `library.pins` is the playlist list pinned to one target: same rows, no
  /// search or create chrome, and nothing to filter away.
  static Map<String, dynamic> _pinProps(Map<String, dynamic> props) {
    return {
      if (props['compact'] is bool) 'compact': props['compact'],
      if (props['direction'] is String) 'direction': props['direction'],
      'filter': 'pins',
      if (props['target'] is String) 'pinTarget': props['target'],
      'limit': 200,
      'showSearch': false,
      'showCreate': false,
      if (props['showPin'] is bool) 'showPin': props['showPin'],
      if (props['showQueue'] is bool) 'showQueue': props['showQueue'],
      if (props['showPlay'] is bool) 'showPlay': props['showPlay'],
      if (props['coverPlays'] is bool) 'coverPlays': props['coverPlays'],
      if (props['showTitle'] is bool) 'showTitle': props['showTitle'],
      if (props['showSubtitle'] is bool) 'showSubtitle': props['showSubtitle'],
      if (props['density'] is String) 'density': props['density'],
      if (props['coverSize'] is num) 'coverSize': props['coverSize'],
      if (props['coverRadius'] is num) 'coverRadius': props['coverRadius'],
      if (props['showDividers'] is bool) 'showDividers': props['showDividers'],
      if (props['rowSpacing'] is num) 'rowSpacing': props['rowSpacing'],
    };
  }
}

/// The filter vocabularies, mirrored by the validator's prop table.
const _playlistFilters = <String>{'all', 'pins', 'recent'};
const _directions = <String>{'vertical', 'horizontal'};

/// A query scope is view state, so it stays inside the character set the
/// `setQuery` action already accepts.
final _queryScopePattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Which playlists a `library.playlists` / `library.pins` widget shows.
///
/// `pins` keeps the order the target stores them in, so a theme that pins five
/// lists sees those five, first. `recent` surfaces the pinned ones ahead of the
/// rest: neither the plugin nor the host keeps a per-playlist timestamp, so
/// "what the user is working with" is the most recent signal there is.
List<SpotubeSimplePlaylistObject> themeUiSelectPlaylists({
  required List<SpotubeSimplePlaylistObject> all,
  required List<String> pinnedIds,
  required String filter,
  required String query,
  required int limit,
}) {
  final byId = {for (final playlist in all) playlist.id: playlist};
  final pinned = [
    for (final id in pinnedIds)
      if (byId[id] != null) byId[id]!,
  ];
  final pinnedSet = pinnedIds.toSet();

  final items = switch (filter) {
    'pins' => pinned,
    'recent' => <SpotubeSimplePlaylistObject>[
        ...pinned,
        for (final playlist in all)
          if (!pinnedSet.contains(playlist.id)) playlist,
      ],
    _ => all,
  };

  final needle = query.trim().toLowerCase();
  final matched = needle.isEmpty
      ? items
      : items
          .where(
            (playlist) =>
                playlist.name.toLowerCase().contains(needle) ||
                playlist.description
                    .strippedHtml()
                    .toLowerCase()
                    .contains(needle),
          )
          .toList();

  return matched.take(limit).toList();
}

/// Cards or tiles, arranged for the widget's `compact` / `direction` props.
///
/// A card sizes its own width off the active layout but needs its height from
/// the parent, and a `Wrap` is the only grid available without a sliver host.
class _ThemeUiCollection extends StatelessWidget {
  const _ThemeUiCollection({
    required this.items,
    required this.builder,
    required this.compact,
    required this.horizontal,
    required this.hasArtist,
    this.listStyle = const CollectionListStyle(),
  });

  final List<Object> items;
  final Widget Function(BuildContext context, Object item) builder;
  final bool compact;
  final bool horizontal;
  final bool hasArtist;

  /// List-level styling from the theme: whether to separate compact rows and
  /// the additional vertical gap between rows.
  final CollectionListStyle listStyle;

  @override
  Widget build(BuildContext context) {
    final scale = context.theme.scaling;
    // A tile row is the cover plus the button's own vertical padding.
    final tileExtent = (50 * scale) + 24;

    if (horizontal) {
      return SizedBox(
        height: compact
            ? tileExtent
            : playbuttonCardExtent(context, hasArtist: hasArtist),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => Gap(8 + listStyle.rowSpacing.toDouble()),
          itemBuilder: (context, index) {
            // A tile fills the width it is given; a card picks its own.
            return compact
                ? SizedBox(
                    width: 300 * scale, child: builder(context, items[index]))
                : builder(context, items[index]);
          },
        ),
      );
    }

    if (compact) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => listStyle.showDividers
            ? const Divider()
            : SizedBox(height: listStyle.rowSpacing.toDouble()),
        itemBuilder: (context, index) => builder(context, items[index]),
      );
    }

    return Wrap(
      spacing: 8 + listStyle.rowSpacing.toDouble(),
      runSpacing: 8 + listStyle.rowSpacing.toDouble(),
      children: [for (final item in items) builder(context, item)],
    );
  }
}

class _ThemeUiPlaylists extends HookConsumerWidget {
  const _ThemeUiPlaylists(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = ThemeUiHostWidgets.boolProp(props['compact']);
    final showSearch =
        ThemeUiHostWidgets.boolProp(props['showSearch'], fallback: true);
    final showCreate =
        ThemeUiHostWidgets.boolProp(props['showCreate'], fallback: true);
    final limit = ThemeUiHostWidgets.intProp(
      props['limit'],
      min: 1,
      max: 200,
      fallback: 50,
    );
    final filter = ThemeUiHostWidgets.enumProp(
      props['filter'],
      values: _playlistFilters,
      fallback: 'all',
    );
    final horizontal = ThemeUiHostWidgets.enumProp(
          props['direction'],
          values: _directions,
          fallback: 'vertical',
        ) ==
        'horizontal';

    // The row chrome belongs to the theme: the same host widget draws the
    // expanded sidebar rows and the collapsed rail's cover-only rows, and
    // the props decide which. The host does not second-guess the theme
    // with a collapse check of its own.
    final rowPolicy = collectionRowPolicyFromProps(props);
    final listStyle = collectionListStyleFromProps(props);

    // The sidebar pin list is a preference; every other target is a theme pin.
    final pinTarget = ThemeUiHostWidgets.stringProp(props['pinTarget']);
    final pinnedIds = pinTarget == null || pinTarget == 'sidebar'
        ? ref.watch(
            userPreferencesProvider.select((prefs) => prefs.pinnedPlaylistIds),
          )
        : ref.watch(
            themePinsProvider.select(
              (pins) => pins[pinTarget] ?? const <String>[],
            ),
          );

    final saved =
        ref.watch(metadataPluginSavedPlaylistsProvider).asData?.value.items ??
            const <SpotubeSimplePlaylistObject>[];
    // A mirrored playlist is a local copy of one the plugin already lists; the
    // plugin's entry wins so a rename on the service is not shadowed.
    final mirrored = ref.watch(mirroredPlaylistsProvider).asData?.value ??
        const <SpotubeSimplePlaylistObject>[];
    final me = ref.watch(metadataPluginUserProvider).asData?.value;
    // The synthetic "Liked Songs" entry is backed by the metadata plugin's
    // savedTracks, so it is real content (not a placeholder) and plays through
    // the same path as every other playlist.
    final likedPlaylist = resolveLikedTracksPlaylist(
      name: context.l10n.liked_tracks,
      description: context.l10n.liked_tracks_description,
      me: me,
      authenticated: me != null,
    );
    final all = <String, SpotubeSimplePlaylistObject>{
      if (likedPlaylist != null) likedTracksPlaylistId: likedPlaylist,
      for (final playlist in mirrored) playlist.id: playlist,
      for (final playlist in saved) playlist.id: playlist,
    }.values.toList();

    final query = useState('');
    final searchController = useTextEditingController();
    final items = themeUiSelectPlaylists(
      all: all,
      pinnedIds: pinnedIds,
      filter: filter,
      query: query.value,
      limit: limit,
    );
    if (items.isEmpty && !showSearch && !showCreate) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch || showCreate)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (showSearch)
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      placeholder: Text(context.l10n.search),
                      onChanged: (value) => query.value = value,
                      features: [
                        InputFeature.leading(
                          Icon(
                            SpotubeIcons.search,
                            size: 16,
                            color: context.theme.colorScheme.mutedForeground,
                          ),
                        ),
                        InputFeature.trailing(
                          ListenableBuilder(
                            listenable: searchController,
                            builder: (context, _) {
                              if (searchController.text.isEmpty) {
                                return const SizedBox.square(
                                  dimension: 20,
                                );
                              }
                              return IconButton.ghost(
                                size: const ButtonSize(.6),
                                icon: const Icon(
                                  SpotubeIcons.close,
                                  size: 16,
                                ),
                                onPressed: () {
                                  searchController.clear();
                                  query.value = '';
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (showCreate) const PlaylistCreateDialogButton(),
              ],
            ),
          ),
        if (items.isNotEmpty)
          _ThemeUiCollection(
            items: items,
            compact: compact,
            horizontal: horizontal,
            hasArtist: false,
            listStyle: listStyle,
            builder: (context, item) {
              final playlist = item as SpotubeSimplePlaylistObject;
              // PlaylistCard wraps itself in PlaylistContextMenu — no
              // HostItemContextMenu here or the richer card menu is shadowed.
              return compact
                  ? PlaylistCard.tile(playlist, rowPolicy: rowPolicy)
                  : PlaylistCard(playlist, rowPolicy: rowPolicy);
            },
          ),
      ],
    );
  }
}

class _ThemeUiAlbums extends ConsumerWidget {
  const _ThemeUiAlbums(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums =
        ref.watch(metadataPluginSavedAlbumsProvider).asData?.value.items ??
            const <SpotubeSimpleAlbumObject>[];
    if (albums.isEmpty) return const SizedBox.shrink();

    final compact = ThemeUiHostWidgets.boolProp(props['compact']);
    final rowPolicy = collectionRowPolicyFromProps(props);
    final listStyle = collectionListStyleFromProps(props);
    return _ThemeUiCollection(
      items: albums,
      compact: compact,
      horizontal: false,
      hasArtist: false,
      listStyle: listStyle,
      builder: (context, item) {
        final album = item as SpotubeSimpleAlbumObject;
        // AlbumCard self-wraps in HostItemContextMenu — no wrap here or the
        // menu would be nested twice.
        return compact
            ? AlbumCard.tile(album, rowPolicy: rowPolicy)
            : AlbumCard(album, rowPolicy: rowPolicy);
      },
    );
  }
}

class _ThemeUiArtists extends ConsumerWidget {
  const _ThemeUiArtists(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists =
        ref.watch(metadataPluginSavedArtistsProvider).asData?.value.items ??
            const <SpotubeFullArtistObject>[];
    if (artists.isEmpty) return const SizedBox.shrink();

    final compact = ThemeUiHostWidgets.boolProp(props['compact']);
    final rowPolicy = collectionRowPolicyFromProps(props);
    final listStyle = collectionListStyleFromProps(props);
    if (!compact) {
      return _ThemeUiCollection(
        items: artists,
        compact: false,
        horizontal: false,
        hasArtist: true,
        listStyle: listStyle,
        builder: (context, item) => ArtistCard(item as SpotubeFullArtistObject),
      );
    }

    // The host has no compact artist presentation of its own — the card is a
    // round avatar in a bounded cell — so a compact row borrows the shared
    // tile and keeps only the navigation the card does. The transport buttons
    // stay disabled because an artist is not something you queue.
    return _ThemeUiCollection(
      items: artists,
      compact: true,
      horizontal: false,
      hasArtist: true,
      listStyle: listStyle,
      builder: (context, item) {
        final artist = item as SpotubeFullArtistObject;
        // Compact rows bypass ArtistCard, so the menu is attached here.
        return HostItemContextMenu(
          item: artist,
          child: PlaybuttonTile(
            title: artist.name,
            description: artist.genres?.join(', '),
            imageUrl:
                artist.images.asUrlString(placeholder: ImagePlaceholder.artist),
            isPlaying: false,
            isLoading: false,
            rowPolicy: rowPolicy,
            onTap: () => context.navigateTo(ArtistRoute(artistId: artist.id)),
          ),
        );
      },
    );
  }
}

/// Transport controls, with the seek line and volume as the document asks.
///
/// `PlayerControls` draws its own progress line when it is not compact, so the
/// host always asks it to stay out of that and renders [PlayerProgress] itself —
/// otherwise `showProgress: false` would still show a bar on desktop.
class _ThemeUiPlayerControls extends ConsumerWidget {
  const _ThemeUiPlayerControls(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = ThemeUiHostWidgets.boolProp(props['compact']);
    final showProgress =
        ThemeUiHostWidgets.boolProp(props['showProgress'], fallback: true);
    final showVolume =
        ThemeUiHostWidgets.boolProp(props['showVolume'], fallback: true);
    final volume = ref.watch(volumeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerControls(compact: compact, progressInline: false),
        if (showProgress) const PlayerProgress(inline: true),
        if (showVolume)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: VolumeSlider(
              fullWidth: true,
              value: volume,
              onChanged: (value) =>
                  ref.read(volumeProvider.notifier).setVolume(value),
            ),
          ),
      ],
    );
  }
}

/// The live queue.
///
/// [PlayerQueue] builds a `Column` with an `Expanded` list, so it needs a
/// bounded height: a slot that gives one keeps it, and an unbounded scroll view
/// gets a fixed window instead of an unbounded-height assertion.
class _ThemeUiQueue extends ConsumerWidget {
  const _ThemeUiQueue(this.props);

  final Map<String, dynamic> props;

  static const _fallbackHeight = 320.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(audioPlayerProvider);
    if (playlist.tracks.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(audioPlayerProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.hasBoundedHeight
              ? constraints.maxHeight
              : _fallbackHeight,
          child: PlayerQueue.fromAudioPlayerNotifier(
            floating: false,
            playlist: playlist,
            notifier: notifier,
          ),
        );
      },
    );
  }
}

/// One EQ band, driven through the same draft/commit pair the Settings page
/// uses so a drag is one filter-chain rebuild rather than one per pixel.
class _ThemeUiBandSlider extends StatelessWidget {
  const _ThemeUiBandSlider({
    required this.label,
    required this.value,
    required this.showValue,
    required this.onChanged,
    required this.onCommit,
  });

  final String? label;
  final double value;
  final bool showValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (label != null)
            SizedBox(
              width: 44,
              child: Text(
                label!,
                style: theme.typography.xSmall.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
          Expanded(
            child: Slider(
              min: kEqualizerMinGain,
              max: kEqualizerMaxGain,
              divisions:
                  ((kEqualizerMaxGain - kEqualizerMinGain) / kEqualizerGainStep)
                      .round(),
              value: SliderValue.single(value),
              onChanged: (next) => onChanged(next.value),
              onChangeEnd: (next) => onCommit(next.value),
            ),
          ),
          if (showValue)
            SizedBox(
              width: 56,
              child: Text(
                context.l10n.audio_gain_db(value.toStringAsFixed(1)),
                textAlign: TextAlign.end,
                style: theme.typography.xSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeUiBass extends HookConsumerWidget {
  const _ThemeUiBass(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = ThemeUiHostWidgets.boolProp(props['compact']);
    final gains = EqualizerSettings.normalizeGains(
      ref.watch(userPreferencesProvider.select((p) => p.equalizerGains)),
    );
    final notifier = ref.read(userPreferencesProvider.notifier);

    // The persisted list arrives as a new object on every preference write;
    // hold a draft so the thumb does not jump back mid-drag.
    final draft = useState<double?>(null);
    final value = draft.value ?? gains.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              context.l10n.audio_bass,
              style: Theme.of(context).typography.small,
            ),
          ),
        _ThemeUiBandSlider(
          label: null,
          value: value,
          showValue: true,
          onChanged: (next) => draft.value = next,
          onCommit: (next) {
            draft.value = null;
            notifier.setEqualizerGain(0, next);
          },
        ),
      ],
    );
  }
}

class _ThemeUiEqualizer extends HookConsumerWidget {
  const _ThemeUiEqualizer(this.props);

  final Map<String, dynamic> props;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ThemeUiHostWidgets.intProp(
      props['bands'],
      min: 1,
      max: kEqualizerBandCount,
      fallback: kEqualizerBandCount,
    );
    final persisted = EqualizerSettings.normalizeGains(
      ref.watch(userPreferencesProvider.select((p) => p.equalizerGains)),
    );
    final notifier = ref.read(userPreferencesProvider.notifier);

    final draft = useState<List<double>>(persisted);
    useEffect(() {
      draft.value = persisted;
      return null;
    }, [persisted]);

    void update(int index, double value) {
      final next = [...draft.value];
      next[index] = value;
      draft.value = next;
    }

    void commit(int index, double value) {
      final next = [...draft.value];
      next[index] = value;
      draft.value = next;
      // One write for the whole set: the effects listener rebuilds the mpv
      // filter chain once, not once per band.
      notifier.setEqualizerGains(next);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < bands; index++)
          _ThemeUiBandSlider(
            label: kEqualizerBandLabels[index],
            value: draft.value[index],
            showValue: false,
            onChanged: (value) => update(index, value),
            onCommit: (value) => commit(index, value),
          ),
      ],
    );
  }
}

class _ThemeUiCrossfade extends ConsumerWidget {
  const _ThemeUiCrossfade();

  static const _maxSeconds = 15.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(crossfadeProvider);
    final notifier = ref.read(crossfadeProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.audio_crossfade,
                style: theme.typography.small,
              ),
            ),
            Text(
              context.l10n.audio_seconds(seconds.toStringAsFixed(0)),
              style: theme.typography.xSmall.copyWith(
                color: theme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
        Slider(
          min: 0,
          max: _maxSeconds,
          divisions: _maxSeconds.round(),
          value: SliderValue.single(seconds.clamp(0, _maxSeconds)),
          onChanged: (value) => notifier.setSeconds(value.value),
        ),
      ],
    );
  }
}

class _ThemeUiSleepTimer extends ConsumerWidget {
  const _ThemeUiSleepTimer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.sleep_timer,
            style: theme.typography.small,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (remaining != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              _formatRemaining(remaining),
              style: theme.typography.xSmall.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (remaining != null)
          IconButton.ghost(
            icon: const Icon(SpotubeIcons.close, size: 16),
            onPressed: notifier.cancelSleepTimer,
          ),
        AdaptivePopSheetList<Duration>(
          tooltip: l10n.sleep_timer,
          icon: Icon(
            SpotubeIcons.timer,
            color: remaining == null ? null : theme.colorScheme.primary,
          ),
          onSelected: notifier.setSleepTimer,
          items: (context) => [
            AdaptiveMenuButton(
              value: const Duration(minutes: 15),
              child: Text(l10n.mins(15)),
            ),
            AdaptiveMenuButton(
              value: const Duration(minutes: 30),
              child: Text(l10n.mins(30)),
            ),
            AdaptiveMenuButton(
              value: const Duration(hours: 1),
              child: Text(l10n.hour(1)),
            ),
            AdaptiveMenuButton(
              value: const Duration(hours: 2),
              child: Text(l10n.hour(2)),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatRemaining(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

/// The host search field, or a scoped query box when the widget names a scope.
///
/// Without a scope the field is the app's own: focus, recents and the
/// suggestion portal all come with it. With one it publishes to
/// `search.<scope>.query` instead, which is how a theme keeps two fields (a
/// sidebar filter and a page search) from overwriting each other.
class _ThemeUiSearchField extends ConsumerWidget {
  const _ThemeUiSearchField(this.props, this.runtime);

  final Map<String, dynamic> props;
  final ThemeUiRuntime runtime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ThemeUiHostWidgets.stringProp(props['placeholder']);
    final scope = ThemeUiHostWidgets.stringProp(props['scope'], maxLength: 32);
    final field = scope == null || !_queryScopePattern.hasMatch(scope)
        ? HomeSearchBar(
            compact: true,
            placeholder: placeholder,
            runtime: runtime,
          )
        : _ThemeUiScopedSearch(scope: scope, placeholder: placeholder);
    // Both fields are a Row+Expanded: inside a theme `row` they can receive
    // unbounded width, which leaves the Row unlaid-out. Pin a compact default
    // only when the parent hands over none — a bounded host is untouched.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedWidth) return field;
        return SizedBox(width: 160, child: field);
      },
    );
  }
}

class _ThemeUiScopedSearch extends ConsumerStatefulWidget {
  const _ThemeUiScopedSearch({required this.scope, this.placeholder});

  final String scope;
  final String? placeholder;

  @override
  ConsumerState<_ThemeUiScopedSearch> createState() =>
      _ThemeUiScopedSearchState();
}

class _ThemeUiScopedSearchState extends ConsumerState<_ThemeUiScopedSearch> {
  static const _debounce = Duration(milliseconds: 300);

  late final TextEditingController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(themeUiQueryProvider)[widget.scope] ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _ThemeUiScopedSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _controller.text = ref.read(themeUiQueryProvider)[widget.scope] ?? '';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _publish(String value) {
    ref.read(themeUiQueryProvider.notifier).set(widget.scope, value);
  }

  void _onChanged(String value) {
    _timer?.cancel();
    // Submitting is a deliberate end of an edit, so it skips the wait.
    _timer = Timer(_debounce, () => _publish(value));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(SpotubeIcons.search, size: 16),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            placeholder:
                widget.placeholder == null ? null : Text(widget.placeholder!),
            onChanged: _onChanged,
            onSubmitted: (value) {
              _timer?.cancel();
              _publish(value);
            },
          ),
        ),
        if (_controller.text.isNotEmpty)
          IconButton.ghost(
            icon: const Icon(SpotubeIcons.close, size: 16),
            onPressed: () {
              _timer?.cancel();
              _controller.clear();
              _publish('');
              setState(() {});
            },
          ),
      ],
    );
  }
}

/// The theme's own settings, mounted inline.
///
/// Rendering the settings document here rather than opening a dialog is what
/// lets a theme put its controls inside its own layout. It cannot nest: a
/// `theme.settings` inside a settings document would re-render itself.
class _ThemeUiSettings extends ConsumerWidget {
  const _ThemeUiSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ThemeUiSettingsScope.isInside(context)) {
      return const SizedBox.shrink();
    }
    // `showSettings()` is an async plugin call, so the first frame has no
    // document yet. Saying "this theme has no settings" then would be a lie the
    // widget takes back a frame later.
    final document = ref.watch(pluginThemeSettingsProvider);
    final ui = document.asData?.value;
    final children = ui?.slots['settings.content']?.children;
    if (document.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ui == null || children == null || children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(context.l10n.theme_settings_empty),
        ),
      );
    }
    return ThemeSettingsBody(ui: ui);
  }
}
