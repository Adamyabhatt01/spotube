part of '../database.dart';

class SourceMatchTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  TextColumn get sourceInfo => text().withDefault(const Constant("{}"))();
  TextColumn get sourceType => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Quarantine for source_match rows that cannot be losslessly migrated.
///
/// Rows whose historical `source_id` payload fails validation are parked
/// here (with the raw payload + reason) instead of being deleted, so no
/// migration ever silently discards user data. The live table keeps
/// serving as a pure performance cache: a missing row is a self-healing
/// cache miss.
class SourceMatchQuarantineTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  TextColumn get rawSourceId => text()();
  TextColumn get reason => text()();
  TextColumn get sourceType => text().nullable()();
  IntColumn get quarantinedAtMs => integer()();
}
