part of '../database.dart';

/// Comma-joined [List<double>]. Unlike [StringListConverter] this keeps the
/// numeric type, and malformed tokens are dropped instead of poisoning the
/// whole preference row.
class DoubleListConverter extends TypeConverter<List<double>, String> {
  const DoubleListConverter();

  @override
  List<double> fromSql(String fromDb) {
    final result = <double>[];
    for (final token in fromDb.split(',')) {
      final parsed = double.tryParse(token.trim());
      if (parsed != null && parsed.isFinite) result.add(parsed);
    }
    return result;
  }

  @override
  String toSql(List<double> value) => value.join(',');
}
