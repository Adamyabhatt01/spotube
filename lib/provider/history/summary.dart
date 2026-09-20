import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/extensions/json1.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
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

  PlaybackHistorySummary copyWith({
    Duration? duration,
    int? tracks,
    int? artists,
    double? fees,
    int? albums,
    int? playlists,
  }) {
    return PlaybackHistorySummary(
      duration: duration ?? this.duration,
      tracks: tracks ?? this.tracks,
      artists: artists ?? this.artists,
      fees: fees ?? this.fees,
      albums: albums ?? this.albums,
      playlists: playlists ?? this.playlists,
    );
  }
}

class PlaybackHistorySummaryNotifier
    extends AsyncNotifier<PlaybackHistorySummary> {
  @override
  build() async {
    final database = ref.watch(databaseProvider);

    final uniqItemIdCountingCol =
        database.historyTable.itemId.count(distinct: true);
    final itemIdCountingCol = database.historyTable.itemId.count();
    final durationSumJsonColumn =
        database.historyTable.data.jsonExtract<int>(r"$.durationMs").sum();

    final totalTracksListenedQuery = (database.selectOnly(database.historyTable)
          ..addColumns([uniqItemIdCountingCol])
          ..where(
              database.historyTable.type.equals(HistoryEntryType.track.name)))
        .map((row) => row.read(uniqItemIdCountingCol));

    final totalDurationListenedQuery = (database
            .selectOnly(database.historyTable)
          ..addColumns([durationSumJsonColumn])
          ..where(
              database.historyTable.type.equals(HistoryEntryType.track.name)))
        .map(
      (row) => Duration(milliseconds: row.read(durationSumJsonColumn) ?? 0),
    );

    // Distinct artist count in SQL: the previous per-row decode re-parsed
    // the artists JSON of EVERY history row on every watch event — the
    // dominant cost on the stats page for large histories.
    final totalArtistsListenedQuery = database.customSelect(
      '''
      SELECT COUNT(DISTINCT json_extract(artist_element.value, '\$.id')) AS artist_count
      FROM history_table,
           json_each(json_extract(history_table.data, '\$.artists')) AS artist_element
      WHERE history_table.type = 'track'
      ''',
      readsFrom: {database.historyTable},
    ).map((row) => row.read<int>('artist_count'));

    final totalAlbumsListenedQuery = (database.selectOnly(database.historyTable)
          ..addColumns([uniqItemIdCountingCol])
          ..where(
              database.historyTable.type.equals(HistoryEntryType.album.name)))
        .map((row) => row.read(uniqItemIdCountingCol));

    final totalPlaylistsListenedQuery =
        (database.selectOnly(database.historyTable)
              ..addColumns([uniqItemIdCountingCol])
              ..where(
                database.historyTable.type
                    .equals(HistoryEntryType.playlist.name),
              ))
            .map((row) => row.read(uniqItemIdCountingCol));

    // [startOfMonth, startOfMonthNext) — the previous
    // copyWith(day: 30, hour: 23) window dropped everything on day 31
    // and mis-bounded shorter months.
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month);
    final startOfNextMonth = DateTime(now.year, now.month + 1);
    final totalTracksListenedThisMonthQuery =
        (database.selectOnly(database.historyTable)
              ..addColumns([itemIdCountingCol])
              ..where(
                database.historyTable.type.equals(
                      HistoryEntryType.track.name,
                    ) &
                    database.historyTable.createdAt
                        .isBiggerOrEqualValue(startOfMonth) &
                    database.historyTable.createdAt
                        .isSmallerThanValue(startOfNextMonth),
              ))
            .map((row) => row.read(itemIdCountingCol));

    final subscriptions = <StreamSubscription>[
      totalTracksListenedQuery.watchSingle().listen((event) {
        if (event == null || state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          tracks: event,
        ));
      }),
      totalDurationListenedQuery.watchSingle().listen((event) {
        if (state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          duration: event,
        ));
      }),
      totalArtistsListenedQuery.watchSingle().listen((event) {
        if (state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          artists: event,
        ));
      }),
      totalAlbumsListenedQuery.watchSingle().listen((event) {
        if (event == null || state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          albums: event,
        ));
      }),
      totalPlaylistsListenedQuery.watchSingle().listen((event) {
        if (event == null || state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          playlists: event,
        ));
      }),
      totalTracksListenedThisMonthQuery.watchSingle().listen((event) {
        if (event == null || state.asData == null) return;
        state = AsyncData(state.asData!.value.copyWith(
          fees: event * 0.005,
        ));
      }),
    ];

    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });

    return database.transaction(() async {
      final totalTracksListened =
          await totalTracksListenedQuery.getSingle() ?? 0;

      final totalDurationListened =
          await totalDurationListenedQuery.getSingle();

      final totalArtistsListened =
          await totalArtistsListenedQuery.getSingle().catchError((_) => 0);

      final totalAlbumsListened =
          await totalAlbumsListenedQuery.getSingle() ?? 0;

      final totalPlaylistsListened =
          await totalPlaylistsListenedQuery.getSingle() ?? 0;

      final totalTracksListenedThisMonth =
          await totalTracksListenedThisMonthQuery.getSingle() ?? 0;

      return PlaybackHistorySummary(
        duration: totalDurationListened,
        tracks: totalTracksListened,
        artists: totalArtistsListened,
        fees: totalTracksListenedThisMonth * 0.005,
        albums: totalAlbumsListened,
        playlists: totalPlaylistsListened,
      );
    });
  }
}

final playbackHistorySummaryProvider = AsyncNotifierProvider<
    PlaybackHistorySummaryNotifier, PlaybackHistorySummary>(
  () => PlaybackHistorySummaryNotifier(),
);
