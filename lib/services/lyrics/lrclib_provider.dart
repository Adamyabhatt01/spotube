import 'package:dio/dio.dart';
import 'package:lrc/lrc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/dio/dio.dart';

import 'lyrics_provider.dart';

/// LRCLib lyrics source.
///
/// Lyrics credits: [lrclib.net](https://lrclib.net) and their contributors.
class LRCLibLyricsProvider implements LyricsProvider {
  @override
  String get id => "LRCLib";

  @override
  Future<SubtitleSimple> fetchLyrics(SpotubeFullTrackObject track) async {
    final packageInfo = await PackageInfo.fromPlatform();

    final res = await globalDio.getUri(
      Uri(
        scheme: "https",
        host: "lrclib.net",
        path: "/api/get",
        queryParameters: {
          "artist_name": track.artists.isNotEmpty ? track.artists.first.name : "",
          "track_name": track.name,
          "album_name": track.album.name,
          if (track.durationMs > 0)
            "duration": (track.durationMs / 1000).toInt().toString(),
        },
      ),
      options: Options(
        headers: {
          "User-Agent":
              "Spotube v${packageInfo.version} (https://github.com/KRTirtho/spotube)"
        },
        responseType: ResponseType.json,
      ),
    );

    if (res.statusCode != 200) {
      return SubtitleSimple(
        lyrics: [],
        name: track.name,
        uri: res.realUri,
        rating: 0,
        provider: id,
      );
    }

    final json = res.data as Map<String, dynamic>;

    final syncedLyricsRaw = json["syncedLyrics"] as String?;
    final syncedLyrics = syncedLyricsRaw?.isNotEmpty == true
        ? Lrc.parse(syncedLyricsRaw!)
            .lyrics
            .map(LyricSlice.fromLrcLine)
            .toList()
        : null;

    if (syncedLyrics?.isNotEmpty == true) {
      return SubtitleSimple(
        lyrics: syncedLyrics!,
        name: track.name,
        uri: res.realUri,
        rating: 100,
        provider: id,
      );
    }

    final plainLyricsRaw = json["plainLyrics"] as String?;
    final plainLyrics = (plainLyricsRaw ?? "")
        .split("\n")
        .map((line) => LyricSlice(text: line, time: Duration.zero))
        .toList();

    return SubtitleSimple(
      lyrics: plainLyrics,
      name: track.name,
      uri: res.realUri,
      rating: 0,
      provider: id,
    );
  }
}