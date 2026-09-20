import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/history/top.dart';
import 'package:spotube/provider/metadata_plugin/artist/artist.dart';
import 'package:spotube/provider/metadata_plugin/utils/family_paginated.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/perf_counters.dart';

typedef PlaybackHistoryTrack = ({int count, SpotubeTrackObject track});
typedef PlaybackHistoryArtist = ({int count, SpotubeSimpleArtistObject artist});

/// A history row whose embedded track JSON has been parsed exactly once.
/// `HistoryTableData.track` decodes JSON on EVERY getter access, so passing
/// raw rows through groupBy + pickers parsed each row 3+ times per event.
typedef ParsedHistoryTrack = ({HistoryTableData row, SpotubeTrackObject track});

/// A track group produced by the SQL-side aggregation, together with the number
/// of rows in the group whose artists still miss their images.
typedef GroupedHistoryTrack = ({PlaybackHistoryTrack item, int unresolved});

/// Whether every artist of a row's track has images, as SQL. This is the
/// counterpart of Dart's `track.artists.every((a) => a.images != null)`:
/// `json_extract` yields NULL both for an absent key and for a JSON null, and
/// an empty or present array is non-NULL either way, exactly like Dart's
/// `images != null`.
const String _allArtistsHaveImages = r'''
  NOT EXISTS (
    SELECT 1
    FROM json_each(json_extract(history_table.data, '$.artists')) AS artist
    WHERE json_extract(artist.value, '$.images') IS NULL
  )
''';

/// Legacy rows (from before tracks were resolved) stored the whole source
/// object under `external_urls`; `HistoryTableData.track` returns null for
/// them, which is the same as dropping them before grouping.
const String _isResolvableTrack = r'''
  json_extract(history_table.data, '$.external_urls') IS NULL
''';

/// The track id as stored inside the row's JSON. Grouping by this rather than by
/// the `item_id` column keeps the aggregation on exactly the key the Dart
/// grouping used - the column is written from the same value by
/// `PlaybackHistoryActions`, but only for rows the current app wrote.
const String _trackIdFromJson = r'''
  json_extract(history_table.data, '$.id')
''';

/// Groups the watched history window per track id entirely in SQLite, and
/// materializes the track JSON of exactly one row per group.
///
/// The representative rule is the one the Dart grouping used: the first row of
/// the group whose artists all have images, falling back to the group's first
/// row. Ordering is by play count, ties by first appearance - the previous
/// `List.sort` was unstable, so it left ties free to come out in any order
/// consistent with the count.
///
/// Watching `select(historyTable)` over the whole window instead decoded every
/// row's `data` blob twice (drift's `MapTypeConverter`, then
/// `SpotubeTrackObject.fromJson`), which measured 74ms per history write at
/// 5k rows and 713ms at 25k.
/// The per-row flags are computed in a materialized CTE, not inline: the
/// aggregation reads [$_allArtistsHaveImages] twice (once to count unresolved
/// rows, once to pick the representative) and SQLite would otherwise run the
/// `json_each` scan twice per row.
const String _groupedTracksSql = '''
  WITH flagged AS MATERIALIZED (
    SELECT
      history_table.id AS row_id,
      $_trackIdFromJson AS item_id,
      $_allArtistsHaveImages AS imaged
    FROM history_table
    WHERE history_table.type = 'track'
      AND history_table.created_at >= ?
      AND $_isResolvableTrack
  )
  SELECT
    grouped.plays AS plays,
    grouped.unresolved AS unresolved,
    history_table.data AS data
  FROM (
    SELECT
      item_id,
      COUNT(*) AS plays,
      MIN(row_id) AS first_id,
      COUNT(*) - SUM(imaged) AS unresolved,
      COALESCE(
        MIN(CASE WHEN imaged = 1 THEN row_id END),
        MIN(row_id)
      ) AS representative_id
    FROM flagged
    GROUP BY item_id
  ) AS grouped
  JOIN history_table ON history_table.id = grouped.representative_id
  ORDER BY grouped.plays DESC, grouped.first_id ASC
''';

