import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spotube/services/control/control_protocol.dart';
import 'package:spotube/services/logger/logger.dart';

/// The running instance's control endpoint.
///
/// A second `spotube` launch connects here instead of starting a second
/// instance, which is what makes `spotube --play <query>` (and the MCP
/// server) able to drive the app the user already has open.
///
/// The endpoint is **local only**: a Unix domain socket on desktop, or a
/// loopback TCP port where that is unavailable. It is a separate socket
/// from the playback/connect server, so turning Connect on (which exposes
/// the app to the LAN) does not expose this.
class ControlServer {
  /// The commands this server answers.
  final ControlCommandHandler handler;

  /// The port the TCP fallback bound, when one was needed.
  int? get port => _tcpServer?.port;

  /// The path the socket was created at, for diagnostics.
  String? get endpointPath => _endpointPath;

  ServerSocket? _unixServer;
  HttpServer? _tcpServer;
  String? _endpointPath;
  final List<Socket> _clients = [];

  ControlServer(this.handler);

  /// Starts listening.
  ///
  /// Returns the endpoint description. A Unix socket is preferred; if the
  /// platform has none, or the socket cannot be created, a loopback TCP
  /// port is used instead and its number is written to a file so a second
  /// launch can find it.
  Future<String> start() async {
    final directory = Directory(ControlChannel.socketDirectory);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    if (ControlChannel.supportsUnixSocket) {
      final path = ControlChannel.effectiveSocketPath;

      // Is a live instance already holding this socket? Connecting is the
      // only reliable test: the socket *file* persists after the process
      // that created it dies, so its presence proves nothing.
      //
      // This matters because a second launch reaches this point too (the
      // runner is NON_UNIQUE so a second launch reaches the Dart entrypoint
      // with its arguments). Deleting the file unconditionally would pull
      // the socket out from under the live instance, and the bind below
      // would then fail with "address already in use" — leaving the live
      // instance's channel broken.
      if (await _isSocketLive(path)) {
        AppLogger.log.t(() => 'Control channel already live at $path');
        return path;
      }

      // No live instance: the file is stale (a crashed run) and must go
      // before the bind, or the bind fails with EADDRINUSE.
      final stale = File(path);
      if (await stale.exists()) {
        try {
          await stale.delete();
        } catch (_) {
          // Someone else owns it after all: the bind below will fail and
          // the TCP fallback takes over.
        }
      }
      try {
        _unixServer = await ServerSocket.bind(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        _endpointPath = path;
        _unixServer!.listen(_handleSocket);
        AppLogger.log.t(() => 'Control channel on $path');
        return path;
      } catch (e, stack) {
        AppLogger.reportError(e, stack, 'Control: unix socket unavailable');
      }
    }

    // Loopback TCP fallback (Windows, or a Unix socket that could not be
    // created). Loopback only: never a routable address.
    _tcpServer = await HttpServer.bind(ControlChannel.loopback, 0);
    final boundPort = _tcpServer!.port;
    _endpointPath = 'tcp://127.0.0.1:$boundPort';
    _tcpServer!.listen((request) async {
      // The HTTP fallback carries the same JSON body the socket protocol
      // uses, so both transports speak one vocabulary.
      ControlResponse response;
      try {
        final body = await utf8.decoder.bind(request).join();
        final decoded = jsonDecode(body);
        final controlRequest = decoded is Map
            ? ControlRequest.fromJson(decoded.cast<String, dynamic>())
            : const ControlRequest('');
        response = await _handleRequest(controlRequest);
      } catch (e) {
        response = ControlResponse.error(e.toString());
      }
      request.response
        ..statusCode = response.ok ? 200 : 400
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response.toJson()));
      await request.response.close();
    });
    // The port file is how a second launch finds this instance.
    try {
      await File(ControlChannel.portFilePath).writeAsString('$boundPort');
    } catch (_) {
      // Without the file a second launch falls back to the socket path,
      // which does not exist on this platform: the second launch then
      // starts its own instance, which is the pre-existing behavior.
    }
    AppLogger.log.t(() => 'Control channel on $_endpointPath');
    return _endpointPath!;
  }

  /// Closes the endpoint and every connected client.
  Future<void> stop() async {
    for (final client in List.of(_clients)) {
      try {
        await client.close();
      } catch (_) {
        // Already gone.
      }
    }
    _clients.clear();

    try {
      await _unixServer?.close();
    } catch (_) {
      // Already closed.
    }
    _unixServer = null;

    try {
      await _tcpServer?.close(force: true);
    } catch (_) {
      // Already closed.
    }
    _tcpServer = null;

    if (_endpointPath != null && ControlChannel.supportsUnixSocket) {
      try {
        final file = File(_endpointPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Another instance may own it now.
      }
    }
    try {
      final portFile = File(ControlChannel.portFilePath);
      if (await portFile.exists()) await portFile.delete();
    } catch (_) {
      // Nothing to clean up.
    }
    _endpointPath = null;
  }

  /// Reads line-delimited requests from a socket and answers each one.
  void _handleSocket(Socket socket) {
    _clients.add(socket);
    socket.done.then((_) => _clients.remove(socket)).ignore();

    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
      if (line.trim().isEmpty) return;
      final request = ControlProtocol.decodeRequest(line);
      if (request == null) {
        socket.write(
          ControlProtocol.encodeResponse(
            const ControlResponse.error('malformed request'),
          ),
        );
        return;
      }
      final response = await _handleRequest(request);
      socket.write(ControlProtocol.encodeResponse(response));
    }, onError: (Object e, StackTrace stack) {
      AppLogger.reportError(e, stack, 'Control: socket error');
    });
  }

  /// Runs one command and turns its outcome into a response.
  Future<ControlResponse> _handleRequest(ControlRequest request) async {
    try {
      final data = await handler(request);
      return ControlResponse.ok(data);
    } catch (e, stack) {
      AppLogger.reportError(e, stack, 'Control: ${request.command}');
      return ControlResponse.error(e.toString());
    }
  }

  /// Whether a live instance is already serving [path].
  ///
  /// Connecting is the only reliable test: the socket *file* outlives the
  /// process that created it, so its presence says nothing about liveness.
  static Future<bool> _isSocketLive(String path) async {
    if (!await File(path).exists()) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      await socket.close();
      return true;
    } catch (_) {
      // Nothing is listening: the file is stale.
      return false;
    }
  }
}

