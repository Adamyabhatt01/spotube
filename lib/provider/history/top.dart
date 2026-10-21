import 'package:hooks_riverpod/hooks_riverpod.dart';

enum HistoryDuration {
  allTime(Duration(days: 365 * 2003)),
  days7(Duration(days: 7)),
  days30(Duration(days: 30)),
  months6(Duration(days: 30 * 6)),
  year(Duration(days: 365)),
  years2(Duration(days: 365 * 2));

  final Duration duration;

  const HistoryDuration(this.duration);
}

final playbackHistoryTopDurationProvider =
    StateProvider((ref) => HistoryDuration.days30);

/// Start of the window a [HistoryDuration] covers.
///
/// Kept next to the enum so the typed page queries, the SQL aggregations and
/// the image repair all agree on what "this period" means. Calendar-based
/// boundaries (start of week/month/year) match the duration labels; rolling
/// N-day approximations made "this week" start on Sunday in one provider and
/// Monday in another.
DateTime historyWindowStart(HistoryDuration duration) {
  final now = DateTime.now();
  return switch (duration) {
    HistoryDuration.allTime => DateTime(1970),
    // from start of the week (Monday)
    HistoryDuration.days7 =>
      DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    // from start of the month
    HistoryDuration.days30 => DateTime(now.year, now.month),
    // the current month plus the five before it
    HistoryDuration.months6 => DateTime(now.year, now.month - 5),
    // from start of the year
    HistoryDuration.year => DateTime(now.year),
    // the current year plus the one before it
    HistoryDuration.years2 => DateTime(now.year - 1),
  };
}
