import 'package:flutter/foundation.dart' hide Summary;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/services/wikipedia/wikipedia.dart';
import 'package:wikipedia_api/wikipedia_api.dart';

/// Keyed by identity + name, not the track object: equal artists fetched as
/// different instances share one entry (the object-keyed version missed on
/// every re-fetch). Bios effectively never change, so the entry is kept for
/// days rather than dropped on scroll-away — a revisit costs zero HTTP.
final artistWikipediaSummaryProvider =
    FutureProvider.autoDispose.family<Summary?, ({String id, String name})>(
  (ref, artist) async {
    ref.cacheFor(const Duration(days: 7));
    return fetchArtistWikipediaSummary(artist.name);
  },
);

/// Fetches an artist bio: exact title first, `<name> (singer)` when Wikipedia
/// answers with anything but a standard page. [pageSummary] is the test seam
/// (production reads the shared Wikipedia client).
@visibleForTesting
Future<Summary?> fetchArtistWikipediaSummary(
  String artistName, {
  Future<Summary?> Function(String query)? pageSummary,
}) async {
  final fetch = pageSummary ?? wikipedia.pageContent.pageSummaryTitleGet;
  final query = artistName.replaceAll(" ", "_");
  final res = await fetch(query);

  if (res?.type != "standard") {
    return fetch("${query}_(singer)");
  }
  return res;
}
