part of '../database.dart';

/// Bookmarked internet-radio stations.
///
/// Mirrors [BlacklistTable]'s shape (discrete key columns + a composite unique
/// index) rather than pretending a station is a track. `stationId` is only
/// unique *within* a directory, so the key is `(stationId, provider)` — the
/// same raw id from two providers is two distinct bookmarks. `data` is a
/// snapshot of the [RadioStation] (name, favicon, last-seen stream URL) so the
/// favorites list renders offline and survives the station vanishing upstream;
/// the stream URL is re-resolved through the directory at play time and this
/// copy is only the fallback.
@TableIndex(
  name: 'unique_radio_favorite',
  unique: true,
  columns: {#stationId, #provider},
)
class RadioFavoritesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get stationId => text()();
  TextColumn get provider => text()();
  TextColumn get data =>
      text().map(const MapTypeConverter<String, dynamic>())();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

extension RadioFavoriteStationExtension on RadioFavoritesTableData {
  /// The stored snapshot. Malformed legacy rows fall back to a minimal station
  /// built from the key columns so the list never drops a favorite outright.
  RadioStation get station {
    try {
      return RadioStation.fromJson(data);
    } catch (_) {
      return RadioStation(
        id: stationId,
        provider: provider,
        name: stationId,
        streamUrl: '',
      );
    }
  }
}
