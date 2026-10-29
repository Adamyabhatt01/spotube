# yt-extract

Standalone Rust YouTube audio extractor. Goal: in-process, no Python/JVM/child
process, anonymous, ad-free audio on Android + desktop (later: embedded into
Spotube via a bridge; today: CLI).

## Usage

```
cargo build --release
./target/release/yt-extract manifest <videoId|watch-URL> [--client visionos|ios|android_vr|tv]
./target/release/yt-extract audio    <videoId|watch-URL> -o /tmp/out  # downloads best audio
./target/release/yt-extract play     <videoId|watch-URL>              # downloads, plays via mpv/ffplay, cleans up
./target/release/yt-extract search   "query" [--json]
```

`manifest`/`search --json` print machine-readable JSON on stdout; every
diagnostic goes to stderr, so the output pipes straight into `jq`.

## The 2026-10 extraction recipe (what made it work)

Discovered empirically; all four parts are load-bearing:

1. **visionOS identity works anonymously.** `VISIONOS / 1.02`
   (deviceMake Apple, RealityDevice17,1, Safari/605.1.15 UA, client-name 101)
   returns fetchable progressive/adaptive audio URLs. yt-dlp's own default is
   this client now; constants were copied from
   `yt_dlp/extractor/youtube/_base.py` (2026-10-26). Other identities today:
   `IOS` answers OK but only HLS/SABR (no audio URLs); `ANDROID_VR` URLs get
   bulk-range 403; `TVHTML5` says UNPLAYABLE without POT.
2. **Session bootstrap before `/player`.** A cold player call gets
   `LOGIN_REQUIRED: Sign in to confirm you're not a bot`. Fetching a watch
   page first (same cookie jar, same UA) plants `VISITOR_INFO1_LIVE`, `YSC`,
   `GPS`, `__Secure-YNID` and yields `visitorData`; carrying `visitorData` in
   the client context + `X-Goog-Visitor-Id` flips gated videos to OK. This is
   the same webpage-first dance yt-dlp traces as
   `Downloading webpage -> ... player API JSON`. If a stored session starts
   getting bot-gated anyway, the resolver wipes it, re-bootstraps and walks
   the ladder once more.
3. **Bounded Range requests for streams.** googlevideo 403s Range-less and
   open-ended GETs on third-party URLs; only bounded chunks (10 MB here,
   total length from `contentLength`, falling back to the `clen` URL param)
   are served. Downloads retry transient failures per chunk, verify the byte
   count, land on `<file>.part` + atomic rename, and refuse a server that
   ignores Range mid-file.
4. **No signature deciphering needed.** These client manifests carry plain
   URLs (`REQUIRE_JS_PLAYER: False` in yt-dlp terms) — no QuickJS/sig-harness
   dependency in the MVP. If `signatureCipher` ever reappears, that is the
   point where an embedded JS engine becomes necessary.

Stream choice: default-language audio track first (`audioTrack.audioIsDefault`),
Opus/WebM over AAC, then bitrate. Ad-free by construction: only
`adaptiveFormats`/`formats` are read, `adSlots`/`adFormats` are never parsed,
and formats with the exact ad content role (`CONTENT_ROLE_ADS`) are dropped.

## Maintenance contract

- Sessions persist to `$XDG_CACHE_HOME/yt-extract/session.json` (or
  `~/.cache/yt-extract/`), written 0600 and atomically. The 12h TTL counts
  from session *creation*, not last use. Runs after the first make zero
  watch-page requests, which is what keeps an IP off the 429/captcha path.
  Delete the file to force a fresh session.
- API calls back off and retry on 429/5xx before surfacing the failure.
- When extraction breaks: re-sync `src/clients.rs` from yt-dlp master's
  `_base.py` (client names/versions/UAs) and check `TRY_ORDER` — the trusted
  anonymous identity rotates (ANDROID → iOS → VISIONOS over 2024-2026).
- `--client` + `manifest`'s per-stream `fetchable` probe exist precisely to
  diagnose which identity died when something stops working.

## Known limits

- Age/login-restricted and kids videos still fall through to yt-dlp/NewPipe
  (they own attestation/POT; this crate deliberately does not).
- Throttling: URLs are served without a solved `n` param; sustained
  throughput may be capped (initial fetch measured fine). Add the ejs-style
  n-transform if real-world speed suffers.
- Live streams: detected (`isLiveContent`) and rejected with a clear message;
  segment-based (HLS/SABR) playback is out of scope.
