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
