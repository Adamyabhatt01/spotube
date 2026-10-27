import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' hide Response;
import 'package:dio/dio.dart' as dio_lib;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/parser/range_headers.dart';
import 'package:spotube/utils/service_utils.dart';

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

  // An inverted range (`bytes=200-100`) parses without complaint but cannot
  // describe any byte span: the 206 branch below computes
  // `end - start + 1` from it, yielding a *negative* content-length. dart:io
  // rejects that by throwing out of `_HttpHeaders._addContentLength`, and
  // shelf's `_writeResponse` sets the status line before applying headers, so
  // the throw escapes `handleRequest` with the response still open — the
  // client hangs until it gives up and the socket is never released. Reachable
  // from any HTTP client, and the server binds 0.0.0.0 when Connect is on.
  //
  // Treat it as unsatisfiable, which is the same answer an out-of-bounds
  // `start` already gets from the check below: the whole file. Deliberately
  // not a 416, so the status codes clients see stay exactly as before.
  final rangeStart = range?.start;
  final rangeEnd = range?.end;
  final rangeIsUsable =
      rangeStart != null && (rangeEnd == null || rangeEnd >= rangeStart);

  if (rangeIsUsable && rangeStart < fileLength) {
    final start = rangeStart;
    final end = min(rangeEnd ?? fileLength - 1, fileLength - 1);

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
    ServiceUtils.trackFileStem(track, spaceAfterComma: true),
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
