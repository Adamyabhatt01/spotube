import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/home/home_search_bar.dart';
import 'package:spotube/modules/home/home_search_results.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/pages/radio/station_search.dart';
import 'package:spotube/pages/search/search_landing.dart';

/// Which catalog the Search page queries. Music is the default; radio
/// restores mobile station search now that the Radio page hides its own
/// row wherever the bottom bar is visible.
enum SearchScope { music, radio }

/// Dedicated search destination behind the mobile bottom-bar Search tab.
///
/// Reuses the Browse search components ([HomeSearchBar] + [HomeSearchResults])
/// so mobile search and desktop inline search can never diverge: same field,
/// same suggestions, same shared [searchTermStateProvider].
///
/// Deliberately no autofocus on entry: focusing would pop the keyboard over
/// the landing on every visit, and the open suggestion panel's fullscreen
/// barrier would absorb the first tap on the scope switcher below.
@RoutePage()
class SearchPage extends HookConsumerWidget {
  static const name = "search";

  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = useState(SearchScope.music);

    final searching =
        ref.watch(searchTermStateProvider.select((s) => s.trim().isNotEmpty));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact, scrollable scope row: 12px gutters instead of the old
          // 28px desktop padding, and translated labels. It stays above the
          // active scope so switching never moves the thing you tapped.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  _ScopeChip(
                    key: const ValueKey('searchScopeMusic'),
                    label: context.l10n.music,
                    selected: scope.value == SearchScope.music,
                    onPressed: () => scope.value = SearchScope.music,
                  ),
                  _ScopeChip(
                    key: const ValueKey('searchScopeRadio'),
                    // Radio is a proper noun in the rest of the app (sidebar,
                    // plugin abilities), so it stays untranslated there too.
                    label: 'Radio',
                    selected: scope.value == SearchScope.radio,
                    onPressed: () => scope.value = SearchScope.radio,
                  ),
                ],
              ),
            ),
          ),
          if (scope.value == SearchScope.music) const HomeSearchBar(),
          Expanded(
            child: scope.value == SearchScope.music
                ? (searching
                    // The field is pinned above; only the results scroll.
                    ? const HomeSearchResults()
                    : const SearchLandingMusic())
                : const _SearchRadioScope(),
          ),
        ],
      ),
    );
  }
}

/// The radio scope: station search field, live results and browse rails via
/// the shared [useStationSearchSlivers] hook, so it can never diverge from
/// the Radio page.
///
/// Mounted only while the scope is active, so the radio hook fires no
/// directory requests while the user only searches music. The tradeoff is
/// the radio field resets on scope switch, while the music term survives
/// via the shared provider.
class _SearchRadioScope extends HookConsumerWidget {
  const _SearchRadioScope();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTag = useState<String?>(null);
    final selectedCountry = useState<String?>(null);
    final controller = useScrollController();

    return CustomScrollView(
      controller: controller,
      slivers: [
        ...useStationSearchSlivers(
          context,
          ref,
          controller: controller,
          // The Search page already has the Music/Radio scope switcher, so the
          // Radio page's Home shortcut is redundant here. History is replaced
          // by the station recommendation rails below; both stay untouched on
          // the actual Radio page.
          showMusicShortcut: false,
          showRecentRail: false,
          selectedTag: selectedTag.value,
          selectedCountry: selectedCountry.value,
          onTag: (tag) {
            selectedCountry.value = null;
            selectedTag.value = tag;
          },
          onCountry: (country) {
            selectedTag.value = null;
            selectedCountry.value = country;
          },
        ),
        const RadioAttributionSliver(),
        const SliverSafeArea(sliver: SliverGap(24)),
      ],
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return selected
        ? Button.secondary(onPressed: onPressed, child: Text(label))
        : Button.outline(onPressed: onPressed, child: Text(label));
  }
}
