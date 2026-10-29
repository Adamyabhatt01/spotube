import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/database/database.dart';

/// Most-recently-played stations, one row per station (latest visit wins),
/// capped at 20.
///
/// Reads the existing [HistoryTable] filtered to `type = 'radio'` and deduped
/// with a window function — the same pattern as the home-screen recently-played
/// list — so listening history costs no new table or migration.
class RadioHistoryNotifier
    extends AutoDisposeAsyncNotifier<List<RadioStation>> {
  static const _limit = 20;

  static const _sql = '''
      WITH RankedRadio AS (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY created_at DESC) AS rn
        FROM history_table
        WHERE type = 'radio'
      )
      SELECT * FROM RankedRadio
      WHERE rn = 1
      ORDER BY created_at DESC
      LIMIT $_limit
      ''';

  @override
  FutureOr<List<RadioStation>> build() async {
    final db = ref.watch(databaseProvider);
    final query = db.customSelect(
      _sql,
      readsFrom: {db.historyTable},
    ).map((row) {
      return _stationFromRow(row);
    });

    final subscription = query.watch().listen((rows) async {
      state = AsyncData(rows.whereType<RadioStation>().toList());
    });
    ref.onDispose(subscription.cancel);

    final initial = (await query.get()).whereType<RadioStation>().toList();
    return initial;
  }

  RadioStation? _stationFromRow(dynamic row) {
    try {
      return RadioStation.fromJson(
        jsonDecode(row.read<String>('data')) as Map<String, dynamic>,
      );
    } catch (_) {
      // A corrupt row is a missing entry, not a broken list.
      return null;
    }
  }
}

final radioHistoryProvider =
    AutoDisposeAsyncNotifierProvider<RadioHistoryNotifier, List<RadioStation>>(
  RadioHistoryNotifier.new,
);