/// Rows of the window whose artists still miss their images - the input of the
/// repair below. Only queried when the aggregation reports an unresolved group,
/// so a healthy history pays nothing for it.
const String _unresolvedTracksSql = '''
  SELECT history_table.id AS row_id, history_table.data AS data
  FROM history_table
  WHERE history_table.type = 'track'
    AND history_table.created_at >= ?
    AND $_isResolvableTrack
    AND NOT $_allArtistsHaveImages
''';

/// Start of the window a [HistoryDuration] covers.
///
/// Kept next to the SQL that filters on it so the typed page query, the
/// aggregation and the image repair all agree on what "this period" means.
DateTime historyWindowStart(HistoryDuration duration) => switch (duration) {
      HistoryDuration.allTime => DateTime(1970),
      // from start of the week
      HistoryDuration.days7 =>
        DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)),
      // from start of the month
      HistoryDuration.days30 =>
        DateTime.now().subtract(Duration(days: DateTime.now().day - 1)),
      // from start of the 6th month
      HistoryDuration.months6 => DateTime.now()
          .subtract(Duration(days: DateTime.now().day - 1))
          .subtract(const Duration(days: 30 * 6)),
      // from start of the year
      HistoryDuration.year => DateTime.now()
          .subtract(Duration(days: DateTime.now().day - 1))
          .subtract(const Duration(days: 30 * 12)),
      HistoryDuration.years2 => DateTime.now()
          .subtract(Duration(days: DateTime.now().day - 1))
          .subtract(const Duration(days: 30 * 12 * 2)),
    };

/// Groups the playback history since [windowStart] per track id, entirely in
/// SQLite. See [_groupedTracksSql].
Selectable<GroupedHistoryTrack> historyTrackGroups(
  AppDatabase database, {
  required DateTime windowStart,
}) {
  return database.customSelect(
    _groupedTracksSql,
    variables: [Variable.withDateTime(windowStart)],
    readsFrom: {database.historyTable},
  ).map((row) {
    final data = row.read<String>('data');
    return (
      item: (
        count: row.read<int>('plays'),
        track: PerfCounters.measured('history.rowParseTime', () {
          PerfCounters.note('history.rowParse');
          return SpotubeTrackObject.fromJson(jsonDecode(data));
        }),
      ),
      unresolved: row.read<int>('unresolved'),
    );
  });
}

/// The rows of the window since [windowStart] whose artists still miss images.
Selectable<({int id, SpotubeTrackObject track})>
    historyTracksMissingArtistImages(
  AppDatabase database, {
  required DateTime windowStart,
}) {
  return database.customSelect(
    _unresolvedTracksSql,
    variables: [Variable.withDateTime(windowStart)],
    readsFrom: {database.historyTable},
  ).map((row) {
    final data = row.read<String>('data');
    return (
      id: row.read<int>('row_id'),
      track: PerfCounters.measured('history.rowParseTime', () {
        PerfCounters.note('history.rowParse');
        return SpotubeTrackObject.fromJson(jsonDecode(data));
      }),
    );
  });
}

