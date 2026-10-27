import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:dio/dio.dart' as dio_lib;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:shelf/shelf.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/server/playback/playback_files.dart';
import 'package:spotube/provider/server/playback/playback_stream_service.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/local_library_lookup.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

/// The shelf-facing playback routes: resolves the queue entry, serves local
/// and downloaded files first, and shapes HTTP responses. All upstream work
/// lives in [PlaybackStreamService].
class ServerPlaybackRoutes {
  final Ref ref;
  UserPreferences get userPreferences => ref.read(userPreferencesProvider);
  AudioPlayerState get playlist => ref.read(audioPlayerProvider);
  AudioPlayerPort get _player => ref.read(audioPlayerPortProvider);
  final PlaybackStreamService service;

  ServerPlaybackRoutes(this.ref) : service = PlaybackStreamService(ref);

  /// Mirrors [PlaybackStreamService.fallbackUrlsReuseWindow]; kept here so
  /// existing callers and tests can tune the memo through the route class.
  static const fallbackUrlsReuseWindow =
      PlaybackStreamService.fallbackUrlsReuseWindow;

  Future<String> resolveServingUrl(SourcedTrack track) =>
      service.resolveServingUrl(track);

  Future<List<String>> fallbackUrlsFor(SourcedTrack track) =>
      service.fallbackUrlsFor(track);

  Future<dio_lib.Response> streamTrackInformation(
    Request request,
    SourcedTrack track,
  ) =>
      service.streamTrackInformation(request, track);

  Future<dio_lib.Response> streamTrack(
    Request request,
    SourcedTrack track,
    Map<String, dynamic> headers,
  ) =>
      service.streamTrack(request, track, headers);

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

      final sourcedTrack = await service.sourcedTrackFor(trackId);

      if (sourcedTrack == null) {
        return Response.notFound("Track not found in the current queue");
      }

      final res = await service.streamTrackInformation(
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

      final sourcedTrack = await service.sourcedTrackFor(trackId);

      if (sourcedTrack == null) {
        return Response.notFound("Track not found in the current queue");
      }

      final res = await service.streamTrack(
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
    _player.isPlaying
        ? await _player.pause()
        : await _player.resume();

    return Response.ok("Playback toggled");
  }

  Future<Response> previousTrack(Request request) async {
    await _player.skipToPrevious();
    return Response.ok("Previous track");
  }

  Future<Response> nextTrack(Request request) async {
    await _player.skipToNext();
    return Response.ok("Next track");
  }
}

final serverPlaybackRoutesProvider =
    Provider((ref) => ServerPlaybackRoutes(ref));
