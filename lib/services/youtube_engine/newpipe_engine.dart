import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart'
    hide Engagement;
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/utils/platform.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http_parser/http_parser.dart';

typedef NewPipeSearch = Future<List<SearchResultItem>> Function(
  String query,
  List<SearchContentFilters> contentFilters,
);

class NewPipeEngine implements YouTubeEngine {
  NewPipeEngine({NewPipeSearch? search}) : _search = search ?? _defaultSearch;

  final NewPipeSearch _search;

  static Future<List<SearchResultItem>> _defaultSearch(
    String query,
    List<SearchContentFilters> contentFilters,
  ) =>
      NewPipeExtractor.search(query, contentFilters: contentFilters);

  static bool get isAvailableForPlatform => kIsAndroid || kIsDesktop;

  AudioOnlyStreamInfo _parseAudioStream(AudioStream stream, String videoId) {
    return AudioOnlyStreamInfo(
      VideoId(videoId),
      stream.itag,
      Uri.parse(stream.content),
      StreamContainer.parse(stream.mediaFormat!.mimeType.split("/").last),
      FileSize.unknown,
      Bitrate(stream.bitrate),
      stream.codec,
      switch (stream.bitrate) {
        > 130 * 1024 => "high",
        > 64 * 1024 => "medium",
        _ => "low",
      },
      [],
      MediaType.parse(stream.mediaFormat!.mimeType),
      null,
    );
  }

  AudioOnlyStreamInfo _parseVideoStream(VideoStream stream, String videoId) {
    return AudioOnlyStreamInfo(
      VideoId(videoId),
      stream.itag,
      Uri.parse(stream.content),
      StreamContainer.parse(stream.mediaFormat!.mimeType.split("/").last),
      FileSize.unknown,
      Bitrate(stream.bitrate),
      stream.codec,
      switch (stream.bitrate) {
        > 130 * 1024 => "high",
        > 64 * 1024 => "medium",
        _ => "low",
      },
      [],
      MediaType.parse(stream.mediaFormat!.mimeType),
      null,
    );
  }

  Video _parseVideo(VideoInfo info) {
    return Video(
      VideoId(info.id),
      info.name,
      info.uploaderName,
      ChannelId(info.uploaderUrl),
      info.uploadDate.offsetDateTime,
      info.uploadDate.offsetDateTime.toString(),
      info.uploadDate.offsetDateTime,
      info.description.content ?? "",
      Duration(seconds: info.duration),
      ThumbnailSet(info.id),
      info.tags,
      Engagement(
        info.viewCount,
        info.likeCount,
        info.dislikeCount,
      ),
      !info.streamType.name.toLowerCase().contains("live"),
    );
  }

  static YouTubeSearchResult? parseSearchResult(VideoSearchResultItem info) {
    // A row whose url is not a watch URL cannot be streamed, but it says
    // nothing about the rest of the page: dropping it keeps one odd row
    // from costing the whole search.
    final id = Uri.tryParse(info.url)?.queryParameters["v"];
    if (id == null || id.isEmpty) return null;

    final streamType = info.streamType.name.toLowerCase();
    return YouTubeSearchResult(
      id: id,
      title: info.name,
      author: info.uploaderName,
      // NewPipe reports an unknown duration as -1, which is non-null in its
      // own model. Handing that through built a "duration of minus one
      // second" that then read as a real, extremely short track.
      duration:
          info.duration > 0 ? Duration(seconds: info.duration) : null,
      description: info.shortDescription,
      uploadDate: info.uploadDate?.offsetDateTime,
      viewCount: info.viewCount,
      isLive: streamType.contains("live"),
      isShortForm: info.shortFormContent,
    );
  }

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    final video = await withinEngineCallBudget(
      'newpipe.getStreamManifest',
      () => NewPipeExtractor.getVideoInfo(videoId),
    );

    final streams =
        video.audioStreams.map((stream) => _parseAudioStream(stream, videoId));

    if (streams.isEmpty) {
      final videoStreams = video.videoStreams
          .map((stream) => _parseVideoStream(stream, videoId));
      if (videoStreams.isNotEmpty) {
        return StreamManifest(videoStreams);
      }
    }