class HistoryTopTracksNotifier extends AutoDisposeFamilyPaginatedAsyncNotifier<
    PlaybackHistoryTrack, HistoryDuration> {
  HistoryTopTracksNotifier() : super();

  /// Start of the watched window. Shared by the typed page query and the SQL
  /// aggregation so both agree on what "this period" means.
  DateTime get windowStart => historyWindowStart(arg);

  SimpleSelectStatement<$HistoryTableTable, HistoryTableData>
      createTracksQuery() {
    final database = ref.read(databaseProvider);

    return database.select(database.historyTable)
      ..where(
        (tbl) =>
            tbl.type.equalsValue(HistoryEntryType.track) &
            tbl.createdAt.isBiggerOrEqualValue(windowStart),
      );
  }

  Selectable<GroupedHistoryTrack> createGroupedTracksQuery() =>
      historyTrackGroups(
        ref.read(databaseProvider),
        windowStart: windowStart,
      );

  /// Artist ids currently being repaired by [fixImageNotLoadingForArtistIssue].
  /// The repair writes to the SAME watched table, whose write event calls
  /// getTracksWithCount again — without this guard every pending fix restarts
  /// on each event and the loop feeds itself.
  final Set<String> _fixingArtistIds = {};

  /// A plugin failing for one artist must not kill the whole repair (and an
  /// unawaited throw here would surface as an uncaught async error).
  Future<SpotubeFullArtistObject?> _fetchArtist(String id) async {
    try {
      return await ref.read(metadataPluginArtistProvider(id).future);
    } catch (_) {
      return null;
    }
  }

  /// Fills in artist images from the metadata plugin, one row at a time.
  ///
  /// Previously, due to a bug, artist images were not being saved. Now it's
  /// fixed, but old history rows still have to be repaired.
  Future<void> fixImageNotLoadingForArtistIssue(
    List<ParsedHistoryTrack> entries,
  ) async {
    final nonImageArtistTracks = entries
        .where((e) => e.track.artists.any((a) => a.images == null))
        .toList();

    if (nonImageArtistTracks.isEmpty) return;

    final artistIds =
        _unfixedArtistIds(nonImageArtistTracks.map((e) => e.track));
    if (artistIds.isEmpty) return;

    _fixingArtistIds.addAll(artistIds);
    try {
      final artists = await _fetchMissingArtists(artistIds);
      if (artists == null) return;

      final fixed = nonImageArtistTracks
          .map((e) => (row: e.row, track: _withArtistImages(e.track, artists)))
          .toList();

      final database = ref.read(databaseProvider);
      await database.batch((batch) {
        batch.insertAllOnConflictUpdate(
          database.historyTable,
          fixed.map((e) => e.row.copyWith(data: e.track.toJson())),
        );
      });
    } finally {
      _fixingArtistIds.removeAll(artistIds);
    }
  }

  /// Watch-event variant of [fixImageNotLoadingForArtistIssue]: repairs every
  /// flagged row of the window, not just the rows the page materialized. Same
  /// window, same rows, same effect - `data` is the only column it rewrites,
  /// which is the only column the old full-row upsert changed.
  Future<void> fixUnresolvedArtists() async {
    final database = ref.read(databaseProvider);
    final rows = await historyTracksMissingArtistImages(
      database,
      windowStart: windowStart,
    ).get();

    if (rows.isEmpty) return;

    final artistIds = _unfixedArtistIds(rows.map((row) => row.track));
    if (artistIds.isEmpty) return;

    _fixingArtistIds.addAll(artistIds);
    try {
      final artists = await _fetchMissingArtists(artistIds);
      if (artists == null) return;

      // Written as raw SQL because the flagged set can be larger than SQLite's
      // host-parameter limit, which an `id IN (...)` companion upsert would
      // hit. The explicit TableUpdate is what makes watchers see the write.
      await database.batch((batch) {
        for (final row in rows) {
          if (row.track.artists.every((a) => a.images != null)) continue;
          batch.customStatement(
            'UPDATE history_table SET data = ? WHERE id = ?',
            [
              jsonEncode(_withArtistImages(row.track, artists).toJson()),
              row.id,
            ],
            [
              TableUpdate.onTable(database.historyTable,
                  kind: UpdateKind.update)
            ],
          );
        }
      });
    } finally {
      _fixingArtistIds.removeAll(artistIds);
    }
  }

  /// Artist ids that still need a lookup, minus the ones already in flight.
  List<String> _unfixedArtistIds(Iterable<SpotubeTrackObject> tracks) {
    return tracks
        .map((track) => track.artists.map((a) => a.id))
        .expand((ids) => ids)
        .toSet()
        .where((id) => !_fixingArtistIds.contains(id))
        .toList();
  }

  /// Returns null when nothing could be fetched, leaving the rows untouched so
  /// the next history event retries - the behavior the per-event repair had.
  Future<List<SpotubeFullArtistObject>?> _fetchMissingArtists(
    List<String> artistIds,
  ) async {
    final artists = (await Future.wait([
      for (final id in artistIds) _fetchArtist(id),
    ]))
        .nonNulls
        .toList();

    return artists.isEmpty ? null : artists;
  }

  SpotubeTrackObject _withArtistImages(
    SpotubeTrackObject track,
    List<SpotubeFullArtistObject> artists,
  ) {
    final includedArtists = track.artists
        .map((a) {
          final fullArtist = artists.firstWhereOrNull(
            (artist) => artist.id == a.id,
          );
          return fullArtist != null ? a.copyWith(images: fullArtist.images) : a;
        })
        .nonNulls
        .toList();

    assert(
      includedArtists.every((a) => a.images != null),
      'Tracks artists should have images',
    );

    return track.copyWith(artists: includedArtists);
  }

  @override
  fetch(offset, limit) async {
    final tracksQuery = createTracksQuery()..limit(limit, offset: offset);

    final entries = await tracksQuery.get();

    final items = getTracksWithCount(entries);

    return SpotubePaginationResponseObject<PlaybackHistoryTrack>(
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
    // newest one and apply it once the initial page resolves.
    List<PlaybackHistoryTrack>? bufferedEvent;
    final subscription = createGroupedTracksQuery().watch().listen((event) {
      final items = _applyEvent(event);
      if (state.asData == null) {
        bufferedEvent = items;
        return;
      }
      state = AsyncData(
        state.asData!.value.copyWith(items: items, hasMore: false),
      );
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    final initial = await fetch(0, 20);
    if (bufferedEvent case final buffered?) {
      return initial.copyWith(items: buffered, hasMore: false);
    }
    return initial;
  }

  /// Publishes one aggregation event and kicks off the image repair if the
  /// aggregation flagged anything. Returns the items to show.
  List<PlaybackHistoryTrack> _applyEvent(List<GroupedHistoryTrack> event) {
    PerfCounters.note('history.tracks.watchEvents');
    if (event.any((group) => group.unresolved > 0)) {
      // Fire-and-forget, but never let a repair failure surface as an
      // uncaught async error (it runs on every watch event).
      fixUnresolvedArtists().catchError((Object error, StackTrace stack) {
        AppLogger.reportError(error, stack);
      });
    }

    return event.map((group) => group.item).toList();
  }

  List<PlaybackHistoryArtist> get artists {
    return getArtistsWithCount(
      state.asData?.value.items.expand((e) => e.track.artists) ?? [],
    );
  }

  List<PlaybackHistoryArtist> getArtistsWithCount(
    Iterable<SpotubeSimpleArtistObject> artists,
  ) {
    return groupBy(artists, (artist) => artist.id)
        .entries
        .map((entry) {
          return (
            count: entry.value.length,

            /// Previously, due to a bug, artist images were not being saved.
            /// Now it's fixed, but we need to handle the case where images are null.
            /// So we take the first artist with images if available, otherwise the first one.
            artist: entry.value.firstWhereOrNull((a) => a.images != null) ??
                entry.value.first,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }

  List<PlaybackHistoryTrack> getTracksWithCount(List<HistoryTableData> tracks) {
    // Parse each row once (see ParsedHistoryTrack); also drops legacy rows
    // whose JSON no longer decodes to a track instead of crashing on `!`.
    final parsed = <ParsedHistoryTrack>[
      for (final row in tracks)
        if (row.track case final track?) (row: row, track: track),
    ];

    // Fire-and-forget, but never let a repair failure surface as an
    // uncaught async error (it runs on every watch event).
    fixImageNotLoadingForArtistIssue(parsed).catchError(
      (Object error, StackTrace stack) {
        AppLogger.reportError(error, stack);
      },
    );

    return groupBy(
      parsed,
      (entry) => entry.track.id,
    )
        .entries
        .map((entry) {
          return (
            count: entry.value.length,

            /// Previously, due to a bug, artist images were not being saved.
            /// Now it's fixed, but we need to handle the case where images are null.
            /// So we take the first artist with images if available, otherwise the first one.
            track: entry.value
                    .firstWhereOrNull(
                        (t) => t.track.artists.every((a) => a.images != null))
                    ?.track ??
                entry.value.first.track,
          );
        })
        .sorted((a, b) => b.count.compareTo(a.count))
        .toList();
  }
}

final historyTopTracksProvider = AutoDisposeAsyncNotifierProviderFamily<
    HistoryTopTracksNotifier,
    SpotubePaginationResponseObject<PlaybackHistoryTrack>,
    HistoryDuration>(
  () => HistoryTopTracksNotifier(),
);
