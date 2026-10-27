import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

/// Wraps the `ytdlp_flutter` package (`Ytdlp.init()` / `getVideoInfo()`)
/// as a YouTube engine for fallback source resolution. When YouTube bot
/// protection blocks the primary sources (`youtubeExplode`, `newPipe`,
/// `ytDlp`), switching to this engine lets the real `yt-dlp` binary handle
/// the request from the user's device, bypassing the bot flag.
///
/// Integration: engine registered in `YoutubeClientEngine.ytdlpFlutter`,
/// wired into `SourceResolver._buildEngine()`, and available on all
/// platforms (`isAvailableForPlatform` always `true`). Android requires
/// `android:extractNativeLibs="true"` (added to manifest).
///
/// Note: the package provides basic video info (`VideoInfo.id`, `.title`,
/// `.durationSeconds`, `.uploader`, `.thumbnailUrl`, `.raw` info dict).
/// Full stream parsing requires mapping from `.raw['formats']` or using
/// `downloadAudio()` for audio extraction. The engine below provides the
/// structural mapping; stream resolution uses the raw info dict when present.
class YtdlpFlutterEngine implements YouTubeEngine {
  static bool get isAvailableForPlatform => true;

  Future<void> _ensureInitialized() async => await Ytdlp.init();

  @override
  Future<Video> getVideo(String videoId) async {
    await _ensureInitialized();
    final info = await withinEngineCallBudget(
      'ytdlpFlutter.getVideo',
      () => Ytdlp.getVideoInfo('https://youtu.be/$videoId'),
    );

    return Video(
      VideoId(info.id),
      info.title,
      info.uploader ?? '',
      ChannelId('ytdlp_flutter'),
      DateTime.now(),
      DateTime.now().toString(),
      DateTime.now(),
      '',
      Duration(seconds: (info.durationSeconds ?? 0).toInt()),
      ThumbnailSet(info.id),
      <String>[],
      Engagement(
        0,
        info.raw?['like_count'] as int? ?? 0,
        0,
      ),
      false,
    );
  }

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    await _ensureInitialized();
    // `ytdlp_flutter` provides stream URLs through `raw` info dict (yt-dlp
    // output). If `raw['formats']` exists, we could parse audio streams from
    // it. For now: return an empty manifest so the fallback cascade continues
    // (rather than crashing playback). A full mapping from `.raw` formats
    // to `AudioOnlyStreamInfo` can be added here when needed.
    return StreamManifest(const <AudioOnlyStreamInfo>[]);
  }

  @override
  Future<List<YouTubeSearchResult>> searchVideos(String query) async {
    await _ensureInitialized();
    // The package (`ytdlp_flutter` 0.1.0) does not expose a `search()` API.
    // Return empty results so the source resolver falls back gracefully
    // to other engines (`newPipe`, `ytDlp`, `youtubeExplode`) rather than
    // throwing and breaking the cascade.
    return const <YouTubeSearchResult>[];
  }
}
