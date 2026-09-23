import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:dio/dio.dart' as dio_lib;
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/parser/range_headers.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';

import 'package:spotube/provider/server/active_track_sources.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/playback_cache_mirror.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/utils/service_utils.dart';
import 'package:spotube/utils/stream_url_expiry.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// NOTE: `android` is deliberately excluded — ANDROID client streams are 403'd
// by YouTube (see .ai/AUDIT_STATE.md), and signing googlevideo URLs to a
// different client here re-introduces the same rejection at the proxy hop.
final _deviceClients = Set.unmodifiable({
  YoutubeApiClient.ios,
  YoutubeApiClient.mweb,
  YoutubeApiClient.safari,
});

String? get _randomUserAgent => _deviceClients
    .elementAt(
      Random().nextInt(_deviceClients.length),
    )
    .payload["context"]["client"]["userAgent"];

/// Signed CDN URLs are host-bound: every fetch must carry the `Host` of the
/// URL it is requesting, never the primary URL's host.
@visibleForTesting
Map<String, dynamic> headersWithHost(String url, Map<String, dynamic> base) {
  return {...base, "host": Uri.parse(url).host};
}

/// Builds the cached-file download response WITHOUT loading the file
/// into memory: the body is a lazily-read byte stream, so large cached
/// tracks (FLAC) no longer spike the heap per request. The caller
/// ([ServerPlaybackRoutes.getStreamTrackId]) forwards stream bodies
/// directly to shelf, which serves them chunked with no re-buffering.
///
/// Honors a client `Range: bytes=start-end` request (206 + partial body);
/// mpv issues ranged reads when seeking, so ignoring Range would serve the
/// wrong audio position. `content-length` must be the exact served byte
/// count — never `fileLength - 1` for the full body — or strict HTTP
/// clients (dart:io, curl) abort with "content size exceeds contentLength".
dio_lib.Response<Stream<List<int>>> cachedFileStreamResponse({
  required File file,
  required int fileLength,
  required String contentType,
  required String requestPath,
  String? rangeHeader,
}) {
  RangeHeader? range;
  if (rangeHeader != null) {
    try {
      range = RangeHeader.parse(rangeHeader);
    } on FormatException {
      range = null; // malformed Range: fall back to the full body
    }
  }

  if (range != null && range.start < fileLength) {
    final start = range.start;
    final end = min(range.end ?? fileLength - 1, fileLength - 1);

    return dio_lib.Response<Stream<List<int>>>(
      statusCode: 206,
      headers: Headers.fromMap({
        "content-type": [contentType],
        "content-length": ["${end - start + 1}"],
        "accept-ranges": ["bytes"],
        "content-range": ["bytes $start-$end/$fileLength"],
        "connection": ["close"],
      }),
      requestOptions: RequestOptions(path: requestPath),
      data: file.openRead(start, end + 1),
    );
  }

  return dio_lib.Response<Stream<List<int>>>(
    statusCode: 200,
    headers: Headers.fromMap({
      "content-type": [contentType],
      "content-length": ["$fileLength"],
      "accept-ranges": ["bytes"],
      "content-range": ["bytes 0-${fileLength - 1}/$fileLength"],
      "connection": ["close"],
    }),
    requestOptions: RequestOptions(path: requestPath),
    data: file.openRead(),
  );
}

/// Header-only response describing a local file, mirroring what
/// [cachedFileStreamResponse] serves for the body. Used by HEAD requests
/// so the response headers match the GET body exactly.
dio_lib.Response cachedFileHeadResponse({
  required int fileLength,
  required String contentType,
  required String requestPath,
}) {
  return dio_lib.Response(
    statusCode: 200,
    headers: Headers.fromMap({
      "content-type": [contentType],
      "content-length": ["$fileLength"],
      "accept-ranges": ["bytes"],
      "content-range": ["bytes 0-${fileLength - 1}/$fileLength"],
    }),
    requestOptions: RequestOptions(path: requestPath),
  );
}

/// The on-disk base name (extension-agnostic) the downloader writes for
/// [track] — the same string `_savePathFor` builds before appending the
/// container extension.
String downloadedFileBaseName(SpotubeFullTrackObject track) {
  return ServiceUtils.sanitizeFilename(
    "${track.name} - ${track.artists.map((e) => e.name).join(", ")}",
  );
}

