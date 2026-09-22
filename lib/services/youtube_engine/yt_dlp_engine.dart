import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/utils/platform.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:yt_dlp_dart/yt_dlp_dart.dart';
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';

class YtDlpEngine implements YouTubeEngine {
  StreamManifest _parseFormats(List formats, videoId) {
    final audioOnlyStreams = formats
        .where((f) => f["resolution"] == "audio only")
        .sorted((a, b) => a["quality"] > b["quality"] ? 1 : -1)
        .map((f) {
      final filesize = f["filesize"] ?? f["filesize_approx"];
      return AudioOnlyStreamInfo(
        VideoId(videoId),
        0,
        Uri.parse(f["url"]),
        StreamContainer.parse(
          f["container"]?.replaceAll("_dash", "").replaceAll("m4a", "mp4") ??
              (f["protocol"] == "m3u8_native" ? "m3u8" : "mp4"),
        ),
        filesize != null ? FileSize(filesize) : FileSize.unknown,
        Bitrate(
          (((f["abr"] ?? f["tbr"] ?? 0) * 1000) as num).toInt(),
        ),
        f["acodec"] ?? "aac",
        f["format_note"],
        [],
        MediaType.parse(
          "audio/${f["audio_ext"]}",
        ),
        null,
      );
    });

    return StreamManifest(audioOnlyStreams);
  }

  Video _parseInfo(Map<String, dynamic> info) {
    final publishDate = info["upload_date"] != null
        ? DateTime.fromMillisecondsSinceEpoch(
            int.parse(info["upload_date"]) * 1000,
          )
        : DateTime.now();
    return Video(
      VideoId(info["id"]),
      info["title"],
      info["channel"],
      ChannelId(info["channel_id"]),
      publishDate,
      info["upload_date"] as String? ?? DateTime.now().toString(),
      publishDate,
      info["description"] ?? "",
      Duration(seconds: (info["duration"] as num).toInt()),
      ThumbnailSet(info["id"]),
      info["tags"]?.cast<String>() ?? <String>[],
      Engagement(
        info["view_count"],
        info["like_count"],
        null,
      ),
      info["is_live"] ?? false,
    );
  }

  static bool get isAvailableForPlatform => kIsDesktop;

  static const String binaryName = 'yt-dlp';

  /// Install directories that a GUI-launched process is usually never told
  /// about. A desktop session hands out a PATH built for packaged programs,
  /// so the most common way of installing yt-dlp on Linux — `pip --user`,
  /// `uv tool install`, `pipx`, all of which land in `~/.local/bin` — leaves
  /// the app reporting the engine missing and every call through it failing,
  /// with the binary sitting right there.
  static List<String> commonInstallDirs(Map<String, String> environment) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    if (kIsWindows) {
      final localAppData = environment['LOCALAPPDATA'];
      return [
        if (localAppData != null)
          p.join(localAppData, 'Microsoft', 'WinGet', 'Links'),
        if (home != null) p.join(home, 'scoop', 'shims'),
      ];
    }
    return [
      if (home != null) p.join(home, '.local', 'bin'),
      if (home != null) p.join(home, 'bin'),
      if (home != null) p.join(home, '.cargo', 'bin'),
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/opt/local/bin',
      '/snap/bin',
      '/usr/bin',
    ];
  }

  /// Absolute path to a usable yt-dlp, or null if there is none.
  ///
  /// [fallbackDirs] exists for tests; production callers want the default,
  /// which is [commonInstallDirs] for [environment].
  static Future<String?> resolveBinaryPath({
    Map<String, String>? environment,
    List<String>? fallbackDirs,
  }) async {
    final env = environment ?? Platform.environment;
    final binary = kIsWindows ? '$binaryName.exe' : binaryName;
    final searchedDirs = <String>[
      ...?env['PATH']?.split(kIsWindows ? ';' : ':'),
      ...fallbackDirs ?? commonInstallDirs(env),
    ];

    for (final dir in searchedDirs) {
      if (dir.isEmpty) continue;
      final file = File(p.join(dir, binary));
      if (await file.exists()) return file.path;
    }
    return null;
  }

  static Future<bool> isInstalled() async {
    return isAvailableForPlatform && await resolveBinaryPath() != null;
  }

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    final formats = await YtDlp.instance.extractInfo(
      "https://www.youtube.com/watch?v=$videoId",
      formatSpecifiers: "%(formats)j",
      extraArgs: [
        "--no-check-certificate",
        "--geo-bypass",
        "--quiet",
        "--ignore-errors"
      ],
    ) as List;

    return _parseFormats(formats, videoId);
  }

  @override
  Future<Video> getVideo(String videoId) async {
    final info = await YtDlp.instance.extractInfo(
      "https://www.youtube.com/watch?v=$videoId",
      formatSpecifiers: "%()j",
      extraArgs: [
        "--skip-download",
        "--no-check-certificate",
        "--geo-bypass",
        "--quiet",
        "--ignore-errors",
      ],
    ) as Map<String, dynamic>;

    return _parseInfo(info);
  }

  @override
  Future<(Video, StreamManifest)> getVideoWithStreamInfo(String videoId) async {
    final info = await YtDlp.instance.extractInfo(
      "https://www.youtube.com/watch?v=$videoId",
      formatSpecifiers: "%()j",
      extraArgs: [
        "--no-check-certificate",
        "--geo-bypass",
        "--quiet",
        "--ignore-errors",
      ],
    ) as Map<String, dynamic>;

    return (_parseInfo(info), _parseFormats(info["formats"], videoId));
  }

  @override
  Future<List<Video>> searchVideos(String query) async {
    final stdout = await YtDlp.instance.extractInfoString(
      "ytsearch10:$query",
      formatSpecifiers: "%()j",
      extraArgs: [
        "--skip-download",
        "--no-check-certificate",
        "--geo-bypass",
        "--quiet",
        "--ignore-errors",
        "--flat-playlist",
        "--no-playlist",
      ],
    );

    final json = jsonDecode(
      "[${stdout.split("\n").where((s) => s.trim().isNotEmpty).join(",")}]",
    ) as List;

    return json.map((e) => _parseInfo(e)).toList();
  }

  @override
  void dispose() {}
}
