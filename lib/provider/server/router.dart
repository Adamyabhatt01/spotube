import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spotube/provider/server/routes/connect.dart';
import 'package:spotube/provider/server/routes/playback.dart';

/// Rejects requests that did not arrive over loopback.
///
/// With Connect enabled the server binds `anyIPv4`, but the only consumers of
/// these routes are this device's own mpv (loopback URIs) — remote Connect
/// clients speak WebSocket on `/ws`, which has its own pairing dialog. Without
/// this gate any LAN host could drive playback and pull queued audio.
///
/// A request with no connection info (unit tests driving the handler
/// directly) is allowed: there is no remote address to distrust.
bool _isLoopbackRequest(Request request) {
  final info =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  final remote = info?.remoteAddress;
  return remote == null || remote.isLoopback;
}

/// Same gate as [loopbackOnly], for `/stream/<trackId>` handlers whose
/// signature carries the path parameter.
@visibleForTesting
FutureOr<Response> Function(Request, String) loopbackOnlyStream(
  FutureOr<Response> Function(Request, String) inner,
) {
  return (request, trackId) {
    if (!_isLoopbackRequest(request)) {
      return Response.forbidden('loopback only');
    }
    return inner(request, trackId);
  };
}

@visibleForTesting
Handler loopbackOnly(Handler inner) {
  return (Request request) {
    if (!_isLoopbackRequest(request)) {
      return Response.forbidden('loopback only');
    }
    return inner(request);
  };
}

final serverRouterProvider = Provider((ref) {
  final playbackRoutes = ref.watch(serverPlaybackRoutesProvider);
  final connectRoutes = ref.watch(serverConnectRoutesProvider);

  final router = Router();

  router.get("/ping", (Request request) => Response.ok("pong"));

  router.head("/stream/<trackId>",
      loopbackOnlyStream(playbackRoutes.headStreamTrackId));
  router.get("/stream/<trackId>",
      loopbackOnlyStream(playbackRoutes.getStreamTrackId));

  router.get("/playback/toggle-playback",
      loopbackOnly(playbackRoutes.togglePlayback));
  router.get("/playback/previous", loopbackOnly(playbackRoutes.previousTrack));
  router.get("/playback/next", loopbackOnly(playbackRoutes.nextTrack));

  router.all("/ws", connectRoutes.websocket);

  return router;
});
