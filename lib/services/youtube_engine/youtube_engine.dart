import 'dart:async';

import 'package:spotube/utils/perf_counters.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

abstract interface class YouTubeEngine {
  Future<Video> getVideo(String videoId);
  Future<StreamManifest> getStreamManifest(String videoId);
  Future<List<YouTubeSearchResult>> searchVideos(String query);
}

/// Wall-clock ceiling for a single call into a YouTube backend.
///
/// NewPipe and yt-dlp shell out to a CLI through `Process.run`, which exposes
/// no handle, and explode waits on an isolate reply. None of those cancel on
/// their own, so an unresponsive backend hung the caller forever. A timeout
/// here abandons the await: the process or isolate keeps running to its own
/// completion and its answer is discarded.
const engineCallBudget = Duration(seconds: 15);

/// Runs one engine [request] under [engineCallBudget], timing it either way.
Future<T> withinEngineCallBudget<T>(
  String call,
  Future<T> Function() request,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    return await request().timeout(engineCallBudget);
  } on TimeoutException {
    PerfCounters.note('engine.$call.timeout');
    rethrow;
  } finally {
    PerfCounters.time('engine.$call', stopwatch.elapsed);
  }
}

/// One row of a search result page.
///
/// Deliberately not [Video]: that model requires a parseable [ChannelId] and a
/// non-null view count, while search pages legitimately omit both. A yt-dlp
/// flat-playlist row for a music upload comes back with `channel_id: null`,
/// and music uploads are precisely where the wanted video usually lives — so
/// building a [Video] there made the whole page fail on its best candidate.
/// Search therefore only carries fields every provider can answer.
class YouTubeSearchResult {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String? description;
  final DateTime? uploadDate;
  final int? viewCount;
  final int? likeCount;
  final bool? isLive;

  /// A YouTube Short. Only some providers can answer this, so it is nullable.
  final bool? isShortForm;

  const YouTubeSearchResult({
    required this.id,
    required this.title,
    required this.author,
    this.duration,
    this.description,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.isLive,
    this.isShortForm,
  });

  factory YouTubeSearchResult.fromVideo(Video video) {
    return YouTubeSearchResult(
      id: video.id.value,
      title: video.title,
      author: video.author,
      duration: video.duration,
      description: video.description,
      uploadDate: video.uploadDate,
      viewCount: video.engagement.viewCount,
      likeCount: video.engagement.likeCount,
      isLive: video.isLive,
    );
  }
}
