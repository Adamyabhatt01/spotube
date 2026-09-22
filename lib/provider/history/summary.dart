import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/provider/database/database.dart';

class PlaybackHistorySummary {
  final Duration duration;
  final int tracks;
  final int artists;
  final double fees;
  final int albums;
  final int playlists;

  const PlaybackHistorySummary({
    required this.duration,
    required this.tracks,
    required this.artists,
    required this.fees,
    required this.albums,
    required this.playlists,
  });

  /// The watch below compares emissions with this, so a history write that
  /// moves none of the six numbers (a repeat of the same track) notifies
  /// nobody.
  @override
  bool operator ==(Object other) {
    return other is PlaybackHistorySummary &&
        other.duration == duration &&
        other.tracks == tracks &&
        other.artists == artists &&
        other.fees == fees &&
        other.albums == albums &&
        other.playlists == playlists;
  }

  @override
  int get hashCode =>
      Object.hash(duration, tracks, artists, fees, albums, playlists);
}

/// The six aggregates as one statement. They used to be six watched queries, so
/// every history write re-scanned the table six times - two of those scans
/// unwindowed - and emitted six separate states. The artist count needs the
/// `json_each` join, which is why it is a branch of a UNION ALL rather than
/// another column of one row.
const _summaryQuery = r'''
  SELECT 'tracks' AS metric, COUNT(DISTINCT item_id) AS value
  FROM history_table WHERE type = 'track'
  UNION ALL
  SELECT 'duration', COALESCE(SUM(CAST(json_extract(data, '$.durationMs') AS INTEGER)), 0)
  FROM history_table WHERE type = 'track'
  UNION ALL
  SELECT 'artists', COUNT(DISTINCT json_extract(artist_element.value, '$.id'))
  FROM history_table,
       json_each(json_extract(history_table.data, '$.artists')) AS artist_element
  WHERE history_table.type = 'track'
  UNION ALL
  SELECT 'albums', COUNT(DISTINCT item_id)
  FROM history_table WHERE type = 'album'
  UNION ALL
  SELECT 'playlists', COUNT(DISTINCT item_id)
  FROM history_table WHERE type = 'playlist'
  UNION ALL
  SELECT 'month', COUNT(item_id)
  FROM history_table
  WHERE type = 'track' AND created_at >= ? AND created_at < ?
''';

PlaybackHistorySummary _summaryFromRows(List<QueryRow> rows) {
  var tracks = 0, artists = 0, albums = 0, playlists = 0, month = 0;
  var durationMs = 0;

  for (final row in rows) {
    final value = (row.data['value'] as num?)?.toInt() ?? 0;
    switch (row.data['metric'] as String) {
      case 'tracks':
        tracks = value;
      case 'duration':
        durationMs = value;
      case 'artists':
        artists = value;
      case 'albums':
        albums = value;
      case 'playlists':
        playlists = value;
      case 'month':
        month = value;
    }
  }

  return PlaybackHistorySummary(
    duration: Duration(milliseconds: durationMs),
    tracks: tracks,
    artists: artists,
    // The royalty estimate the stats page shows: a fraction of a cent per
    // stream, counted over the current calendar month.
    fees: month * 0.005,
    albums: albums,
    playlists: playlists,
  );
}

class PlaybackHistorySummaryNotifier
    extends AutoDisposeAsyncNotifier<PlaybackHistorySummary> {
  @override
  build() async {
    final database = ref.watch(databaseProvider);

    // [startOfMonth, startOfNextMonth) — the previous
    // copyWith(day: 30, hour: 23) window dropped everything on day 31
    // and mis-bounded shorter months.
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfNextMonth = DateTime(now.year, now.month + 1);

    final query = database.customSelect(
      _summaryQuery,
      variables: [
        Variable.withDateTime(startOfMonth),
        Variable.withDateTime(startOfNextMonth),
      ],
      readsFrom: {database.historyTable},
    );

    final subscription = query.watch().listen((rows) {
      final next = _summaryFromRows(rows);
      final current = state.asData?.value;
      if (current != null && current == next) return;
      state = AsyncData(next);
    });

    ref.onDispose(() => subscription.cancel());

    return _summaryFromRows(await query.get());
  }
}

/// Auto-disposed: the stats page is its only consumer, and while it was kept
/// alive this aggregate re-ran on every play-history write for the rest of the
/// session, whether or not anyone was looking at it.
final playbackHistorySummaryProvider = AutoDisposeAsyncNotifierProvider<
    PlaybackHistorySummaryNotifier, PlaybackHistorySummary>(
  () => PlaybackHistorySummaryNotifier(),
);
