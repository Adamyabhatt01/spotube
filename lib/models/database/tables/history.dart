part of '../database.dart';

enum HistoryEntryType {
  playlist,
  album,
  track,
}

class HistoryTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get type => textEnum<HistoryEntryType>()();
  TextColumn get itemId => text()();
  TextColumn get data =>
      text().map(const MapTypeConverter<String, dynamic>())();
}

extension HistoryItemParseExtension on HistoryTableData {
  SpotubeSimplePlaylistObject? get playlist =>
      type == HistoryEntryType.playlist && !data.containsKey("external_urls")
          ? PerfCounters.measured(
              'history.playlistParseTime',
              () {
                PerfCounters.note('history.playlistParse');
                return SpotubeSimplePlaylistObject.fromJson(data);
              },
            )
          : null;
  SpotubeSimpleAlbumObject? get album =>
      type == HistoryEntryType.album && !data.containsKey("external_urls")
          ? PerfCounters.measured(
              'history.albumParseTime',
              () {
                PerfCounters.note('history.albumParse');
                return SpotubeSimpleAlbumObject.fromJson(data);
              },
            )
          : null;
  SpotubeTrackObject? get track {
    if (type != HistoryEntryType.track || data.containsKey("external_urls")) {
      return null;
    }
    // Every history watcher that re-materializes its rows parses one JSON
    // document per row through this getter, so the count is the direct measure
    // of "did a track change cost us the whole table again".
    PerfCounters.note('history.rowParse');
    return PerfCounters.measured(
      'history.rowParseTime',
      () => SpotubeTrackObject.fromJson(data),
    );
  }
}
