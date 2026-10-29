import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/radio/plugin_directory_adapter.dart';
import 'package:spotube/provider/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/radio/radio_directory_provider.dart';

/// Boot (or reuse) the Hetu VM behind [config] so its `radio` endpoint can be
/// queried. Shares [pluginCacheProvider] with the audio-source path so a plugin
/// update evicts it, and a transient `MetadataPlugin.create` failure is dropped
/// rather than memoized as a permanently broken directory.
Future<MetadataPlugin> _radioPluginVm(Ref ref, PluginConfiguration config) {
  final youtubeEngine = ref.read(youtubeEngineProvider);
  return ref.read(pluginCacheProvider).getOrCreate(
    '${config.slug}@${config.version}:radio',
    () async {
      final byteCode = await ref
          .read(metadataPluginsProvider.notifier)
          .getPluginByteCode(config);
      return MetadataPlugin.create(youtubeEngine, config, byteCode);
    },
  );
}

/// Radio directories derived from the installed plugins, default first and then
/// every other plugin carrying the [PluginAbilities.radio] ability — the same
/// ordering the audio-source resolver uses, so "set as default" and fallback
/// behave identically across the two subsystems.
///
/// Each adapter boots its VM lazily, so this loop costs nothing until the
/// fan-out actually reaches a directory.
List<RadioDirectoryProvider> radioProvidersFor(
  Ref ref,
  MetadataPluginState state,
) {
  final defaultConfig = state.defaultRadioPluginConfig;
  final ordered = <PluginConfiguration>[
    if (defaultConfig != null &&
        defaultConfig.abilities.contains(PluginAbilities.radio))
      defaultConfig,
    ...state.plugins.where(
      (p) =>
          p.abilities.contains(PluginAbilities.radio) &&
          (defaultConfig == null || p.slug != defaultConfig.slug),
    ),
  ];
  return [
    for (final config in ordered)
      MetadataPluginRadioDirectoryProvider(
        id: config.name,
        plugin: () => _radioPluginVm(ref, config),
      ),
  ];
}

/// Identifies the installed radio directories.
///
/// The plugin state also carries auth and progress updates, and every one of
/// those emissions used to invalidate the browse caches - so a perfectly good
/// station page was thrown away (and refetched) whenever the plugin reported
/// something unrelated. This is the part of the state that actually decides
/// what the browse can ask: the default radio plugin and the set of
/// radio-capable plugins.
String _radioDirectorySignature(MetadataPluginState state) {
  return [
    state.defaultRadioPluginConfig?.slug ?? '',
    for (final plugin in state.plugins)
      if (plugin.abilities.contains(PluginAbilities.radio))
        '${plugin.slug}@${plugin.version}',
  ].join('|');
}

/// Keeps the process-wide [radioProviders] registry pointed at the installed
/// radio plugins, so the whole Radio feature runs on the real Hetu plugin
/// system (the old hard-coded in-app directory is gone).
///
/// Wiring the fan-out through a listener on plugin *state* here — rather than
/// having the browse/search notifiers read [metadataPluginsProvider] directly —
/// is what lets the radio provider tests run in a bare [ProviderContainer]: they
/// never mount this provider, so [radioProviders] stays exactly what a test
/// injects, and the notifiers keep serving it. In the app it is watched once
/// from the root.
///
/// After reseeding it invalidates the station/tag/country providers: a page
/// opened before plugin state finished loading would otherwise sit on the empty
/// first answer, since a plain list is not observable. Only the plugin-managed
/// adapters are swapped out, so manually registered providers survive a sync.
///
/// The invalidation is scoped to a change in the *set of radio directories*:
/// the plugin state also reports auth and progress, and dropping the browse
/// caches on those meant every visit to the Radio page refetched everything.
///
/// Yields a generation counter rather than `void` on purpose.
/// [radioProviders] is a plain mutable list, so a consumer cannot `watch` it;
/// this provider is the announcement channel, and a `Provider<void>` would be
/// useless as one — its value is always `null`, so Riverpod would never notify
/// a dependent that it changed, and the registry would never be re-read.
final radioPluginDirectorySyncProvider = Provider<int>((ref) {
  var generation = 0;
  String? signature;
  ref.listen<AsyncValue<MetadataPluginState>>(
    metadataPluginsProvider,
    (_, next) {
      final state = next.valueOrNull;
      if (state == null) {
        // The plugin state is not known (yet), so the plugin-managed adapters
        // cannot be resolved and come out of the registry. The browse caches
        // are left alone: they were filled by directories that are still
        // installed, and dropping them would mean a refetch for nothing.
        radioProviders.removeWhere(
          (p) => p is MetadataPluginRadioDirectoryProvider,
        );
        return;
      }

      final nextSignature = _radioDirectorySignature(state);
      final directoriesChanged = nextSignature != signature;
      signature = nextSignature;

      radioProviders.removeWhere(
        (p) => p is MetadataPluginRadioDirectoryProvider,
      );
      radioProviders.addAll(radioProvidersFor(ref, state));

      if (!directoriesChanged) return;

      ref.invalidate(radioStationsProvider);
      ref.invalidate(radioTagsProvider);
      ref.invalidate(radioCountriesProvider);
      generation++;
    },
    fireImmediately: true,
  );
  return generation;
});

