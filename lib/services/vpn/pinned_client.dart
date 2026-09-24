import 'dart:async';
import 'dart:io';

import 'package:spotube/collections/http-override.dart';
import 'package:spotube/services/logger/logger.dart';

import 'vpn_manager.dart';

/// Creates an [HttpClient] whose sockets are source-pinned to the VPN tunnel
/// address returned by [readPin], or behave exactly like a default client
/// when [readPin] returns null (no lease held).
///
/// Mechanism (every step verified against the SDK + Dio 5.9.0 sources):
/// - Dio's `IOHttpClientAdapter(createHttpClient:)` calls the callback once
///   and caches the client, so the factory closure below reads the pin
///   **live per connection** — a reconnect IP change heals on the next
///   attempt without rebuilding anything.
/// - `HttpClient.connectionFactory` replaces socket creation. Plain legs
///   use `Socket.connect(host, port, sourceAddress: pin)`; TLS legs open
///   the same pinned TCP socket then upgrade via `SecureSocket.secure`,
///   returning both through the documented `ConnectionTask.fromSocket` seam.
/// - Unpinned legs call the same SDK entry points a default client would
///   (`SecureSocket.startConnect` / `Socket.startConnect`, default context,
///   no key-log callback — nothing in the app sets one, verified by grep).
/// - Certificate rule: the SDK adapts the client's 3-arg callback to the
///   1-arg TLS callback by capturing host/port per request; the factory
///   below mirrors that adaptation around the shared
///   [allowsBadCertificateForHost] rule, so pinned, unpinned and pre-VPN
///   behavior agree exactly.
///
/// Fail-closed rules:
/// - Unresolvable pin is impossible here ([readPin] returning null simply
///   delegates); resolution failures surface at lease time as
///   [VpnNoRouteException] instead.
/// - A configured HTTP proxy cannot be seen through with this seam, so a
///   proxied request under an active pin throws [VpnProxyConflictException]
///   rather than transmitting unpinned. (No proxy handling exists anywhere
///   in the app today, verified by grep, so this branch is currently
///   unreachable — it exists so a future proxy cannot silently bypass the
///   pin.)
///
/// Out of scope by construction: DNS resolution still uses the system
/// resolver (documented in `docs/automatic-vpn.md`).
/// [certificateRule] overrides the bad-certificate predicate (tests only —
/// production always uses [allowsBadCertificateForHost], matching the
/// global overrides; Dio-level `validateCertificate` is unused in the app
/// and therefore not threaded through this factory).
HttpClient createPinnedClient(
  InternetAddress? Function() readPin, {
  bool Function(X509Certificate, String, int)? certificateRule,
}) {
  final allowBadCertificate = certificateRule ?? allowsBadCertificateForHost;
  final client = HttpClient();
  client.connectionFactory =
      (Uri uri, String? proxyHost, int? proxyPort) {
    final pin = readPin();
    if (proxyHost != null) {
      // Reachable only if proxy support is added later; see above.
      AppLogger.log.w(
        'Vpn pin: refusing proxied request to ${uri.host} '
        '(pin ${pin?.address ?? "none"})',
      );
      throw const VpnProxyConflictException();
    }
    if (pin == null) {
      return _defaultConnection(uri, allowBadCertificate);
    }
    return _pinnedConnection(uri, pin, allowBadCertificate);
  };
  return client;
}

/// Socket establishment identical to a default client. Used when no pin is
/// held so the client behaves exactly like a plain `HttpClient`.
Future<ConnectionTask<Socket>> _defaultConnection(
  Uri uri,
  bool Function(X509Certificate, String, int) allowBadCertificate,
) {
  final host = uri.host;
  final port = uri.hasPort ? uri.port : _defaultPort(uri.scheme);
  if (uri.scheme == 'https') {
    return SecureSocket.startConnect(
      host,
      port,
      onBadCertificate: _certRuleFor(host, port, allowBadCertificate),
    );
  }
  return Socket.startConnect(host, port);
}

/// Pinned socket establishment: bind the local end to [pin], then upgrade
/// to TLS for `https` with SNI set to the target host and the same
/// certificate rule a default client would apply.
///
/// Cancellation note: Dio aborts the request on cancel; the handed-back
/// task additionally destroys an already-connected socket. A cancel landing
/// inside the millisecond TCP-handshake window cannot abort the handshake
/// itself (no handle exists yet) — the socket is then tracked by the
/// client's pool and closed with it, never leaked.
Future<ConnectionTask<Socket>> _pinnedConnection(
  Uri uri,
  InternetAddress pin,
  bool Function(X509Certificate, String, int) allowBadCertificate,
) {
  final host = uri.host;
  final port = uri.hasPort ? uri.port : _defaultPort(uri.scheme);
  Socket? connected;
  void cancelAttempt() => connected?.destroy();

  Future<Socket> connect() {
    if (uri.scheme == 'https') {
      return Socket.connect(
        host,
        port,
        sourceAddress: pin,
      ).then<Socket>((socket) {
        connected = socket;
        return SecureSocket.secure(
          socket,
          host: host,
          onBadCertificate: _certRuleFor(host, port, allowBadCertificate),
        );
      });
    }
    return Socket.connect(
      host,
      port,
      sourceAddress: pin,
    ).then<Socket>((socket) {
      connected = socket;
      return socket;
    });
  }

  return Future.value(ConnectionTask.fromSocket(connect(), cancelAttempt));
}

/// Mirrors the SDK's adaptation of the client callback (`_http_impl.dart`):
/// capture host/port per request around the applicable allowlist rule.
bool Function(X509Certificate) _certRuleFor(
  String host,
  int port,
  bool Function(X509Certificate, String, int) allowBadCertificate,
) {
  return (X509Certificate certificate) =>
      allowBadCertificate(certificate, host, port);
}

int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
