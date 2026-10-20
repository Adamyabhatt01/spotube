import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';

extension ChunkDownloaderDioExtension on Dio {
  /// Monotonic suffix making every transfer's staging file unique. Combined
  /// with the pid it is unique across processes too, so two concurrent
  /// transfers — two workers resolving to the same `_savePath`, a retry racing
  /// the cancelled generation's teardown, or a second Spotube instance — can
  /// never share one staging inode and interleave writes at the same slice
  /// offsets. Previously they did, and both integrity gates
  /// (`written == expectedLength` and `stagedLength == fileLength`) still
  /// passed, so a scrambled file was renamed into place and reported complete.
  static int _stagingSequence = 0;

  /// Downloads [urlPath] to [savePath], over `connections` range requests
  /// when the server honors them.
  ///
  /// Bytes are written straight into a staging file next to the target, at
  /// each connection's slice offset — no per-part temp files and no
  /// concatenate pass, so a download costs its own size in disk traffic and
  /// free space rather than twice it. The staging file is unique per
  /// transfer, so concurrent transfers cannot corrupt each other, and the
  /// target only ever sees an atomic same-directory rename: a failed or
  /// canceled attempt can neither disturb a file that is already there nor
  /// be disturbed by one. Legacy `.chunk_dl_*` scratch directories from the
  /// previous part-file flow are swept at startup.
  Future<Response> chunkDownload(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    int? connections,
  }) async {
    final targetFile = File(savePath.toString());
    // Bytes land here first, at their final offsets, and the target only ever
    // sees an atomic same-directory rename. Legacy `.chunk_dl_*` scratch
    // directories from the previous part-file flow are swept at startup.
    //
    // The pid + sequence suffix is what keeps two transfers off one inode;
    // it still ends in `.part` so the startup sweep (which is age-bounded, so
    // a live transfer in another instance survives) can reclaim the orphans a
    // hard kill leaves behind.
    final stagingFile =
        File('${targetFile.path}.$pid.${_stagingSequence++}.part');

    /// Single-stream fallback. Writes to the staging file and renames, exactly
    /// like the chunked path, so dio's `deleteOnError` — which unlinks
    /// `savePath` outright on a mid-body error *and* on cancellation — can
    /// only ever destroy bytes this transfer wrote. Passing the target
    /// directly is what used to make a failed re-download delete a complete
    /// file the user already had.
    Future<Response> fallback() => _downloadToStagingThenRename(
          this,
          urlPath: urlPath,
          stagingFile: stagingFile,
          targetFile: targetFile,
          onReceiveProgress: onReceiveProgress,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          deleteOnError: deleteOnError,
          lengthHeader: lengthHeader,
          data: data,
          options: options,
        );

    try {
      int? totalLength;
      bool supportsRange = false;

      Response? headResp;
      try {
        headResp = await head(
          urlPath,
          queryParameters: queryParameters,
          options: Options(
            headers: {'Range': 'bytes=0-0'},
            followRedirects: true,
          ),
          // The probe is the first request this function makes, so without
          // the token a cancel landing here went unobserved until the probe
          // gave up — up to connectTimeout + receiveTimeout, and with three
          // workers that is long enough for three cancels to wedge the whole
          // download pool. The catch below already swallows every failure.
          cancelToken: cancelToken,
        );
      } catch (_) {
        // Some servers reject HEAD -> ignore
      }

      final lengthStr = headResp?.headers[lengthHeader]?.first;
      if (lengthStr != null) {
        final parsed = int.tryParse(lengthStr);
        if (parsed != null && parsed > 1) {
          totalLength = parsed;
        }
      }

      supportsRange = headResp?.statusCode == 206 ||
          headResp?.headers.value(HttpHeaders.acceptRangesHeader) == 'bytes';

      if (totalLength == null || totalLength <= 1) {
        final resp = await get<ResponseBody>(
          urlPath,
          options: Options(
            responseType: ResponseType.stream,
          ),
          queryParameters: queryParameters,
          cancelToken: cancelToken,
        );

        final len = int.tryParse(resp.headers[lengthHeader]?.first ?? '');
        if (len == null || len <= 1) {
          // can’t safely chunk — fallback
          await _closeStreamResponse(resp);
          return fallback();
        }

        totalLength = len;
        supportsRange =
            resp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() ==
                'bytes';

        if (!supportsRange || _connectionsForSize(len, connections) <= 1) {
          // This discovery request's body was never consumed; close it
          // before starting the real download or its socket leaks.
          await _closeStreamResponse(resp);
          return fallback();
        }
        await _closeStreamResponse(resp);
      }

      final fileConnections = _connectionsForSize(totalLength, connections);
      if (!supportsRange || fileConnections <= 1) {
        return fallback();
      }

      // Non-null here: both fallback paths above returned otherwise.
      final fileLength = totalLength;

      // One read-write handle per connection, each pinned to its slice
      // offset. Concurrent `writeFrom` on one shared handle would clobber the
      // shared position, so every connection owns its file — and its flush,
      // since a buffered sink cannot interleave positional writes either.
      final chunkSize = (fileLength / fileConnections).ceil();
      int downloaded = 0;

      try {
        await stagingFile.create(recursive: true);
      } catch (_) {
        // No space to even pre-size the staging file: let the single-stream
        // path deal with the staging file the same way a plain download does.
        return fallback();
      }

      // Set when any connection proves the server does not honor Range
      // (or wrote anything other than its exact slice): the staging file is
      // poisoned and the whole transfer falls back to a plain download.
      var rangeRejected = false;

      final futures = List.generate(fileConnections, (i) async {
        final start = i * chunkSize;
        // A slice skipped below (start beyond EOF) leaves no gap to write.
        if (start >= fileLength) return;
        final end = min((i + 1) * chunkSize - 1, fileLength - 1);
        // Bytes this connection is expected to write; a server that
        // sends anything else (e.g. ignores Range and streams the full
        // body) must poison the whole chunked transfer.
        final expectedLength = end - start + 1;

        final resp = await get<ResponseBody>(
          urlPath,
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Range': 'bytes=$start-$end'},
          ),
          queryParameters: queryParameters,
          cancelToken: cancelToken,
        );

        try {
          if (rangeRejected) {
            await _closeStreamResponse(resp);
            return;
          }
          if (resp.statusCode != 206) {
            rangeRejected = true;
            await _closeStreamResponse(resp);
            return;
          }

          final file =
              await stagingFile.open(mode: FileMode.append);
          try {
            await file.setPosition(start);

            var written = 0;
            await for (final chunk in resp.data!.stream) {
              if (rangeRejected) break;

              final remaining = expectedLength - written;
              if (remaining <= 0) {
                // Server streamed past the requested span: the slice
                // cannot be trusted as a clean byte range.
                rangeRejected = true;
                break;
              }

              final boundedChunk =
                  chunk.length > remaining ? chunk.sublist(0, remaining) : chunk;
              await file.writeFrom(
                boundedChunk,
                0,
                boundedChunk.length,
              );
              written += boundedChunk.length;
              downloaded += boundedChunk.length;
              onReceiveProgress?.call(downloaded, fileLength);
            }

            if (written != expectedLength) {
              rangeRejected = true;
            }
          } finally {
            // `close()` must run even if the flush throws (EIO, some network
            // filesystems), or the fd for this connection leaks for the rest
            // of the process — four of them per transfer. The length check
            // below is the real integrity gate, so a flush error is not worth
            // losing the handle over.
            try {
              await file.flush();
            } finally {
              await file.close();
            }
          }
        } finally {
          await _closeStreamResponse(resp);
        }
      });

      await Future.wait(futures);

      if (rangeRejected) {
        // Forget the partial staging file and re-download as a single
        // stream. The caller's retry/cancel/progress semantics live in
        // download().
        await _deleteQuietly(stagingFile);
        return fallback();
      }

      // Positional writes can leave the last slice short when the file size
      // was misreported, and an all-skipped tail slice never wrote at all.
      final stagedLength = await stagingFile.length();
      if (stagedLength != fileLength) {
        await _deleteQuietly(stagingFile);
        return fallback();
      }

      // The only moment the target path changes: an atomic same-directory
      // rename. Before it, a pre-existing target is untouched by anything
      // this call did; after a failure below it still is.
      await stagingFile.rename(targetFile.path);

      return Response(
        requestOptions: RequestOptions(path: urlPath),
        data: targetFile,
        statusCode: 200,
        statusMessage:
            'Chunked download completed ($fileConnections connections)',
      );
    } catch (e) {
      try {
        // Only ever this transfer's staging file, and only because nothing
        // below the fallback already renamed it away: no path opens the
        // target for writing, so a failed attempt leaves an existing target
        // byte-identical to how it found it.
        await _deleteQuietly(stagingFile);
      } catch (_) {}
      rethrow;
    }
  }

  /// Connections to spend on a file of [totalLength] bytes: one below ~2 MiB
  /// (a 3-5 MiB track costs more in request overhead than it saves), the
  /// caller's [requested] ceiling above that.
  static int _connectionsForSize(int totalLength, int? requested) {
    final ceiling = (requested ?? 4).clamp(1, 4);
    if (ceiling == 1) return 1;
    return min(ceiling, max(1, totalLength >> 21));
  }

  /// The single-stream path used everywhere chunking is not possible.
  ///
  /// dio's `download()` writes straight to the path it is given — there is no
  /// temp file of its own — and with `deleteOnError` it unlinks that path on
  /// any mid-body error *and* on cancellation. Handing it the real target
  /// therefore meant a failed re-download deleted a complete file the user
  /// already had, and a cancel destroyed it too. Writing to the transfer's
  /// staging file and renaming on success restores the invariant the chunked
  /// path has always had.
  ///
  /// The `catch` is the mirror image: the staging file is the only thing this
  /// call may delete, and it is the only thing it ever created.
  static Future<Response> _downloadToStagingThenRename(
    Dio dio, {
    required String urlPath,
    required File stagingFile,
    required File targetFile,
    required ProgressCallback? onReceiveProgress,
    required Map<String, dynamic>? queryParameters,
    required CancelToken? cancelToken,
    required bool deleteOnError,
    required String lengthHeader,
    required Object? data,
    required Options? options,
  }) async {
    try {
      final response = await dio.download(
        urlPath,
        stagingFile.path,
        onReceiveProgress: onReceiveProgress,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
        options: options,
        data: data,
      );
      // Same atomic rename the chunked path ends with. A competing transfer
      // that finished first loses here rather than being interleaved with.
      await stagingFile.rename(targetFile.path);
      return Response(
        requestOptions: RequestOptions(path: urlPath),
        data: targetFile,
        statusCode: response.statusCode,
        statusMessage: 'Single-stream download completed',
      );
    } catch (_) {
      await _deleteQuietly(stagingFile);
      rethrow;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Drains-and-detaches an unconsumed [ResponseBody] stream so the
  /// underlying socket is freed instead of leaking until GC. Errors are
  /// swallowed: the response is being discarded, not transferred.
  static Future<void> _closeStreamResponse(Response resp) async {
    final body = resp.data;
    if (body is! ResponseBody) return;
    try {
      final subscription = body.stream.listen((_) {});
      await subscription.cancel();
    } catch (_) {}
  }
}
