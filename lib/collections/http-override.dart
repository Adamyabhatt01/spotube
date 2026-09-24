import 'dart:io';

const allowList = [
  "spotify.com",
];

/// Whether a bad certificate is tolerated for [host].
///
/// Shared rule: the global [HttpOverrides] install it on every client, and
/// the VPN-pinned client factory applies the identical rule on its manual
/// TLS leg (the factory cannot read the callback back off the client — the
/// SDK only exposes a setter). Keep both call sites on this one function.
bool allowsBadCertificateForHost(
  X509Certificate cert,
  String host,
  int port,
) {
  return allowList.any((allowedHost) {
    return host.endsWith(allowedHost);
  });
}

class BadCertificateAllowlistOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = allowsBadCertificateForHost;
  }
}
