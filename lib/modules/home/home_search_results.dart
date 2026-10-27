import 'package:collection/collection.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/string.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/pages/search/tabs/albums.dart';
import 'package:spotube/pages/search/tabs/all.dart';
import 'package:spotube/pages/search/tabs/artists.dart';
import 'package:spotube/pages/search/tabs/playlists.dart';
import 'package:spotube/pages/search/tabs/tracks.dart';
import 'package:spotube/provider/metadata_plugin/search/albums.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/provider/metadata_plugin/search/artists.dart';
import 'package:spotube/provider/metadata_plugin/search/playlists.dart';
import 'package:spotube/provider/metadata_plugin/search/tracks.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

/// Search result tab, as named by the metadata plugin's chip list.
///
/// The plugin contract is bare `List<String>`; mapping it to this enum at
/// the boundary turns a typo or a plugin-side rename into an explicit
/// unknown (which renders the All tab) instead of a silent content/chip
/// mismatch. Unknown chips can never read as selected.
enum SearchChip {
  all,
  tracks,
  albums,
  artists,
  playlists;

  static SearchChip? fromString(String chip) {
    for (final value in SearchChip.values) {
      if (value.name == chip) return value;
    }
    return null;
  }
}

/// Search results hosted inline in Browse. Extracted from the deleted
/// `SearchPage`: same chips row, same tab switch, same error states — only
/// the host moved.
///
/// Renders a plain box child (`Column` of chips + `Expanded` tab); `HomePage`
/// mounts it in a `SliverFillRemaining` so the active tab keeps its own
/// internal scroll view with a bounded height.
class HomeSearchResults extends HookConsumerWidget {
  const HomeSearchResults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchChipSnapshot = ref.watch(metadataPluginSearchChipsProvider);
    final selectedChip = useState<SearchChip>(
      searchChipSnapshot.asData?.value
              .map(SearchChip.fromString)
              .nonNulls
              .firstOrNull ??
          SearchChip.all,
    );

    ref.listen(
      metadataPluginSearchChipsProvider,
      (previous, next) {
        // Reset only when the current selection is no longer offered (plugin
        // swap, cache bust); a re-emission of the same list must not bounce
        // the user back to All mid-scroll.
        final nextChips = next.asData?.value;
        if (nextChips == null) return;
        final mapped = nextChips.map(SearchChip.fromString).nonNulls.toSet();
        if (!mapped.contains(selectedChip.value)) {
          selectedChip.value = mapped.firstOrNull ?? SearchChip.all;
        }
      },
    );

    if (searchChipSnapshot.error
        case MetadataPluginException(
          errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
          message: _
        )) {
      return const NoDefaultMetadataPlugin();
    }

    if (searchChipSnapshot.hasError) {
      return ErrorBox(
        error: searchChipSnapshot.error!,
        onRetry: () {
          ref.invalidate(metadataPluginSearchChipsProvider);
        },
      );
    }

    final term = ref.watch(searchTermStateProvider);
    final hasContent = themeUiSlotExists(ref, 'search.content');
    if (hasContent) {
      return ThemePageContent(
        slot: 'search.content',
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        bindings: {
          'search.query': term,
          'search.tracks': ref
                  .watch(metadataPluginSearchTracksProvider(term))
                  .asData
                  ?.value
                  .items ??
              const [],
          'search.albums': ref
                  .watch(metadataPluginSearchAlbumsProvider(term))
                  .asData
                  ?.value
                  .items ??
              const [],
          'search.artists': ref
                  .watch(metadataPluginSearchArtistsProvider(term))
                  .asData
                  ?.value
                  .items ??
              const [],
          'search.playlists': ref
                  .watch(metadataPluginSearchPlaylistsProvider(term))
                  .asData
                  ?.value
                  .items ??
              const [],
        },
        fallback: const SizedBox.shrink(),
      );
    }

    return Column(
      children: [
        // The chip row is wider than a phone once the plugin supplies all
        // five tabs; scrolling it here keeps every chip reachable instead of
        // clipping the last ones (or overflowing on desktop).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              // Back to Browse: clearing the term restores the Browse
              // sections (HomePage swaps on this state, no navigation).
              // Pinned in the chips row — outside the tab's scroll view —
              // so it never scrolls away like the search field's X does.
              IconButton.ghost(
                size: ButtonSize.small,
                icon: const Icon(SpotubeIcons.angleLeft),
                onPressed: () {
                  ref.read(searchTermStateProvider.notifier).state = "";
                },
              ),
              if (searchChipSnapshot.asData?.value != null)
                for (final chip in searchChipSnapshot.asData!.value)
                  // Unknown plugin chips render unselected and fall back to
                  // the All tab; they can never read as selected.
                  Builder(builder: (context) {
                    final mapped = SearchChip.fromString(chip);
                    return Chip(
                      style: selectedChip.value == mapped && mapped != null
                          ? ButtonVariance.primary.copyWith(
                              decoration: (context, states, value) {
                                return ButtonVariance.primary
                                    .decoration(context, states)
                                    .copyWithIfBoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          context.pillCornerRadius),
                                    );
                              },
                            )
                          : ButtonVariance.secondary.copyWith(
                              decoration: (context, states, value) {
                                return ButtonVariance.secondary
                                    .decoration(context, states)
                                    .copyWithIfBoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          context.pillCornerRadius),
                                    );
                              },
                            ),
                      child: Text(chip.capitalize()),
                      onPressed: () {
                        selectedChip.value = mapped ?? SearchChip.all;
                      },
                    );
                  }),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (selectedChip.value) {
              SearchChip.tracks => const SearchPageTracksTab(),
              SearchChip.albums => const SearchPageAlbumsTab(),
              SearchChip.artists => const SearchPageArtistsTab(),
              SearchChip.playlists => const SearchPagePlaylistsTab(),
              SearchChip.all => const SearchPageAllTab(),
            },
          ),
        ),
      ],
    );
  }
}
