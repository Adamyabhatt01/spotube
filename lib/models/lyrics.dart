import 'package:lrc/lrc.dart';

class SubtitleSimple {
  Uri uri;
  String name;
  List<LyricSlice> lyrics;
  int rating;
  String provider;

  SubtitleSimple({
    required this.uri,
    required this.name,
    required this.lyrics,
    required this.rating,
    required this.provider,
  });

  /// Whether any line carries readable text. A provider that answers with a
  /// single blank line (an empty `plainLyrics` splits to `[""]`) is a miss,
  /// not a hit — treating it as a hit caches a permanently empty panel.
  bool get hasContent => lyrics.any((slice) => slice.text.trim().isNotEmpty);

  /// Whether at least one line is stamped past zero. Plain lyrics render fine
  /// but the synced view can never advance, so a synced source is preferred.
  bool get isSynced => lyrics.any((slice) => slice.time > Duration.zero);

  factory SubtitleSimple.fromJson(Map<String, dynamic> json) {
    return SubtitleSimple(
      uri: Uri.parse(json["uri"] as String),
      name: json["name"] as String,
      lyrics: (json["lyrics"] as List<dynamic>)
          .map((e) => LyricSlice.fromJson(e as Map<String, dynamic>))
          .toList(),
      rating: json["rating"] as int,
      provider: json["provider"] as String? ?? "unknown",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "uri": uri.toString(),
      "name": name,
      "lyrics": lyrics.map((e) => e.toJson()).toList(),
      "rating": rating,
      "provider": provider,
    };
  }
}

class LyricSlice {
  Duration time;
  String text;

  LyricSlice({required this.time, required this.text});

  factory LyricSlice.fromLrcLine(LrcLine line) {
    return LyricSlice(
      time: line.timestamp,
      text: line.lyrics.trim(),
    );
  }

  factory LyricSlice.fromJson(Map<String, dynamic> json) {
    return LyricSlice(
      time: Duration(milliseconds: json["time"]),
      text: json["text"] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "time": time.inMilliseconds,
      "text": text,
    };
  }

  @override
  String toString() {
    return "LyricsSlice({time: $time, text: $text})";
  }
}
