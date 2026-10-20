import 'dart:async';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/perf_counters.dart';

/// A source that can list and search internet-radio stations.
///
/// Mirrors the lyrics subsystem ([LyricsProvider]): providers are tried in
/// registry order and the first non-empty answer wins, with per-provider
/// failures isolated so one broken directory cannot block the rest.
///
/// Concrete directories are Hetu plugins: [MetadataPluginRadioDirectoryProvider]
/// adapts an installed plugin's `radio` endpoint to this interface, so the
/// browse/search/favorites fan-out is unchanged by a directory becoming a
/// plugin. Adding the `stations`/`tags`/`countries` methods to the music-only
/// [MetadataPlugin] mixin set instead would have forced a poor abstraction; an
/// additive `radio` ability plus this adapter keeps both concerns clean.
abstract interface class RadioDirectoryProvider {
  /// Stable identifier for logging, favorites namespacing and diagnostics.
  String get id;

  /// The page shape reuses Spotube's existing pagination envelope.
  Future<SpotubePaginationResponseObject<RadioStation>> stations({
    String? tag,
    String? country,
    String? search,
    int offset = 0,
    int limit = 20,
  });

  /// Resolves a single station by its provider-scoped [id], or null on a miss.
  /// Favorites store a snapshot of the last-known station but directories
  /// rotate `streamUrl`s, so play-from-favorite re-resolves through this before
  /// falling back to the stored URL.
  Future<RadioStation?> byId(String id);

  /// Distinct tags for the browse-by-tag entry view, most-used first.
  Future<List<RadioTag>> tags({int limit = 50});

  /// Distinct countries for the browse-by-country entry view.
  Future<List<RadioCountry>> countries({int limit = 100});
}

/// The live set of radio directory providers, in priority order.
///
/// [radioPluginDirectorySyncProvider] keeps it pointed at the installed radio
/// plugins (default first); tests inject fakes directly. Kept as a mutable
/// process-wide list so both the browse/search notifiers and the favorites
/// re-resolution read one registry without coupling to plugin state.
final List<RadioDirectoryProvider> radioProviders = [];

/// Wall-clock ceiling for one directory provider inside the failover walk.
/// Matches [engineCallBudget]/[metadataRequestBudget] (15 s): a stalled Hetu
/// directory must not head-of-line-block the providers behind it. Measured:
/// a hanging first provider blocked a healthy second one indefinitely
/// (see `test/perf_audit_measure_test.dart`); with this budget the walk
/// skips the stalled provider and serves the next hit.
const radioProviderBudget = Duration(seconds: 15);

/// Runs [request] against each registered provider in priority order,
/// returning the first page that carries stations.
///
/// A provider that returns an empty result is a miss and the next is tried. A
/// provider that *throws* is isolated (logged) and the next is tried — but if
/// every provider that was attempted threw, the last error is rethrown so the
/// UI can show a real failure instead of a misleading "no stations". With no
/// providers registered the empty page is returned unchanged.
Future<SpotubePaginationResponseObject<RadioStation>>
    fetchStationsAcrossProviders(
  Future<SpotubePaginationResponseObject<RadioStation>> Function(
    RadioDirectoryProvider provider,
  )
      request,
) async {
  Object? lastError;
  StackTrace? lastStack;

  // Snapshotted, not iterated live: radioProviders is a mutable process-global
  // that radioPluginDirectorySyncProvider rewrites in place (removeWhere +
  // addAll) from a plugins_table listener. This loop awaits inside its body, so
  // a sync landing between two providers steps the iterator of a list that
  // changed under it and throws ConcurrentModificationError — which escapes the
  // per-provider catch below, since that only wraps the request call.
  for (final provider in List.of(radioProviders)) {
    try {
      final page =
          await request(provider).timeout(radioProviderBudget);
      if (page.items.isNotEmpty) return page;
    } on TimeoutException catch (e, stack) {
      // A stall is a miss for this provider, never a global failure: the
      // next directory still gets its chance. Recorded so a permanently
      // stalled directory is discoverable in profile/debug counters.
      PerfCounters.note('radio.provider.timeout');
      lastError = e;
      lastStack = stack;
      AppLogger.reportError(e, stack, 'radio provider ${provider.id}');
    } catch (e, stack) {
      lastError = e;
      lastStack = stack;
      AppLogger.reportError(e, stack, 'radio provider ${provider.id}');
    }
  }

  if (lastError != null) {
    Error.throwWithStackTrace(lastError, lastStack!);
  }
  return SpotubePaginationResponseObject<RadioStation>(
    limit: 0,
    nextOffset: null,
    total: 0,
    hasMore: false,
    items: const [],
  );
}
