part of '../database.dart';

class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    // Some installs wrote the raw plugin.json array (`["theme"]`) into the
    // column instead of the comma-joined names; decode that form too so the
    // row's abilities/apis still resolve.
    final trimmed = fromDb.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
    return fromDb.split(",").where((e) => e.isNotEmpty).toList();
  }

  @override
  String toSql(List<String> value) {
    return value.join(",");
  }
}