    return StreamManifest(streams);
  }

  @override
  Future<Video> getVideo(String videoId) async {
    final video = await withinEngineCallBudget(
      'newpipe.getVideo',
      () => NewPipeExtractor.getVideoInfo(videoId),
    );

    return _parseVideo(video);
  }

  @override
  Future<List<YouTubeSearchResult>> searchVideos(String query) async {
    return withinEngineCallBudget('newpipe.searchVideos', () async {
      // The `videos` filter is load-bearing, not an optimization: NewPipe's
      // channel rows carry `description` as a plain String, and
      // flutter_new_pipe_extractor's ChannelSearchResultItem.fromJson casts it
      // to Map<String, dynamic> - so a single channel row makes the whole
      // search throw. Unfiltered, "Wassup Flawed" returns 5 such rows; with the
      // filter it returns 0. Recall for credit-noisy queries is recovered by
      // SourcedTrack.matchWithQueryVariants instead. `music_songs` was measured
      // over the same pages and also returns 0 channel rows.
      //
      // An ISRC keeps going to `videos` alone. YouTube treats it as free text,
      // so the songs category answers a junk page of 11-20 unrelated songs where
      // the videos category correctly answers nothing - and a clean empty answer
      // is exactly what lets the plugin fall back to the text query. Turning a
      // miss into a confident wrong match is the one regression to avoid here.
      if (_isIsrcQuery(query)) {
        return _parseRows(await _search(query, _videoFilters));
      }

      final List<YouTubeSearchResult> songs;
      try {
        songs = _parseRows(await _search(query, _songFilters));
      } catch (_) {
        // A songs page that fails outright should cost nothing but the extra
        // call: `videos` is the page this engine used unconditionally before and
        // remains correct.
        return _parseRows(await _search(query, _videoFilters));
      }

      if (!_isIrrelevantSongsPage(query, songs)) return songs;

      // Merged, not replaced: tracks outside the YouTube Music catalog only
      // exist in the videos page, so recall is kept.
      final videos = _parseRows(await _search(query, _videoFilters));
      return orderTiers(query: query, songs: songs, videos: videos);
    });
  }

  /// Places the two tiers against each other and drops rows the other tier
  /// already carried, keeping the first copy seen.
  static List<YouTubeSearchResult> orderTiers({
    required String query,
    required List<YouTubeSearchResult> songs,
    List<YouTubeSearchResult> videos = const [],
  }) {
    final rankedVideos = _rankVideoTier(videos, _tokens(query));
    // The category earns first place only when it actually answered the query.
    final songsLead = !_isIrrelevantSongsPage(query, songs);
    final seen = <String>{};

    return [
      ...(songsLead ? songs : rankedVideos),
      ...(songsLead ? rankedVideos : songs),
    ].where((row) => seen.add(row.id)).toList();
  }

  /// Demoted, never dropped: a page whose only candidate is a live version is
  /// still the song, and this search has already lost its best row once to
  /// over-strict parsing.
  static List<YouTubeSearchResult> _rankVideoTier(
    List<YouTubeSearchResult> videos,
    Set<String> queryTokens,
  ) {
    // Indexed tiebreak: List.sort is not stable, and YouTube's own page order
    // is a quality signal worth preserving among equals.
    final scored = [
      for (var i = 0; i < videos.length; i++)
        (row: videos[i], score: _videoTierScore(videos[i], queryTokens), index: i),
    ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.index.compareTo(b.index);
      });

    return scored.map((entry) => entry.row).toList();
  }

  static int _videoTierScore(
    YouTubeSearchResult row,
    Set<String> queryTokens,
  ) {
    var score = 0;
    if (row.isLive == true) score -= 6;
    if (row.isShortForm == true) score -= 6;
    if (row.duration == null) score -= 3;
    // "Original channel" means the one the query names. The verification badge
    // is not that signal: studio uploads sit on unverified auto-generated
    // channels while lyric channels are verified.
    if (_tokens(row.author).any(queryTokens.contains)) score += 2;
    return score;
  }

  /// Whether the songs page failed to answer [query] at all.
  ///
  /// A `"<title> <artist>"` query has one token that reliably appears in a
  /// video title and one that usually appears in none, so for a short query a
  /// single match counts as a hit: "Wassup Flawed" -> "Wassup", and "Dynamite
  /// BTS" -> "Dynamite". Held to two matches from three tokens up, where a
  /// single shared word is more often the artist and every row a different
  /// song.
  static bool _isIrrelevantSongsPage(
    String query,
    List<YouTubeSearchResult> songs,
  ) {
    if (songs.isEmpty) return true;

    final queryTokens = _tokens(query);
    final best = songs
        .map((row) => _tokens(row.title).intersection(queryTokens).length)
        .fold<int>(0, (a, b) => b > a ? b : a);

    if (queryTokens.length >= 3) return best < 2;
    return best == 0;
  }

  static final _wordRegex = RegExp(r'[a-z0-9]+');

  static Set<String> _tokens(String value) => _wordRegex
      .allMatches(value.toLowerCase())
      .map((match) => match[0]!)
      .where((word) => word.length > 1)
      .toSet();

  /// ISRC: 2-letter country, 3-char registrant, 2-digit year, 5-digit
  /// designation. Anchored, so any query with a space in it is prose.
  static final _isrcRegex =
      RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{2}[0-9]{5}$', caseSensitive: false);

  static bool _isIsrcQuery(String query) => _isrcRegex.hasMatch(query.trim());

  static const List<SearchContentFilters> _songFilters = [
    SearchContentFilters.musicSongs,
  ];

  static const List<SearchContentFilters> _videoFilters = [
    SearchContentFilters.videos,
  ];

  List<YouTubeSearchResult> _parseRows(List<SearchResultItem> results) {
    return results
        .whereType<VideoSearchResultItem>()
        .map(parseSearchResult)
        .nonNulls
        .toList();
  }
}
