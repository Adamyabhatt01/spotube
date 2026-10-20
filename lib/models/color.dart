import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The accent-color model: a color plus the display name it was picked by.
/// Lives in `lib/models/` (not in the picker dialog it used to sit in) so
/// the provider, database and theme layers can import it without a
/// provider→modules or models→modules inversion.
class SpotubeColor extends Color {
  final String name;

  const SpotubeColor(super.color, {required this.name});

  const SpotubeColor.from(super.value, {required this.name});

  factory SpotubeColor.fromString(String string) {
    final slices = string.split(":");
    return SpotubeColor(int.parse(slices.last), name: slices.first);
  }

  @override
  String toString() {
    return "$name:${toARGB32()}";
  }
}
