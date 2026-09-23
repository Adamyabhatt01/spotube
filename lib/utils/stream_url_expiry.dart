/// Helpers for reasoning about proxied audio-stream URL expiry.
///
/// YouTube-style stream URLs carry an `expire` query parameter holding a unix
/// timestamp (seconds) after which the signed URL stops working. The manifest
/// models intentionally do NOT persist this value (Phase 2 guardrail: no
/// model changes), so it is derived from the URL itself at the serving
/// boundary.
///
/// Any URL without a parseable, positive `expire` value is treated as having
/// UNKNOWN expiry — never as expired — so serving falls through to the
/// existing reactive failure path instead of triggering speculative
/// refreshes.
bool isStreamUrlExpired(String url, {DateTime? now}) {
  final expireParam = Uri.tryParse(url)?.queryParameters['expire'];
  final expireSeconds = int.tryParse(expireParam ?? '');

  if (expireSeconds == null || expireSeconds <= 0) return false;

  final nowSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  return expireSeconds < nowSeconds;
}

/// The `expire` timestamp parsed from [url], or null when the URL carries no
/// usable expiry (missing, malformed or non-positive). Null means UNKNOWN,
/// never expired — the single rule every freshness decision below shares.
int? streamUrlExpireSeconds(String url) {
  final expireSeconds =
      int.tryParse(Uri.tryParse(url)?.queryParameters['expire'] ?? '');
  if (expireSeconds == null || expireSeconds <= 0) return null;
  return expireSeconds;
}

/// Freshness horizon of an extracted manifest: the earliest `expire` across
/// [urls], or null when ANY URL lacks a usable expiry.
///
/// Null poisons the whole manifest on purpose. A manifest whose selected URL
/// is fresh but whose sibling URLs carry no expiry cannot prove the selected
/// URL will still be fresh on the next serve — and the engines that omit
/// `expire` are exactly the ones whose URLs cannot be reasoned about, so
/// those manifests keep today's re-extract behavior instead of being cached.
int? manifestMinExpireSeconds(Iterable<String> urls) {
  int? min;
  var any = false;
  for (final url in urls) {
    final expire = streamUrlExpireSeconds(url);
    if (expire == null) return null;
    any = true;
    min = min == null || expire < min ? expire : min;
  }
  return any ? min : null;
}
