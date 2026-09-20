import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

extension ChunkDownloaderDioExtension on Dio {
  Future<Response> chunkDownload(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    int connections = 4,
  }) async {
    final targetFile = File(savePath.toString());
    final tempRootDir = await getTemporaryDirectory();
    final tempSaveDir = Directory(
      join(
        tempRootDir.path,
        'Spotube',
        '.chunk_dl_${targetFile.uri.pathSegments.last}',
      ),
    );
    if (await tempSaveDir.exists()) await tempSaveDir.delete(recursive: true);
    await tempSaveDir.create(recursive: true);

    // Set right before the target is opened for writing. Until then, the file
    // at [savePath] — if any — is whatever a previous run left there, and a
    // failed attempt (a cancellation during discovery, most of the time) must
    // not throw that away.
    var targetWritten = false;

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
          return download(
            urlPath,
            savePath,
            onReceiveProgress: onReceiveProgress,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            deleteOnError: deleteOnError,
            options: options,
            data: data,
          );
        }

        totalLength = len;
        supportsRange =
            resp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() ==
                'bytes';

        if (!supportsRange || connections <= 1) {
          // This discovery request's body was never consumed; close it
          // before starting the real download or its socket leaks.
          await _closeStreamResponse(resp);
          return download(
            urlPath,
            savePath,
            onReceiveProgress: onReceiveProgress,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            deleteOnError: deleteOnError,
            options: options,
            data: data,
          );
        }
        await _closeStreamResponse(resp);
      }

      if (!supportsRange || connections <= 1) {
        return download(
          urlPath,
          savePath,
          onReceiveProgress: onReceiveProgress,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          deleteOnError: deleteOnError,
          options: options,
          data: data,
        );
      }

      // Non-null here: both fallback paths above returned otherwise.
      final fileLength = totalLength;

      final chunkSize = (fileLength / connections).ceil();
      int downloaded = 0;

      final partFiles = List.generate(
        connections,
        (i) => File(join(tempSaveDir.path, 'part_$i')),
      );

      // Set when any connection proves the server does not honor Range
      // (or single-connection mode is impossible): remaining chunk writes
      // stop and the whole transfer falls back to a plain download.
      var rangeRejected = false;

      final futures = List.generate(connections, (i) async {
        final start = i * chunkSize;
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

          final file = partFiles[i];
          if (await file.exists()) await file.delete();
          await file.create(recursive: true);
          final sink = file.openWrite();

          var written = 0;
          try {
            await for (final chunk in resp.data!.stream) {
              if (rangeRejected) break;

              final remaining = expectedLength - written;
              if (remaining <= 0) {
                // Server streamed past the requested span: the part
                // cannot be trusted as a clean byte range.
                rangeRejected = true;
                break;
              }

              final boundedChunk =
                  chunk.length > remaining ? chunk.sublist(0, remaining) : chunk;
              sink.add(boundedChunk);
              written += boundedChunk.length;
              downloaded += boundedChunk.length;
              onReceiveProgress?.call(downloaded, fileLength);
            }
          } finally {
            await sink.close();
          }

          if (written != expectedLength) {
            rangeRejected = true;
          }
        } finally {
          await _closeStreamResponse(resp);
        }
      });

      await Future.wait(futures);

      if (rangeRejected) {
        // Forget the parts and re-download as a single stream. The
        // caller's retry/cancel/progress semantics live in download().
        await tempSaveDir.delete(recursive: true);
        return download(
          urlPath,
          savePath,
          onReceiveProgress: onReceiveProgress,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          deleteOnError: deleteOnError,
          options: options,
          data: data,
        );
      }

      targetWritten = true;
      final targetSink = targetFile.openWrite();
      for (final f in partFiles) {
        // A slice skipped above (start beyond EOF) has no part file.
        if (!await f.exists()) continue;
        await targetSink.addStream(f.openRead());
      }
      await targetSink.close();

      await tempSaveDir.delete(recursive: true);

      return Response(
        requestOptions: RequestOptions(path: urlPath),
        data: targetFile,
        statusCode: 200,
        statusMessage: 'Chunked download completed ($connections connections)',
      );
    } catch (e) {
      try {
        // Only a target this call actually opened for writing is ours to
        // clean up. Falling back to download() returns before assembly, so
        // those paths keep dio's deleteOnError semantics for the target.
        if (targetWritten && await targetFile.exists()) {
          await targetFile.delete();
        }
        if (await tempSaveDir.exists()) {
          await tempSaveDir.delete(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
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
