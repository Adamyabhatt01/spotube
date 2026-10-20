import 'package:uuid/uuid.dart';

abstract class PrimitiveUtils {
  static const uuid = Uuid();

  /// First character of [name], uppercased, or [fallback] for blank input.
  ///
  /// `name[0]` and shadcn's `Avatar.getInitials('')` both throw on empty
  /// metadata (local files and some plugin payloads have blank artist/owner
  /// names), so every initials site goes through this.
  static String initialOf(String? name, {String fallback = '?'}) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed[0].toUpperCase();
  }

  /// One or two uppercase initials for [name], safe for blank input.
  static String initialsOf(String? name, {String fallback = '?'}) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return fallback;

    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return fallback;

    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final first = parts.first;
    return (first.length > 1 ? first.substring(0, 2) : first).toUpperCase();
  }

  static String toReadableNumber(double num) {
    if (num > 999 && num < 99999) {
      return "${(num / 1000).toStringAsFixed(0)}K";
    } else if (num > 99999 && num < 999999) {
      return "${(num / 1000).toStringAsFixed(0)}K";
    } else if (num > 999999 && num < 999999999) {
      return "${(num / 1000000).toStringAsFixed(0)}M";
    } else if (num > 999999999) {
      return "${(num / 1000000000).toStringAsFixed(0)}B";
    } else {
      return num.toStringAsFixed(0);
    }
  }
}
