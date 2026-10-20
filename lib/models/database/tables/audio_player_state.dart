part of '../database.dart';

class AudioPlayerStateTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get playing => boolean()();
  TextColumn get loopMode => textEnum<PlaylistMode>()();
  BoolColumn get shuffled => boolean()();
  TextColumn get collections => text().map(const StringListConverter())();
  TextColumn get tracks => text()
      .map(const SpotubeTrackObjectListConverter())
      .withDefault(const Constant("[]"))();
  IntColumn get currentIndex => integer().withDefault(const Constant(0))();
}

class SpotubeTrackObjectListConverter
    extends TypeConverter<List<SpotubeTrackObject>, String> {
  const SpotubeTrackObjectListConverter();

  @override
  List<SpotubeTrackObject> fromSql(String fromDb) {
    // A corrupt queue row must not break restore: quarantine to empty and
    // let the app start with no queue rather than throwing from the drift
    // converter (previously `as List` threw here).
    List<Map> raw;
    try {
      raw = (jsonDecode(fromDb) as List).cast<Map>();
    } catch (_) {
      return const <SpotubeTrackObject>[];
    }

    return PerfCounters.measured('queue.decode', () {
      PerfCounters.note('queue.decodeRows', raw.length);
      final tracks = <SpotubeTrackObject>[];
      for (final e in raw) {
        try {
          tracks.add(
            SpotubeTrackObject.fromJson(e.cast<String, dynamic>()),
          );
        } catch (_) {
          // Skip the single bad entry; keep the rest of the queue.
        }
      }
      return tracks;
    });
  }

  @override
  String toSql(List<SpotubeTrackObject> value) {
    return PerfCounters.measured('queue.encode', () {
      final encoded = jsonEncode(
        value.map((e) => e.toJson()).toList(),
      );
      PerfCounters.note('queue.encodeRows', value.length);
      PerfCounters.note('queue.encodeBytes', encoded.length);
      return encoded;
    });
  }
}