/// A `base name -> file` index of the download directory, kept between
/// requests.
///
/// mpv asks the proxy for a track's length (HEAD) and then for every byte
/// range it plays, so the listing this replaced ran on each of those requests:
/// a downloaded track re-walked the folder on every seek.
///
/// Invalidation is the directory's own mtime plus the location it belongs to —
/// creating, deleting and renaming an entry all write the containing directory.
/// Because Dart reports that timestamp in milliseconds, a lookup that fails to
/// hit re-lists before answering "not downloaded", and a hit re-checks that the
/// file is still there. A miss therefore still costs one walk, exactly as
/// before; only hits became cheap, and no download can be shadowed by a stale
/// entry.
class DownloadedFileIndex {
  String? _location;
  DateTime? _modifiedAt;
  Map<String, File> _byBaseName = const {};

  /// How many times the directory has actually been listed. Test seam: lets a
  /// test assert that repeated hits are served from the index.
  @visibleForTesting
  int listingCount = 0;

  Future<Map<String, File>> _list(Directory dir) async {
    listingCount++;
    final byBaseName = <String, File>{};
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          byBaseName[basenameWithoutExtension(entity.path)] = entity;
        }
      }
    } on FileSystemException {
      // Unreadable (or not a directory): treat it as empty for this request.
    }
    return byBaseName;
  }

  /// Finds a user-downloaded file for [track] in [location], if one exists.
  Future<File?> find(String location, SpotubeFullTrackObject track) async {
    if (location.isEmpty) return null;
    final dir = Directory(location);
    final DateTime modifiedAt;
    try {
      modifiedAt = (await dir.stat()).modified;
    } on FileSystemException {
      return null;
    }

    final base = downloadedFileBaseName(track);
    if (_location != location || _modifiedAt != modifiedAt) {
      _location = location;
      _modifiedAt = modifiedAt;
      _byBaseName = await _list(dir);
    }
    final cached = _byBaseName[base];
    // One stat is far cheaper than a walk, and it closes the hole left by
    // millisecond-granular directory mtime: a file deleted in the same
    // millisecond the index was built would otherwise still be served.
    if (cached != null && await cached.exists()) return cached;

    _byBaseName = await _list(dir);
    return _byBaseName[base];
  }
}

final _downloadedFiles = DownloadedFileIndex();

/// Finds a user-downloaded file for [track] in [downloadLocation], if one
/// exists. Matches on the sanitized base name (extension-agnostic), the
/// same naming the downloader writes, so any downloaded codec resolves.
Future<File?> findDownloadedFile(
  String downloadLocation,
  SpotubeFullTrackObject track,
) =>
    _downloadedFiles.find(downloadLocation, track);

class ServerPlaybackRoutes {
  final Ref ref;
  UserPreferences get userPreferences => ref.read(userPreferencesProvider);
  AudioPlayerState get playlist => ref.read(audioPlayerProvider);
  final Dio dio;

