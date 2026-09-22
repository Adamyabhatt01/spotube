import 'package:html_unescape/html_unescape.dart';
import 'package:html/parser.dart';

/// [cleanHtml] parses a DOM per call and the card/tile builders run it on every
/// rebuild of every visible card, over the same handful of descriptions. The
/// map is a plain literal, so it stays insertion-ordered and the cap evicts the
/// oldest entry instead of growing for the length of a browse session.
final Map<String, String> _strippedDescriptions = {};
const int _strippedDescriptionLimit = 512;

extension CachedStrippedHtml on String? {
  /// `this.unescapeHtml().cleanHtml()`, memoized on the raw string.
  String strippedHtml() {
    final raw = this;
    if (raw == null || raw.isEmpty) return "";

    final hit = _strippedDescriptions[raw];
    if (hit != null) return hit;

    final cleaned = raw.unescapeHtml().cleanHtml();
    if (_strippedDescriptions.length >= _strippedDescriptionLimit) {
      _strippedDescriptions.remove(_strippedDescriptions.keys.first);
    }
    _strippedDescriptions[raw] = cleaned;
    return cleaned;
  }
}

final htmlEscape = HtmlUnescape();

extension UnescapeHtml on String {
  String cleanHtml() => parse("<p>$this</p>").documentElement!.text;
  String unescapeHtml() => htmlEscape.convert(this);
}

extension NullableUnescapeHtml on String? {
  String? cleanHtml() => this?.cleanHtml();
  String? unescapeHtml() => this?.unescapeHtml();
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
