import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:spotube/utils/perf_counters.dart';

typedef PlaybackHistoryPlaylist = ({
  int count,
  SpotubeSimplePlaylistObject playlist
});

/// The playlist id as stored inside the row's JSON. Grouping by this rather
/// than by the `item_id` column keeps the aggregation on exactly the key the
/// Dart grouping used - the same decision as `_trackIdFromJson` in
/// `top/tracks.dart`.
const String _playlistIdFromJson = r'''
  json_extract(history_table.data, '$.id')
''';

/// The counterpart of `HistoryItemParseExtension.playlist`, which returns null
/// for legacy rows that stored the whole source object under `external_urls`.
/// The old `playlist.playlist!` crashed on such rows; dropping them before
/// grouping is what the tracks aggregation does for the same shape.
const String _isResolvablePlaylist = r'''
  json_extract(history_table.data, '$.external_urls') IS NULL
''';

/// Groups the watched window per playlist id entirely in SQLite and
/// materializes the JSON of exactly one row per group (the group's first,
/// matching `groupBy(...).first`). Ordering is by play count, ties by first
/// appearance - the previous unstable `List.sort` left ties free to come out
/// in any order consistent with the count.
///
/// Watching `select(historyTable)` over the whole window instead decoded every
/// row's `data` blob twice (drift's `MapTypeConverter`, then
/// `SpotubeSimplePlaylistObject.fromJson`) on every history write, so the cost
/// of one scrobble grew linearly with the playlist history.
const String _groupedPlaylistsSql = '''
  WITH scoped AS MATERIALIZED (
    SELECT
      history_table.id AS row_id,
      $_playlistIdFromJson AS item_id
    FROM history_table
    WHERE history_table.type = 'playlist'
      AND history_table.created_at >= ?
      AND $_isResolvablePlaylist
  )
  SELECT
    grouped.plays AS plays,
    history_table.data AS data
  FROM (
    SELECT
      item_id,
      COUNT(*) AS plays,
      MIN(row_id) AS first_id,
      MIN(row_id) AS representative_id
    FROM scoped
    GROUP BY item_id
  ) AS grouped
  JOIN history_table ON history_table.id = grouped.representative_id
  ORDER BY grouped.plays DESC, grouped.first_id ASC
''';

/// Groups the playback history since [windowStart] per playlist id, entirely
/// in SQLite. See [_groupedPlaylistsSql].
Selectable<PlaybackHistoryPlaylist> historyPlaylistGroups(
  AppDatabase database, {
  required DateTime windowStart,
}) {
  return database.customSelect(
    _groupedPlaylistsSql,
    variables: [Variable.withDateTime(windowStart)],
    readsFrom: {database.historyTable},
  ).map((row) {
    final data = row.read<String>('data');
    return (
      count: row.read<int>('plays'),
      playlist: PerfCounters.measured('history.playlistParseTime', () {
        PerfCounters.note('history.playlistParse');
        return SpotubeSimplePlaylistObject.fromJson(jsonDecode(data));
      }),
    );
  });
}

class HistoryTopPlaylistsNotifier
    extends AutoDisposeFamilyPaginatedAsyncNotifier<PlaybackHistoryPlaylist,
        HistoryDuration> {
  HistoryTopPlaylistsNotifier() : super();

  /// Start of the watched window. Shared by the typed page query, the SQL
  /// aggregation and the other Stats families so "this week" is the same week
  /// in every tab.
  DateTime get windowStart => historyWindowStart(arg);

  SimpleSelectStatement<$HistoryTableTable, HistoryTableData>
      createPlaylistsQuery() {
    final database = ref.read(databaseProvider);

    return database.select(database.historyTable)
      ..where(
        (tbl) =>
            tbl.type.equalsValue(HistoryEntryType.playlist) &
            tbl.createdAt.isBiggerOrEqualValue(windowStart),
      );
  }

  Selectable<PlaybackHistoryPlaylist> createGroupedPlaylistsQuery() =>
      historyPlaylistGroups(
        ref.read(databaseProvider),
        windowStart: windowStart,
      );

  @override
  fetch(offset, limit) async {
    final playlistsQuery = createPlaylistsQuery()..limit(limit, offset: offset);

    final items = getPlaylistsWithCount(await playlistsQuery.get());

    return SpotubePaginationResponseObject(
      items: items,
      nextOffset: offset + limit,
      total: items.length,
      limit: limit,
      hasMore: items.length == limit,
    );
  }

  @override
  build(arg) async {
    // Events arriving during the initial fetch used to be dropped, leaving
    // the first frame permanently stale until the next write. Buffer the
    // newest one and apply it once the initial page resolves (same fix as
    // HistoryTopTracks/AlbumsNotifier.build).
    List<PlaybackHistoryPlaylist>? bufferedEvent;
    final subscription = createGroupedPlaylistsQuery().watch().listen((event) {
      if (state.asData == null) {
        bufferedEvent = event;
        return;
      }
      state = AsyncData(state.asData!.value.copyWith(
        items: event,
        hasMore: false,
      ));
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    final initial = await fetch(0, 20);
    if (bufferedEvent case final buffered?) {
      return initial.copyWith(
        items: buffered,
        hasMore: false,
      );
    }
    return initial;
  }

  List<PlaybackHistoryPlaylist> getPlaylistsWithCount(
    List<HistoryTableData> playlists,
  ) {
    // Legacy rows store the whole source object under `external_urls` and
    // have no `playlist`; the old `playlist!` threw on them. Drop them before
    // grouping, exactly like the tracks aggregation and the watch query.
    final parsed = <SpotubeSimplePlaylistObject>[
      for (final row in playlists)
        if (row.playlist case final playlist?) playlist,
    ];

    return groupBy(parsed, (playlist) => playlist.id)
        .entries
        .map((entry) {
          return (
            count: entry.value.length,
            playlist: entry.value.first,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }
}

final historyTopPlaylistsProvider = AutoDisposeAsyncNotifierProviderFamily<
    HistoryTopPlaylistsNotifier,
    SpotubePaginationResponseObject<PlaybackHistoryPlaylist>,
    HistoryDuration>(
  () => HistoryTopPlaylistsNotifier(),
);