/// Observable view of the process-global [radioProviders] registry.
///
/// [radioProviders] is a plain mutable list, so nothing tells a consumer that
/// the installed plugin set changed. A provider that has to fall back to the
/// network must watch this or it will keep the answer it computed against an
/// empty registry — which, for a sidebar pin, means staying null for the rest
/// of the session.
///
/// Handed out as a fresh unmodifiable copy on every rebuild, deliberately:
/// returning the global itself would compare equal to itself, so Riverpod would
/// see no change and the dependents this provider exists to notify would never
/// rebuild.
final radioDirectoryRegistryProvider = Provider<List<RadioDirectoryProvider>>(
  (ref) {
    ref.watch(radioPluginDirectorySyncProvider);
    return List.unmodifiable(radioProviders);
  },
);

/// The browse axis for the station list: a tag, a country, a free-text search,
/// or none (the popular default). A record so equality is field-wise — the
/// family keys one instance per distinct combination, and re-typing a search
/// that lands back on a previous value reuses that page instead of refetching.
typedef RadioStationsQuery = ({String? tag, String? country, String? search});

const _pageLimit = 20;

/// How long a fetched browse answer survives the page that asked for it.
///
/// The Radio page is torn down every time the user leaves the tab, and an
/// auto-disposed provider takes its answer with it - so every visit refetched
/// the directory (five requests: three station pages plus the tag and country
/// lists). Holding the answer for a few minutes makes a tab switch instant
/// while still letting a long-idle app see fresh data.
const _radioCacheFor = Duration(minutes: 5);

/// One page of [RadioStation]s for a [RadioStationsQuery], with [fetchMore]
/// appending subsequent pages.
///
/// Deliberately not the music [PaginatedAsyncNotifier]: that family is welded to
/// [MetadataPluginMixin] (Spotify rate-limit gate, plugin resolution, snapshot
/// persistence) which has no meaning for a keyless public directory. The paging
/// contract is small enough to keep here without inheriting that coupling.
class RadioStationsNotifier extends AutoDisposeFamilyAsyncNotifier<
    SpotubePaginationResponseObject<RadioStation>, RadioStationsQuery> {
  bool _isFetchingMore = false;

  @override
  Future<SpotubePaginationResponseObject<RadioStation>> build(
    RadioStationsQuery arg,
  ) async {
    ref.cacheFor(_radioCacheFor);
    return fetchStationsAcrossProviders(
      (provider) => provider.stations(
        tag: arg.tag,
        country: arg.country,
        search: arg.search,
        offset: 0,
        limit: _pageLimit,
      ),
    );
  }

  /// Appends the next page, guarding against the scroll edge and a visibility
  /// callback firing at once and interleaving two partial pages.
  Future<void> fetchMore() async {
    final current = state.value;
    if (_isFetchingMore || current == null || !current.hasMore) return;

    _isFetchingMore = true;
    final previous = current;
    try {
      final next = await fetchStationsAcrossProviders(
        (provider) => provider.stations(
          tag: arg.tag,
          country: arg.country,
          search: arg.search,
          offset: current.nextOffset ?? current.items.length,
          limit: current.limit == 0 ? _pageLimit : current.limit,
        ),
      );

      final seen = previous.items.map((s) => s.id).toSet();
      state = AsyncData(
        next.copyWith(
          items: [
            ...previous.items,
            ...next.items.where((s) => seen.add(s.id)),
          ],
        ),
      );
    } catch (e, stack) {
      // Keep the page already on screen; a failed top-up is not a reason to
      // blank out stations the user is mid-way through browsing.
      state = AsyncData(previous);
      // Deliberately logged, not rethrown: the real caller is PlaybuttonView's
      // `final VoidCallback onRequestMore`, which discards the returned future.
      // A throw here would surface as an unhandled async error with no error
      // state and paging would simply stop for the rest of the session.
      AppLogger.reportError(e, stack, 'radio stations page $arg');
    } finally {
      _isFetchingMore = false;
    }
  }
}

final radioStationsProvider = AsyncNotifierProvider.autoDispose.family<
    RadioStationsNotifier,
    SpotubePaginationResponseObject<RadioStation>,
    RadioStationsQuery>(
  RadioStationsNotifier.new,
);

/// Distinct tags for the browse-by-tag rail, most-used first.
final radioTagsProvider =
    FutureProvider.autoDispose<List<RadioTag>>((ref) async {
  // Same reasoning as the station pages: the list is fetched from the
  // directory, and the rail is rebuilt every time the Radio page is opened.
  ref.cacheFor(_radioCacheFor);
  // Snapshotted: radioProviders is a mutable process-global that the plugin
  // sync rewrites in place, and this loop awaits inside its body.
  for (final provider in List.of(radioProviders)) {
    try {
      final tags = await provider.tags();
      if (tags.isNotEmpty) return tags;
    } catch (e, stack) {
      // A dead directory should not hide the one that answers.
      AppLogger.reportError(e, stack, 'radio tags ${provider.id}');
      continue;
    }
  }
  return const [];
});

/// Distinct countries for the browse-by-country rail.
final radioCountriesProvider =
    FutureProvider.autoDispose<List<RadioCountry>>((ref) async {
  ref.cacheFor(_radioCacheFor);
  for (final provider in List.of(radioProviders)) {
    try {
      final countries = await provider.countries();
      if (countries.isNotEmpty) return countries;
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'radio countries ${provider.id}');
      continue;
    }
  }
  return const [];
});