  ServerPlaybackRoutes(this.ref)
      : dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
        )) {
    if (kPerfCountersEnabled) {
      dio.interceptors.add(const _UpstreamRequestCounter());
    }
  }

  /// How long an upstream HEAD answer may stand in for the next request for the
  /// same URL. mpv probes a stream with HEAD and asks for its body moments
  /// later; the window only has to cover that gap.
  static const headProbeReuseWindow = Duration(seconds: 5);

  /// Content types answered by a recent HEAD, keyed by `track id|url`.
  final Map<String, _HeadProbe> _headProbes = {};

  static String _headProbeKey(SourcedTrack track, String url) =>
      '${track.query.id}|$url';

  /// The content type a recent HEAD established for this exact URL, or null if
  /// there is no usable answer. A URL is signed and immutable, so what it
  /// served a moment ago is what it serves now — and a re-signed stream has a
  /// different key, which is why no length or type can survive a URL change.
  String? _reuseHeadProbe(SourcedTrack track, String url) {
    final key = _headProbeKey(track, url);
    final probe = _headProbes[key];
    if (probe == null) return null;

    if (DateTime.now().difference(probe.probedAt) > headProbeReuseWindow) {
      _headProbes.remove(key);
      return null;
    }
    PerfCounters.note('playback.headProbeReused');
    return probe.contentType;
  }

  void _rememberHeadProbe(SourcedTrack track, String url, String? contentType) {
    if (contentType == null) return;

    // Only ever a handful of live tracks; drop the lot rather than track ages.
    if (_headProbes.length > 16) _headProbes.clear();
    _headProbes[_headProbeKey(track, url)] =
        _HeadProbe(contentType, DateTime.now());
  }

  /// How long a computed fallback list may stand in for the next one. The HEAD
  /// preflight and the stream GET ask seconds apart, for the same broken
  /// stream; past that gap the cascade may have new information.
  static const fallbackUrlsReuseWindow = Duration(seconds: 5);

  /// Fallback lists already built, keyed by `track id|primary url`.
  final Map<String, _FallbackUrls> _fallbackUrlLists = {};

  /// [playbackFallbackUrls] with the one cost both failure paths share. The
  /// key is the primary URL, so a re-signed stream misses rather than reusing
  /// a list resolved against a dead URL.
  ///
  /// Public only so the memo can be driven the way both handlers drive it;
  /// nothing outside this file calls it.
  @visibleForTesting
  Future<List<String>> fallbackUrlsFor(SourcedTrack track) async {
    final primaryUrl = track.url;
    final key = primaryUrl == null ? null : _headProbeKey(track, primaryUrl);

    final memo = key == null ? null : _fallbackUrlLists[key];
    if (memo != null &&
        DateTime.now().difference(memo.computedAt) <=
            fallbackUrlsReuseWindow) {
      PerfCounters.note('playback.fallbackUrlsReused');
      return memo.urls;
    }

    final urls = await playbackFallbackUrls(ref, track);
    if (key != null) {
      // Same bound as the HEAD probes: a handful of live tracks, cleared
      // wholesale rather than aged.
      if (_fallbackUrlLists.length > 16) _fallbackUrlLists.clear();
      _fallbackUrlLists[key] = _FallbackUrls(urls, DateTime.now());
    }
    return urls;
  }

  Future<String> _getTrackCacheFilePath(SourcedTrack track) async {
    PerfCounters.note('playback.musicCacheDirLookup');
    return join(
      await UserPreferencesNotifier.getMusicCacheDir(),
      ServiceUtils.sanitizeFilename(
        '${track.query.name} - ${track.query.artists.map((d) => d.name).join(",")} (${track.info.id}).${track.qualityPreset!.getFileExtension()}',
      ),
    );
  }

  /// Selects the stream URL to serve for [track], proactively refreshing
  /// once when the selected URL's `expire` timestamp is already past.
  ///
  /// Phase 2 perf: without this, the first request after URL expiry pays a
  /// failed proxied HEAD plus a full refresh before audio starts. URLs with
  /// unknown expiry (missing/malformed/non-positive `expire`) take the
  /// existing path unchanged. Any refresh failure falls back to the stale
  /// URL so the existing reactive HEAD-failure path keeps working — worst
  /// case is today's behavior, never a new retry loop.
  Future<String> resolveServingUrl(SourcedTrack track) async {
    String url = track.url ??
        await ref
            .read(sourcedTrackProvider(track.query).notifier)
            .swapWithNextSibling()
            .then((track) => track.url!);

    if (isStreamUrlExpired(url)) {
      try {
        final refreshed = await ref
            .read(sourcedTrackProvider(track.query).notifier)
            .refreshStreamingUrl();
        final freshUrl = refreshed.url;
        if (freshUrl != null) {
          url = freshUrl;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    }

    return url;
  }

  /// The resolved source for the queue entry with [trackId], or null when the
  /// queue no longer holds it.
  ///
  /// Deliberately keyed off the app-side queue rather than off
  /// `audioPlayer.playlist.medias`: the backend rebuilds those as bare
  /// `Media(uri)` on `setShuffle`, so their `extras` payload — the only place
  /// the track object is stored — is gone, and a shuffle toggle used to make
  /// this route throw for every track it served.
  Future<SourcedTrack?> _getSourcedTrack(String trackId) async {
    final track =
        playlist.tracks.firstWhere((element) => element.id == trackId);

    final activeSourcedTrack =
        await ref.read(activeTrackSourcesProvider.future);

    return activeSourcedTrack?.track.id == track.id
        ? activeSourcedTrack?.source
        : await ref.read(
            sourcedTrackProvider(track as SpotubeFullTrackObject).future,
          );
  }

  Future<dio_lib.Response> streamTrackInformation(
    Request request,
    SourcedTrack track,
  ) async {
    AppLogger.log.i(
      "HEAD request for track: ${track.query.name}\n"
      "Headers: ${request.headers}",
    );

    final trackCacheFile = File(await _getTrackCacheFilePath(track));

    if (await trackCacheFile.exists() && userPreferences.cacheMusic) {
      final fileLength = await trackCacheFile.length();

      return cachedFileHeadResponse(
        fileLength: fileLength,
        contentType: "audio/${track.qualityPreset!.name}",
        requestPath: request.requestedUri.toString(),
      );
    }

    String url = await resolveServingUrl(track);

    final options = Options(
      headers: {
        "user-agent": _randomUserAgent,
        "Cache-Control": "max-age=3600",
        "Connection": "keep-alive",
      },
      validateStatus: (status) => status! < 400,
    );

    // HEAD preflight is advisory. Try the primary URL first; only on failure
    // lazily resolve the cascade so the success path never builds plugins.
    try {
      final res = await dio.head(
        url,
        options: options.copyWith(
          headers: {
            ...?options.headers,
            "host": Uri.parse(url).host,
          },
        ),
      );
      // The GET that follows would otherwise ask for this same answer again.
      _rememberHeadProbe(track, url, res.headers.value("content-type"));
      return res;
    } catch (_) {
      // fall through to cascade
    }

    Object? lastError;
    StackTrace? lastStack;
    for (final candidateUrl in await fallbackUrlsFor(track)) {
      if (candidateUrl == url) continue;
      try {
        final res = await dio.head(
          candidateUrl,
          options: options.copyWith(
            headers: {
              ...?options.headers,
              "host": Uri.parse(candidateUrl).host,
            },
          ),
        );
        return res;
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
      }
    }

    if (lastError case final Object error) {
      Error.throwWithStackTrace(error, lastStack ?? StackTrace.current);
    }
    throw Exception("All HEAD sources failed for ${track.query.name}");
  }

  Future<dio_lib.Response> streamTrack(
    Request request,
    SourcedTrack track,
    Map<String, dynamic> headers,
  ) async {
    AppLogger.log.i(
      "GET request for track: ${track.query.name}\n"
      "Headers: ${request.headers}",
    );

    final trackCacheFile = File(await _getTrackCacheFilePath(track));

    if (await trackCacheFile.exists() && userPreferences.cacheMusic) {
      final cachedFileLength = await trackCacheFile.length();

      return cachedFileStreamResponse(
        file: trackCacheFile,
        fileLength: cachedFileLength,
        contentType: "audio/${track.qualityPreset!.name}",
        requestPath: request.requestedUri.toString(),
        rangeHeader: request.headers["range"],
      );
    }

    final primaryUrl = await resolveServingUrl(track);

    final baseHeaders = <String, dynamic>{
      ...headers,
      "user-agent": _randomUserAgent,
      "Cache-Control": "max-age=3600",
      "Connection": "keep-alive",
    };
    final options = Options(
      headers: baseHeaders,
      responseType: ResponseType.stream,
      validateStatus: (status) => status! < 400,
    );
    Options optionsFor(String url) => Options(
          headers: headersWithHost(url, baseHeaders),
          responseType: options.responseType,
          validateStatus: options.validateStatus,
        );

    // HEAD preflight on the primary URL, including a one-time URL refresh
    // on failure (preserves the original behavior). A detected m3u8 stream
    // is redirected directly since it handles range requests internally.
    //
    // mpv HEADs a URL before it GETs it, so [streamTrackInformation] has
    // usually already paid for this exact answer on the same URL — reuse it
    // instead of spending a second upstream round trip before every stream.
    var url = primaryUrl;
    var probedContentType = _reuseHeadProbe(track, url);
    if (probedContentType == null) {
      try {
        final probed = await dio.head(
          url,
          options: optionsFor(url).copyWith(responseType: ResponseType.bytes),
        );
        probedContentType = probed.headers.value("content-type");
      } catch (e, stack) {
        AppLogger.reportError(e, stack);

        final sourcedTrack = await ref
            .read(sourcedTrackProvider(track.query).notifier)
            .refreshStreamingUrl();

        url = sourcedTrack.url!;

        probedContentType = (await dio.head(
          url,
          options: optionsFor(url),
        ))
            .headers
            .value("content-type");
      }
      _rememberHeadProbe(track, url, probedContentType);
    }

    if (probedContentType == "application/vnd.apple.mpegurl") {
      return dio_lib.Response<Uint8List>(
        statusCode: 301,
        statusMessage: "M3U8 Redirect",
        headers: Headers.fromMap({
          "location": [url],
          "content-type": ["application/vnd.apple.mpegurl"],
        }),
        requestOptions: RequestOptions(path: request.requestedUri.toString()),
        isRedirect: true,
      );
    }

    // The actual stream GET is the real failure point. Try the primary URL
    // first; only if it fails, lazily resolve the source cascade (siblings,
    // other engines/plugins) so the expensive plugin construction never runs
    // on the normal success path.
    dio_lib.Response<ResponseBody>? res;
    Object? lastError;
    StackTrace? lastStack;

    try {
      res = await dio.get<ResponseBody>(url, options: optionsFor(url));
    } catch (e, stack) {
      lastError = e;
      lastStack = stack;
      AppLogger.reportError(e, stack);
    }

    if (res == null) {
      for (final fallbackUrl in await fallbackUrlsFor(track)) {
        if (fallbackUrl == url) continue;
        try {
          res = await dio.get<ResponseBody>(
            fallbackUrl,
            options: optionsFor(fallbackUrl),
          );
          url = fallbackUrl;
          break;
        } catch (e, stack) {
          lastError = e;
          lastStack = stack;
          AppLogger.reportError(e, stack);
        }
      }
    }

    if (res == null) {
      if (lastError case final Object error) {
        Error.throwWithStackTrace(error, lastStack ?? StackTrace.current);
      }
      throw Exception("All stream sources failed for ${track.query.name}");
    }

    AppLogger.log.i(
      "Response for track: ${track.query.name}\n"
      "Status Code: ${res.statusCode}\n"
      "Headers: ${res.headers.map}",
    );

    if (!userPreferences.cacheMusic) {
      return res;
    }

    // Only responses that cover the whole file in one sequential write are
    // safe to mirror into the cache; partial/seek ranges stream through
    // untouched (see [PlaybackCacheMirror.completeCoverLength]).
    final expectedTotal = PlaybackCacheMirror.completeCoverLength(
      statusCode: res.statusCode,
      contentRangeHeader: res.headers.value("content-range"),
      contentLengthHeader: res.headers.value("content-length"),
    );

    PlaybackCacheMirror? mirror;
    if (expectedTotal != null) {
      mirror = PlaybackCacheMirror.tryBegin(
        cacheFile: trackCacheFile,
        expectedTotal: expectedTotal,
        onComplete: (fileLength) => _finalizeCachedTrack(track, fileLength),
      );
    }

    if (mirror != null) {
      res.data?.stream = await mirror.attach(res.data!.stream);
    } else {
      res.data?.stream = res.data!.stream.asBroadcastStream();
    }
    return res;
  }

  /// Runs after a complete cache file has been written and renamed:
  /// stamps artwork/metadata the same way the old onDone path did.
  Future<void> _finalizeCachedTrack(SourcedTrack track, int fileLength) async {
    if (track.qualityPreset!.getFileExtension() == "weba") return;

    final imageBytes = await ServiceUtils.downloadImage(
      track.query.album.images.asUrlString(
        placeholder: ImagePlaceholder.albumArt,
        index: 1,
      ),
    );

    final cachePath = await _getTrackCacheFilePath(track);
    await MetadataGod.writeMetadata(
      file: cachePath,
      metadata: track.query.toMetadata(
        imageBytes: imageBytes,
        fileLength: fileLength,
      ),
    ).catchError((e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
    });
  }

  Future<Response> headStreamTrackId(Request request, String trackId) async {
    try {
      final track =
          playlist.tracks.firstWhereOrNull((element) => element.id == trackId);
      if (track == null) {
        return Response.notFound("Track not found in the current queue");
      }

      if (track case SpotubeFullTrackObject()) {
        final downloaded =
            await findDownloadedFile(userPreferences.downloadLocation, track);
        if (downloaded != null) {
          final fileLength = await downloaded.length();
          final res = cachedFileHeadResponse(
            fileLength: fileLength,
            contentType: lookupMimeType(downloaded.path) ??
                "audio/${basename(downloaded.path).split('.').last}",
            requestPath: request.requestedUri.toString(),
          );
          return Response(res.statusCode!, headers: res.headers.map);
        }
      }

      final sourcedTrack = await _getSourcedTrack(trackId);

      if (sourcedTrack == null) {
        return Response.notFound("Track not found in the current queue");
      }

      final res = await streamTrackInformation(
        request,
        sourcedTrack,
      );

      return Response(
        res.statusCode!,
        headers: res.headers.map,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return Response.internalServerError();
    }
  }

  Future<Response> getStreamTrackId(Request request, String trackId) async {
    try {
      final track =
          playlist.tracks.firstWhereOrNull((element) => element.id == trackId);
      if (track == null) {
        return Response.notFound("Track not found in the current queue");
      }

      if (track case SpotubeFullTrackObject()) {
        final downloaded =
            await findDownloadedFile(userPreferences.downloadLocation, track);
        if (downloaded != null) {
          final fileLength = await downloaded.length();
          final res = cachedFileStreamResponse(
            file: downloaded,
            fileLength: fileLength,
            contentType: lookupMimeType(downloaded.path) ??
                "audio/${basename(downloaded.path).split('.').last}",
            requestPath: request.requestedUri.toString(),
            rangeHeader: request.headers["range"],
          );
          return Response(
            res.statusCode!,
            body: res.data as Stream<List<int>>,
            headers: res.headers.map,
          );
        }
      }

      final sourcedTrack = await _getSourcedTrack(trackId);

      if (sourcedTrack == null) {
        return Response.notFound("Track not found in the current queue");
      }

      final res = await streamTrack(
        request,
        sourcedTrack,
        request.headers,
      );

      if (res.data is ResponseBody) {
        return Response(
          res.statusCode!,
          body: (res.data as ResponseBody).stream,
          headers: res.headers.map,
        );
      }

      // Cached-file path: a lazily-read byte stream (see
      // [cachedFileStreamResponse]). Forwarded as-is so shelf serves it
      // chunked — it must never be collected back into memory here.
      if (res.data is Stream<List<int>>) {
        return Response(
          res.statusCode!,
          body: res.data as Stream<List<int>>,
          headers: res.headers.map,
        );
      }

      return Response(
        res.statusCode!,
        body: res.data,
        headers: res.headers.map,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return Response.internalServerError();
    }
  }

  Future<Response> togglePlayback(Request request) async {
    audioPlayer.isPlaying
        ? await audioPlayer.pause()
        : await audioPlayer.resume();

    return Response.ok("Playback toggled");
  }

  Future<Response> previousTrack(Request request) async {
    await audioPlayer.skipToPrevious();
    return Response.ok("Previous track");
  }

  Future<Response> nextTrack(Request request) async {
    await audioPlayer.skipToNext();
    return Response.ok("Next track");
  }
}

final serverPlaybackRoutesProvider =
    Provider((ref) => ServerPlaybackRoutes(ref));

/// One upstream HEAD answer, kept only long enough for the request that follows
/// it. See [ServerPlaybackRoutes._headProbes].
class _HeadProbe {
  const _HeadProbe(this.contentType, this.probedAt);

  final String contentType;
  final DateTime probedAt;
}

/// One cascade walk, kept only long enough for the request that follows it.
/// See [ServerPlaybackRoutes._fallbackUrlLists].
class _FallbackUrls {
  const _FallbackUrls(this.urls, this.computedAt);

  final List<String> urls;
  final DateTime computedAt;
}

/// Debug-only tally of upstream media requests (`playback.upstream.head` /
/// `.get`), so the proxy-path work is measured rather than inferred from the
/// source. Registered only when [kPerfCountersEnabled].
class _UpstreamRequestCounter extends Interceptor {
  const _UpstreamRequestCounter();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    PerfCounters.note('playback.upstream.${options.method.toLowerCase()}');
    handler.next(options);
  }
}
