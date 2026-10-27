import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:dio/dio.dart' as dio_lib;
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';

import 'package:spotube/provider/server/active_track_sources.dart';
import 'package:spotube/provider/server/playback/playback_files.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/vpn/vpn_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/music_cache_policy.dart';
import 'package:spotube/services/playback_cache_mirror.dart';
import 'package:spotube/services/sourced_track/local_library_lookup.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/services/vpn/vpn_lease.dart';
import 'package:spotube/services/vpn/vpn_pin.dart';
import 'package:spotube/services/vpn/pinned_client.dart';
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

String? get _randomDeviceUserAgent => _deviceClients
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
    // Source-pins sockets to the held VPN lease when one exists; delegates
    // unpinned otherwise (gate off = old behavior).
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createPinnedClient(VpnPinHolder.current),
    );
    if (kPerfCountersEnabled) {
      dio.interceptors.add(const _UpstreamRequestCounter());
    }
  }

  /// How long an upstream HEAD answer may stand in for the next request for the
  /// same URL. mpv probes a stream with HEAD and asks for its body moments
  /// later, but pauses and seeks can stretch that gap: the key is the full
  /// signed URL, which is immutable, so a wider window cannot serve a stale
  /// answer for different content — only skip a repeated probe of the same.
  static const headProbeReuseWindow = Duration(seconds: 30);

  /// The user agent a track is served under, fixed at its first request.
  ///
  /// A signed googlevideo URL belongs to the client context that signed it,
  /// and mpv's HEAD and the GET after it (plus any re-probe after a seek) are
  /// all requests for the same signed answer. Drawing a fresh random client
  /// per request asked one of them to be rejected and paid for with the whole
  /// fallback-cascade rebuild.
  String? _userAgentFor(SourcedTrack track) {
    final key = track.query.id;
    if (_userAgents.containsKey(key)) {
      // Re-touch the entry: Dart maps are insertion-ordered, so remove+re-add
      // moves it to most-recently-used. The playing track is asked for on
      // every HEAD/GET (plus any seek re-probe), so its UA can never be the
      // oldest entry while it is still live — the failure mode the pin exists
      // to prevent.
      final ua = _userAgents.remove(key);
      return _userAgents[key] = ua;
    }
    // Same bound as [_headProbes], but evict the *oldest* entry instead of
    // clearing the lot: clearing would also drop the currently playing
    // track's pinned UA, re-randomizing it mid-playback.
    while (_userAgents.length >= 16) {
      _userAgents.remove(_userAgents.keys.first);
    }
    return _userAgents[key] = _randomDeviceUserAgent;
  }

  final Map<String, String?> _userAgents = {};

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
    // Re-touch: Dart maps are insertion-ordered, so remove+re-add moves the
    // entry to most-recently-used. The playing track is probed on every
    // HEAD/GET (plus seeks), so it can never be the oldest entry while live —
    // the same pin that `_userAgentFor` already implements. Measured: the old
    // `clear()` below wiped the playing entry on the 17th insert.
    _headProbes.remove(key);
    _headProbes[key] = probe;
    PerfCounters.note('playback.headProbeReused');
    return probe.contentType;
  }

  void _rememberHeadProbe(SourcedTrack track, String url, String? contentType) {
    if (contentType == null) return;

    // Evict the oldest entry instead of clearing the lot: clearing also
    // dropped the currently playing track's probe (extra upstream HEAD).
    // Mirrors `_userAgentFor` above; same 16-entry bound.
    while (_headProbes.length >= 16) {
      _headProbes.remove(_headProbes.keys.first);
    }
    _headProbes[_headProbeKey(track, url)] =
        _HeadProbe(contentType, DateTime.now());
  }

  /// Stream-URL refreshes currently running, keyed by track id.
  ///
  /// `resolveServingUrl` (proactive expiry check, called from both the HEAD
  /// and the GET handler) and the GET handler's reactive failure path can
  /// otherwise each run a full `refreshStream` — manifest-wide HEAD sweep
  /// plus re-fetch — for the same track back to back. Sharing the in-flight
  /// refresh collapses that pair into one; entries remove themselves on
  /// completion, so the map holds only live work.
  final Map<String, Future<SourcedTrack>> _refreshInFlight = {};

  /// [SourcedTrackNotifier.refreshStreamingUrl] with the pair above folded
  /// into one flight. Failures propagate to every sharer, and every sharer
  /// keeps its existing fallback (stale URL / cascade), exactly as if each
  /// had run its own refresh and failed it.
  Future<SourcedTrack> _refreshStreamingUrlOnce(
    SpotubeFullTrackObject query,
  ) {
    final running = _refreshInFlight[query.id];
    if (running != null) {
      PerfCounters.note('playback.refreshShared');
      return running;
    }
    final future = ref
        .read(sourcedTrackProvider(query).notifier)
        .refreshStreamingUrl();
    _refreshInFlight[query.id] = future;
    // Both handlers swallow (entry removal is the whole result), so this
    // telemetric future always completes cleanly and can never surface a
    // failed refresh as an unhandled zone error. (A `whenComplete` here
    // would rethrow into an unobserved future.)
    future.then(
      (_) {
        if (identical(_refreshInFlight[query.id], future)) {
          _refreshInFlight.remove(query.id);
        }
      },
      onError: (_) {
        if (identical(_refreshInFlight[query.id], future)) {
          _refreshInFlight.remove(query.id);
        }
      },
    );
    return future;
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

    final urls = await playbackFallbackUrls(ref.sourceDeps, track);
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
    // The extension names the cache file, so it must be stable for a given
    // track: the same container the bytes are served in. Falls back to the
    // track's own container when the plugin has published no presets yet.
    final extension = track.container?.extension ?? "m4a";
    return join(
      await UserPreferencesNotifier.getMusicCacheDir(),
      ServiceUtils.sanitizeFilename(
        "${ServiceUtils.trackFileStem(track.query, spaceAfterComma: false)} (${track.info.id}).$extension",
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
            .then((swapped) {
              final newUrl = swapped.url ?? track.url;
              if (newUrl == null) {
                throw StateError(
                  'No stream URL available for ${track.query.id} '
                  'after sibling swap',
                );
              }
              return newUrl;
            });

    if (isStreamUrlExpired(url)) {
      try {
        // Shared with the GET handler's reactive refresh below: one flight
        // per track, not one per handler.
        final refreshed = await _refreshStreamingUrlOnce(track.query);
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
    final track = playlist.tracks
        .firstWhereOrNull((element) => element.id == trackId);
    if (track == null) return null;
    // Local tracks need no sourcing; the unguarded `as` used to turn them
    // into a 500 here (caught at the route handlers). Return null so the
    // caller serves the local file path instead.
    if (track is! SpotubeFullTrackObject) return null;

    final activeSourcedTrack =
        await ref.read(activeTrackSourcesProvider.future);

    return activeSourcedTrack?.track.id == track.id
        ? activeSourcedTrack?.source
        : await ref.read(
            sourcedTrackProvider(track).future,
          );
  }

  /// Acquires one VPN lease for a playback upstream fetch, or null when the
  /// mode does not gate playback. Throws fail-closed when protection is
  /// required but unavailable — the route handlers translate that into an
  /// HTTP 500 (and never fall back to the normal connection).
  ///
  /// Local-file and cache-file serving happens before this point in both
  /// handlers, so already-on-disk audio never takes a lease.
  Future<VpnLease?> _acquirePlaybackLease() async {
    if (!vpnGatesPlayback(ref)) return null;
    return ref.read(vpnManagerProvider).acquire();
  }

  /// The `Content-Type` for a response that serves [file] from the music
  /// cache.
  ///
  /// Prefers the track's container name — that is what the cached bytes
  /// actually are. Falls back to the cache file's own extension when the
  /// audio-source plugin has published no presets, so the header still
  /// describes the file being served instead of crashing the request.
  String _cachedContentType(SourcedTrack track, File file) {
    final name = track.container?.name;
    if (name != null) return "audio/$name";
    return lookupMimeType(file.path) ?? "audio/mpeg";
  }

  Future<dio_lib.Response> streamTrackInformation(
    Request request,
    SourcedTrack track,
  ) async {
    // Interpolated once per playback request and only useful while
    // debugging — `AppLogger.log` prints at Level.info in release, so the
    // guard has to be at the call site or the header map is built anyway.
    if (kDebugMode) {
      AppLogger.log.i(
        "HEAD request for track: ${track.query.name}\n"
        "Headers: ${request.headers}",
      );
    }

    final trackCacheFile = File(await _getTrackCacheFilePath(track));

    if (await trackCacheFile.exists() && userPreferences.cacheMusic) {
      // Feeds the cache-eviction ranking: mpv HEADs before it GETs and
      // pre-warms the queue head the same way, so this marks both the active
      // track and the next ones as hot.
      MusicCacheUsage.markServed(trackCacheFile.path);
      final fileLength = await trackCacheFile.length();

      return cachedFileHeadResponse(
        fileLength: fileLength,
        contentType: _cachedContentType(track, trackCacheFile),
        requestPath: request.requestedUri.toString(),
      );
    }

    final VpnLease? vpnLease = await _acquirePlaybackLease();
    try {
      String url = await resolveServingUrl(track);

      final options = Options(
        headers: {
          "user-agent": _userAgentFor(track),
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
        // Intentional fall-through to the fallback cascade, but counted so
        // a failing primary is observable in debug/profile counters.
        PerfCounters.note('playback.headProbeFailure');
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
    } finally {
      await vpnLease?.release();
    }
  }

  Future<dio_lib.Response> streamTrack(
    Request request,
    SourcedTrack track,
    Map<String, dynamic> headers,
  ) async {
    if (kDebugMode) {
      AppLogger.log.i(
        "GET request for track: ${track.query.name}\n"
        "Headers: ${request.headers}",
      );
    }

    final trackCacheFile = File(await _getTrackCacheFilePath(track));

    if (await trackCacheFile.exists() && userPreferences.cacheMusic) {
      MusicCacheUsage.markServed(trackCacheFile.path);
      final cachedFileLength = await trackCacheFile.length();

      return cachedFileStreamResponse(
        file: trackCacheFile,
        fileLength: cachedFileLength,
        contentType: _cachedContentType(track, trackCacheFile),
        requestPath: request.requestedUri.toString(),
        rangeHeader: request.headers["range"],
      );
    }

    final VpnLease? vpnLease = await _acquirePlaybackLease();
    try {
      final primaryUrl = await resolveServingUrl(track);

      final baseHeaders = <String, dynamic>{
        ...headers,
        "user-agent": _userAgentFor(track),
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

          // Shared with the proactive refresh in resolveServingUrl above.
          final sourcedTrack = await _refreshStreamingUrlOnce(track.query);
          final freshUrl = sourcedTrack.url;
          if (freshUrl != null) {
            url = freshUrl;
          }

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

      if (kDebugMode) {
        AppLogger.log.i(
          "Response for track: ${track.query.name}\n"
          "Status Code: ${res.statusCode}\n"
          "Headers: ${res.headers.map}",
        );
      }

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
          // The cache path is passed in rather than re-derived: the
          // container it is named after can change between the request and
          // the write completing, and the metadata must land on the file
          // that was actually mirrored.
          onComplete: (fileLength) =>
              _finalizeCachedTrack(track, fileLength, trackCacheFile.path),
        );
      }

      if (mirror != null && res.data != null) {
        final responseBody = res.data!;
        responseBody.stream = await mirror.attach(responseBody.stream);
      }
      // No wrap on the pass-through path: a client disconnect cancels shelf's
      // subscription, which reaches the dio body stream directly and closes
      // the upstream connection. asBroadcastStream() used to sit here and
      // swallow that cancel, leaving the socket paused-but-open forever.
      return res;
    } finally {
      await vpnLease?.release();
    }
  }

  /// Runs after a complete cache file has been written and renamed:
  /// stamps artwork/metadata the same way the old onDone path did.
  ///
  /// [cachePath] is the file that was actually mirrored, passed in by the
  /// caller rather than re-derived, so the metadata lands on that file
  /// even if the container naming has changed in the meantime.
  Future<void> _finalizeCachedTrack(
    SourcedTrack track,
    int fileLength,
    String cachePath,
  ) async {
    // A weba (webm) cache file cannot carry the metadata we are about to
    // write, so skip it. The extension comes from the same container the
    // bytes were served in, so this stays true when the plugin has
    // published no presets.
    if (track.container?.extension == "weba") return;

    // Shared bytes with the download worker and the palette hook: one fetch
    // per URL no matter how many of them want this cover at once.
    final imageBytes = await ServiceUtils.artworkBytes(
      track.query.album.images.asUrlString(
        placeholder: ImagePlaceholder.albumArt,
        index: 1,
      ),
    );

    await MetadataGod.writeMetadata(
      file: cachePath,
      metadata: track.query.toMetadata(
        imageBytes: imageBytes,
        fileLength: fileLength,
      ),
    ).catchError((e, stackTrace) {
      AppLogger.reportError(e, stackTrace);
    });

    // The cache just grew by this track; trim it back under the user's
    // ceiling here rather than on a timer, so the ceiling is also respected by
    // a session that downloads 200 tracks and never plays another byte. The
    // file being finalized is pinned — it has been served zero times, so the
    // recency ranking alone would not protect it.
    await ref
        .read(userPreferencesProvider.notifier)
        .enforceMusicCacheQuota(pinnedPaths: {cachePath});
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

        // The file may also be in the user's local library (the folder
        // Spotube was pointed at), which is not the download folder. It
        // needs no YouTube lookup, no manifest extraction and no upstream
        // stream, so it is served before the remote source is resolved.
        final local = await findLocalLibraryFile(track);
        if (local != null) {
          final fileLength = await local.length();
          final res = cachedFileHeadResponse(
            fileLength: fileLength,
            contentType: lookupMimeType(local.path) ??
                "audio/${basename(local.path).split('.').last}",
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

  /// Finds [track] in the user's local library and returns the file.
  ///
  /// The library is the folder Spotube was pointed at (Settings → Storage →
  /// Local library), which is not the download folder: a file the user
  /// already had is served straight from disk, with no YouTube lookup, no
  /// manifest extraction and no upstream stream.
  ///
  /// Null when the library holds no equivalent of the track, or when the
  /// matched file has since been removed — the index is a scan result and
  /// the disk is the truth.
  Future<File?> findLocalLibraryFile(SpotubeFullTrackObject track) async {
    final library = ref.read(localTracksProvider).valueOrNull;
    if (library == null || library.isEmpty) return null;

    final candidates = [
      for (final tracks in library.values) ...tracks,
    ];
    if (candidates.isEmpty) return null;

    final match = LocalLibraryLookup.find(track, candidates);
    if (match == null) return null;
    if (!LocalLibraryLookup.fileExists(match.track)) return null;

    return File(match.track.path);
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

        // The file may also be in the user's local library (the folder
        // Spotube was pointed at), which is not the download folder. It
        // needs no YouTube lookup, no manifest extraction and no upstream
        // stream, so it is served before the remote source is resolved.
        final local = await findLocalLibraryFile(track);
        if (local != null) {
          final fileLength = await local.length();
          final res = cachedFileStreamResponse(
            file: local,
            fileLength: fileLength,
            contentType: lookupMimeType(local.path) ??
                "audio/${basename(local.path).split('.').last}",
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
