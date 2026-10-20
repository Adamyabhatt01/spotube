import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spotube/utils/platform.dart';

/// Handles one control request.
///
/// The callback returns the command's result, or throws to report a
/// failure. The channel turns either into a [ControlResponse].
typedef ControlCommandHandler = FutureOr<Object?> Function(
  ControlRequest request,
);

/// A request sent to a running Spotube instance over the control channel.
class ControlRequest {
  /// The command name, e.g. "playback.play" or "state.get".
  final String command;

  /// The command's arguments.
  final Map<String, dynamic> arguments;

  const ControlRequest(this.command, [this.arguments = const {}]);

  factory ControlRequest.fromJson(Map<String, dynamic> json) {
    return ControlRequest(
      json['command'] as String? ?? '',
      (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'command': command,
        'arguments': arguments,
      };
}

/// The answer a running instance sends back.
class ControlResponse {
  /// Whether the command succeeded.
  final bool ok;

  /// The command's result, when it succeeded.
  final Object? data;

  /// The failure message, when it did not.
  final String? error;

  const ControlResponse.ok([this.data])
      : ok = true,
        error = null;

  const ControlResponse.error(this.error)
      : ok = false,
        data = null;

  factory ControlResponse.fromJson(Map<String, dynamic> json) {
    if (json['ok'] == true) return ControlResponse.ok(json['data']);
    return ControlResponse.error(json['error'] as String? ?? 'unknown error');
  }

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
      };
}

/// The wire protocol for the control channel.
///
/// One JSON object per line, in both directions. A line-delimited JSON
/// protocol keeps the channel usable from any language (a shell script with
/// `nc`, a Python script, the MCP server) without a client library.
class ControlProtocol {
  /// The newline that terminates a frame.
  static const String terminator = '\n';

  /// Encodes a request as a single line.
  static String encodeRequest(ControlRequest request) =>
      '${jsonEncode(request.toJson())}$terminator';

  /// Encodes a response as a single line.
  static String encodeResponse(ControlResponse response) =>
      '${jsonEncode(response.toJson())}$terminator';

  /// Decodes one line into a request, or null when the line is not one.
  static ControlRequest? decodeRequest(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      return ControlRequest.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Decodes one line into a response, or null when the line is not one.
  static ControlResponse? decodeResponse(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      return ControlResponse.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

/// Where the running instance's control socket lives, and how to reach it.
///
/// A Unix domain socket on desktop, a named pipe on Windows, and a
/// loopback TCP port on mobile (where neither is available). The path is
/// written to a small file so a second launch can find the first.
///
/// The channel is **local only**: it is never bound to a routable address,
/// so it cannot be reached from the network. It is a different socket from
/// the playback/connect server, so enabling Connect (which exposes the app
/// to the LAN) does not expose this.
class ControlChannel {
  /// The directory the socket and the port file live in.
  static String get socketDirectory {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home/.local/state/spotube';
  }

  /// The Unix socket path (desktop).
  static String get socketPath => '$socketDirectory/control.sock';

  /// The file the bound port is written to (used when a socket is not
  /// available).
  static String get portFilePath => '$socketDirectory/control.port';

  /// The name of the environment variable that overrides the socket path.
  ///
  /// Set by anyone running two isolated instances.
  static const String socketPathOverrideEnv = 'SPOTUBE_CONTROL_SOCKET';

  /// An explicit socket path, set by the test suite.
  ///
  /// The environment variable is the production override, but
  /// `Platform.environment` is unmodifiable in a Flutter test, so the
  /// test seam is a field.
  static String? socketPathOverride;

  /// The effective socket path, honoring the override.
  static String get effectiveSocketPath {
    final override = socketPathOverride;
    if (override != null && override.isNotEmpty) return override;

    final fromEnv = Platform.environment[socketPathOverrideEnv];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    return socketPath;
  }

  /// Whether this platform can host a Unix domain socket.
  static bool get supportsUnixSocket => !kIsWindows;

  /// The loopback host the TCP fallback binds to.
  static final InternetAddress loopback = InternetAddress.loopbackIPv4;
}