/// The client side: connects to a running instance and sends a command.
class ControlClient {
  /// The response to a command, or null when no instance was reachable.
  static Future<ControlResponse?> send(
    ControlRequest request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await sendRaw(
      ControlProtocol.encodeRequest(request),
      timeout: timeout,
    );
    if (response == null) return null;
    return ControlProtocol.decodeResponse(response.trim());
  }

  /// Sends raw text and returns the raw reply.
  ///
  /// Exposed so a caller (or a test) can use the channel without the
  /// command vocabulary.
  static Future<String?> sendRaw(String payload,
      {Duration timeout = const Duration(seconds: 5)}) async {
    // Unix socket first: it is what the desktop instance binds.
    if (ControlChannel.supportsUnixSocket) {
      final path = ControlChannel.effectiveSocketPath;
      final file = File(path);
      if (await file.exists()) {
        try {
          final socket = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          );
          return await _exchange(socket, payload, timeout);
        } catch (_) {
          // No live instance on the socket: fall through to the port file.
        }
      }
    }

    // Loopback TCP fallback.
    final portFile = File(ControlChannel.portFilePath);
    if (await portFile.exists()) {
      try {
        final port = int.tryParse((await portFile.readAsString()).trim());
        if (port != null && port > 0) {
          final socket = await Socket.connect(ControlChannel.loopback, port);
          return await _exchange(socket, payload, timeout);
        }
      } catch (_) {
        // No live instance: the caller falls back to starting its own.
      }
    }

    return null;
  }

  /// Writes one line and reads the reply line.
  static Future<String?> _exchange(
    Socket socket,
    String payload,
    Duration timeout,
  ) async {
    try {
      socket.write(payload);
      await socket.flush();
      final completer = Completer<String?>();
      final subscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!completer.isCompleted) completer.complete(line);
      }, onError: (Object e) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });
      final reply = await completer.future.timeout(timeout, onTimeout: () {
        subscription.cancel();
        return null;
      });
      await subscription.cancel();
      return reply;
    } finally {
      try {
        await socket.close();
      } catch (_) {
        // Already closed.
      }
    }
  }
}
