# Spotube — Optimization Execution Plan

Status document for the verified optimization roadmap. Written 2026-09-20 from the
read-only performance investigation (source + measurements). Update the **Status
table** as each PR lands so a later session can resume without re-investigating.

- Branch: `master`, base commit at plan time: `fae936c1`
- Working tree at plan time: **120 dirty entries (user's own work) — never reset,
  revert, stash or discard it.** Each optimization lands as its own commit on top.
- Toolchain: Flutter 3.35.2 stable / Dart 3.9 (via `fvm`), Spotube 5.1.2+45
- Test suite at plan time: **283 tests green**, `fvm flutter analyze` clean

## Roadmap closed 2026-09-21

PR 1–6 landed in the working tree (uncommitted, per instruction — no commits were
authorized). PR 7 (C9) and PR 8 (C4) were **measured and deliberately not
implemented**; PR 9 is a plan only; PR 10 (this file + `.ai/` corrections) is done.

Update 2026-09-21: the `containsTracks` defect was **fixed** on an explicit go-ahead
(344 green, analyze clean, release build green, verified in-app). The media_kit
`setShuffle` `extras` strand is still reported-not-fixed, since it too changes
user-visible behavior — see `.ai/TODO.md` P1.

## Guiding rules (from the investigation)

1. Behavior-preserving only. If playback, queue, shuffle/repeat, history/statistics,
   source selection, URL expiry/403 recovery, download, local-library, plugin or
   lyrics behavior must change — **stop and report first**.
2. No speculative optimization: every change needs a located bottleneck, a measured
   cost, expected benefit, a regression test, and a before/after benchmark.
3. Do not rewrite architecture. Small, independently revertible commits.
4. Never claim improvement from code inspection. Measure, then record numbers in
   `.ai/PERFORMANCE.md` (only after PR 1 lands).
5. Do **not** add expensive instrumentation to release builds.

## Baseline (measured 2026-09-20, release build, this machine)

| Metric | Value |
|---|---|
| CPU (paused, 8–20 s) | 0.00 % |
| RSS / PSS idle | 447–500 MB / 348 MB |
| RSS after ~45 min with liked tracks loaded | 666–676 MB |
| Threads / fds | 104 / 54 |
| DB | 1.4 MB, 12 tables, exactly 1 index (`unique_blacklist`) |
| Table population | source_match 604 (204 B avg) · history 49 (1222 B avg) · lyrics 19 (2933 B avg) |
| Persisted queue | 1 track = 1223 B JSON (~0.5–1.1 KB/track) |
| Music cache on disk | 360 MB / 34 files (10.6 MB avg), no eviction |
| Startup | main-isolate CPU work finished ~2.1 s; RSS 368→565→~500 MB |
| `history SELECT *` (10k rows) | 6.8 ms (SQL only) |
| `jsonDecode` 10k track rows | 56 ms (JIT VM) |
| `recentlyPlayed` window CTE | 0.9 ms @2k · 1.7 ms @10k · 7.0 ms @40k |
| artists `json_each` distinct | 3.2 ms @10k · 13.5 ms @40k |
| Same queries **with** `INDEX(type,created_at)` | 6.8 / 13.5 ms → **no change** |
| `source_match` lookup @20k rows | 0.4 ms → 0.03 ms with composite index |
| 2000-file recursive walk | 15 ms; +per-file `length()` 19 ms |
| `jsonEncode` 600-track queue (269 KB) | 7 ms (JIT), excludes 600 `toJson()` |
| Playback tick dispatch rate | 5.0 events/s raw, 1.0/s per whole-second consumer; 8 consumers cost 144,000 gated dispatches per hour (PR 5) |

Synthetic-data benchmark method: copy the real DB to `/tmp`, inject rows, time with
`python3 sqlite3` + `fvm dart run` on a script kept **outside** the repo.

## Status table

| PR | Scope | Roadmap item | Status |
|---|---|---|---|
| 1 | Instrumentation + synthetic datasets | P0 / Wave 1 | **landed (uncommitted)** |
| 2 | History scaling | C1 | **landed (uncommitted)** |
| 3 | Queue persistence | C2 | **landed (uncommitted)** |
| 4 | Playback proxy requests | C5 | **landed (uncommitted)** |
| 5 | Position tick fan-out (+ connect payload C11) | C3 | **landed (uncommitted)** |
| 6 | Artwork decode + membership scans (C6 + C8) | C6, C8 | **landed (uncommitted)** |
| 7 | Local metadata cache | C9 | **rejected after measurement — no code** |
| 8 | Manifest TTL cache | C4 | **measured; not implemented (see PR 8 result)** |
| 9 | Startup ordering + disk/retention policy | C10, C13 | **plan only — see PR 9 section** |
| 10 | `.ai/` truth update | docs | **done** |

### PR 1 measured baseline (`fvm flutter test test/perf_baseline_test.dart`)

Counters live in `lib/utils/perf_counters.dart` (compiled out under
`kReleaseMode`); fixtures in `test/support/perf_fixtures.dart`.

| Dataset | Measured |
|---|---|
| queue 50 tracks | 35.7 KB, encode 7 ms, decode 7 ms |
| queue 600 tracks | 428.8 KB, encode 14 ms, decode 14 ms |
| queue 2000 tracks | **1.43 MB**, encode **22 ms**, decode **27 ms** |
| history 50 rows (40 track rows) | SQL fetch 4 ms, freezed parse 1 ms |
| history 5 000 rows (4 000 track rows) | SQL fetch 47 ms, parse 23 ms |
| history 25 000 rows (20 000 track rows) | SQL fetch **187 ms**, parse **76 ms** |

Two corrections to the investigation's estimates this replaces:

1. **A single scrobble over a 25 000-row history costs ~263 ms**, not the
   100–250 ms inferred — and `data` is a drift `MapTypeConverter` column, so
   every row is `jsonDecode`d during row mapping *and* parsed again by
   `HistoryTableData.track`. The fix must cut both (stop selecting `data` for
   aggregation, and stop parsing rows outside the visible page).
2. **Queue persistence is worse than estimated**: 2 encodes + 1 decode per track
   change ≈ 70 ms and 2.9 MB written at a 2 000-track queue.

Still not measurable headlessly: raw position dispatch rate (media_kit needs a
real player) and upstream HEAD/GET counts — both are now counter-instrumented and
dump with `SPOTUBE_PERF_COUNTERS=<seconds>` in a debug/profile run.


Skip a later PR if the earlier benchmark shows the problem does not exist at real
dataset sizes. Record that outcome in `.ai/AUDIT_STATE.md` as a disproven item.

---

## PR 1 — Instrumentation (P0, prerequisite for everything)

Purpose: make the numbers above reproducible, and close the two gaps the
investigation could not measure: **position dispatch rate** and **playback path**.

- `test/support/perf_fixtures.dart` — deterministic builders: history rows
  (50 / 5k / 25k, realistic ~500 B track JSON), queues (50 / 600 / 2000 tracks),
  a temp-dir file tree (2k / 20k audio files with embedded art).
- Counters, debug/test-only (no release cost):
  - rows parsed + µs per history watch event (`lib/provider/history/*`)
  - queue encode count + byte size (`lib/models/database/tables/audio_player_state.dart` path)
  - raw position dispatches/sec + per-consumer counts (`lib/services/audio_player/`)
  - upstream HEAD/GET count + time-to-audio (`lib/provider/server/routes/playback.dart`)
  - files scanned + MetadataGod calls + duration (`lib/provider/local_tracks/`)
  - `ImageCache.currentSizeBytes`, RSS/PSS sampling helper for the running app
- `.ai/PERFORMANCE.md`: measurement recipe (profile build + DevTools frame data,
  how to drive playback headlessly through `localhost:21808/playback/toggle-playback`).
- Tests: fixtures are deterministic; counters compiled out / no-ops in release.
- **Do not** add product behaviour changes here.

## PR 2 — C1: history stops re-parsing the world (highest value)

Files: `lib/provider/history/top/tracks.dart:159,210-248,251`,
`top/albums.dart:86`, `top/playlists.dart:50`,
`lib/provider/history/recent.dart:40`, `lib/provider/history/history.dart`.

Root cause: `AsyncNotifierProviderFamily`s (keepAlive, `top/tracks.dart:251`) hold
**unbounded** `watch()` queries; every scrobble insert
(`audio_player_streams.dart:169`) re-materializes every row and calls
`SpotubeTrackObject.fromJson` per row; `fixImageNotLoadingForArtistIssue` re-runs
(with per-artist network fetches) on **every** event.

Implement:
1. Aggregate in SQL (`GROUP BY item_id`, `COUNT(*)`), return `{id,count}`; resolve
   full JSON only for the top-N page actually displayed.
2. Bound the watched query with a `LIMIT` large enough for the visible list.
3. Run the image repair once per notifier lifetime, not per event.
4. Preserve tie-break: "first row whose artists all have images, else first row".
5. `autoDispose` the three **Stats-page** families only. **Do not** autoDispose
   `recentlyPlayedItems` (watched by the always-mounted Home section → flicker +
   refetch per Home visit); bound its query instead. **Never** autoDispose
   `syncedLyricsProvider` (intentionally keepAlive).

Golden test: old Dart grouping vs new SQL grouping on a fixed dataset (duplicates,
different artists/albums, missing artwork, ordering/ties) — must be identical.
Bench: per-track-change µs at 50 / 5k / 25k rows must be flat.
Expected: ~250–600 ms per track change at 25k rows → 5–30 ms.
Risk: Stats numbers shifting. Rollback: single revert, no schema change.

### PR 2 result (measured 2026-09-20, JIT test VM, `test/history_scaling_test.dart`)

Landed in `lib/provider/history/top/tracks.dart` (+ the two sibling families switched
to `AutoDisposeAsyncNotifierProviderFamily`), tests:
`history_track_grouping_test.dart` (equivalence, all six windows),
`history_image_repair_test.dart` (repair semantics), `history_scaling_test.dart`.

Per single history write, while the Stats page is open:

| Rows (groups) | Before | After | After, Dart parse share |
|---|---|---|---|
| 52 (17) | ~1 ms | 1–2 ms | ~1 ms |
| 5 002 (1 667) | 74 ms | 21–33 ms | 18–28 ms |
| 25 002 (8 334) | 263–713 ms | 106–119 ms | 100–106 ms |

Row parses fell from 3× rows to 1× groups (25k rows: 50k+ → 8.3k per event).

Deviations from the plan, both measured rather than assumed:

1. **`albums`/`playlists` left as they were** — 27 ms and 6 ms per write at 5k rows,
   i.e. the same order as the optimized tracks path. No bottleneck, so no change
   beyond instrumenting their parse counters.
2. **Top-N page materialization and a `LIMIT` on the watched query were NOT done.**
   The Stats list renders every group (`SliverInfiniteList(itemCount: items.length)`),
   so limiting the watch or resolving only a page would change displayed statistics.
   The residual ~100 ms at 25k groups is one `fromJson` per group, which the current
   UI contract requires. What was done instead: the three Stats families are
   `autoDispose`, so the recomputation no longer happens at all once the page is
   closed (guarded by "a write with no Stats page open recomputes nothing").
3. The per-event image repair became event-driven off the SQL `unresolved` flag and
   is idempotent; `recentlyPlayedItems` was already `LIMIT 10` bounded — left
   keepAlive as instructed.

## PR 3 — C2: queue persisted only when membership changed

Files: `lib/provider/audio_player/audio_player.dart` (`:108`, `:154`, `:245-268`,
`:262`; mutation sites `:427` add, `:486` remove, `:596` load, `:638`).

Root cause: the `playlistStream` listener maps every media through
`SpotubeMedia.media()` → `fromJson` and rewrites the whole `tracks` column
(`jsonEncode` of the entire queue, 269 KB per 600 tracks measured), and mutations
write again → 2 encodes + 1 full decode per track change.

Implement:
- On index/playing-only changes: write `current_index` / `playing` / `loop_mode` /
  `shuffled`, **not** `tracks`.
- Skip the write entirely when the track list is the same instance
  (`EqualUnmodifiableListView` compares `_source` identity — verified safe; riverpod
  2.6.1 `Notifier.state=` uses `identical`, also verified).
- Remove the duplicate encode inside mutation paths (the listener may not also write).

Tests: restore-equality (write → fresh `AppDatabase` → same state) for index change,
add, remove, reorder, shuffle toggle; explicit assertion that an index-only change
issues **no** `tracks` write; existing 19 download/seek + queue tests stay green.
Bench: encodes + bytes written + ms at 50 / 600 / 2000 tracks.
Expected at 600: 2 × 269 KB → 0 KB per track change.
Risk: crash-restart queue restore fidelity — mitigate with the restore tests.

### PR 3 result (measured 2026-09-20, JIT test VM, `test/queue_persistence_test.dart`)

| queue | two track changes, old path | now |
|---|---|---|
| 50 | 8 ms, 2 writes / 4 encodes / 103 KB | 0 ms, 0 / 0 / 0 KB |
| 600 | 32 ms, 2 writes / 4 encodes / 1233 KB | 0 ms, 0 / 0 / 0 KB |
| 2000 | 95 ms, 2 writes / 4 encodes / 4109 KB | 1–2 ms, 0 / 0 / 0 KB |

One real queue load at 600 tracks still costs 1 write / 2 encodes / 616 KB and
10 ms — unchanged, and that is the only path that may rewrite the column.

Findings worth keeping:
- **Drift encodes twice per write.** `UpdateStatement.write` calls
  `entity.toColumns(true)` and `validateIntegrity` calls it again, so every
  converted column's `toSql` (here `jsonEncode` of the whole queue) runs **2×**
  per UPDATE. Counters therefore read 2 writes → 4 `queue.encode`. Any future
  "shrink the write" idea must budget for that factor; the mitigation (a
  `Value<String>`-typed raw column write) would skip the converter entirely.
- The identity key is **the media objects**, not a list wrapper: media_kit
  publishes index-only events from the live `current` list (`real.dart:1604-1614`)
  and replaces `current` with a fresh list on every membership change
  (`real.dart:162, 469, 508, 533, 552, 683, 939`) — it never mutates a published
  list in place, so `identical` per element is a sound test.
- Deviation from the plan: no `EqualUnmodifiableListView` was involved (the queue
  is a plain `List<Media>`); the memo is `_lastSyncedMedias`, refreshed in
  `_updatePlayerState` whenever a write carries `tracks`, so it always describes
  what the column actually holds.

**Pre-existing bug found, not fixed** (`setShuffle`): media_kit rebuilds the
playlist as `Media(uri)` from mpv (`real.dart:923-927`), dropping `extras`, then
emits that playlist. `SpotubeMedia.media()` asserts in debug and throws in
release (`audio_player.dart` listener → `AppLogger.reportError`), so after a
shuffle toggle `state.tracks` and the persisted row stop following the backend
until the next `load`. Behavior is identical before and after PR 3; fixing it
means either tolerating media without `extras` (keep the last parsed queue) or
re-attaching `extras` by index — a behavior change, so it needs its own sign-off.

## PR 4 — C5: proxy request path (only the two verified items)

Files: `lib/provider/server/routes/playback.dart:231-238` (`_getTrackCacheFilePath`
→ `UserPreferencesNotifier.getMusicCacheDir()` at `user_preferences_provider.dart:150`),
`:296-370` (`streamTrackInformation`), `:372-459` (`streamTrack`, HEAD at `:419`).

Implement:
1. Memoize the music-cache dir per process (it never changes at runtime).
2. Small in-process cache of the upstream HEAD result `(content-length,
   content-type)` keyed by **(trackId, url)** with a few-second TTL, so mpv's HEAD
   and the immediately following GET share one upstream round trip. URL changes on
   every refresh ⇒ natural invalidation.

Do **not** break: range requests, seeking, content-type (incl. the m3u8 301 path at
`:436-448`), expiry handling, the reactive refresh at `:424-434`.
**Never** let a cached length survive a URL change.
Tests: HEAD, GET, range GET (mid/edge), seek, URL refresh, changed URL, expired URL.
Bench: upstream HEAD count per track start (2 → 1), time-to-audio, platform-channel
calls per media request (2 → 0).
Explicitly NOT in scope: the "duplicated expiry refresh" claim — reading
`resolveServingUrl:249-271` shows the second call is a no-op once fresh.

### PR 4 result (measured 2026-09-20, `test/playback_proxy_requests_test.dart`)

Per track start (mpv's HEAD + the GET that follows), counted at a real loopback
upstream and in a counting `PathProviderPlatform`:

| | before | after |
|---|---|---|
| upstream HEADs | 2 | 1 |
| upstream GETs | 1 | 1 |
| path_provider round trips | 2 | 0 extra (1 per process) |

- `_headProbes` is keyed by `track id|url` with a 5 s window and a 16-entry cap;
  it stores only the content type, because that is the one thing the GET-path
  HEAD is read for (the m3u8 301). No length is cached, so nothing can survive a
  URL change — a re-signed URL simply misses the cache.
- Behavior kept deliberately: the GET-path HEAD (and its refresh-and-retry on
  failure) still runs whenever there is no fresh probe, so expiry/reactive
  recovery is unchanged on every path except "the same URL was HEAD-verified
  within the last 5 s", where a failure is now caught by the GET itself and
  reaches the same fallback cascade as before.
- Tests cover: one HEAD per start, re-signed URL re-probes, HLS redirect with
  and without a reused probe, no cross-URL contamination (hls → non-hls),
  `bytes=100-199` → 206 with the right slice and `content-range`, expired URL
  re-signed before anything is sent upstream, and a failing GET still reaching
  the cascade.

## PR 5 — C3: one throttled tick at the player-service layer (+ C11)

Files: `lib/services/audio_player/audio_players_streams_mixin.dart:9-11` (raw),
`lib/utils/position_tick_gate.dart`, consumers at
`audio_player_streams.dart:108,144,182`, `discord_provider.dart:43`,
`provider/connect/*`, `modules/player/use_progress.dart:24-40`,
`modules/lyrics/use_synced_lyrics.dart:25`, `pages/lyrics/synced_lyrics.dart:97`,
`modules/root/use_global_subscriptions.dart:63`,
`provider/server/routes/connect.dart:186-191,208-213` (per-client whole-queue
jsonEncode + ungated position events).

Model:

```text
raw positionStream ──► seek-critical consumers (sponsor skip, scrub)
                    └► positionTickStream (≈1 Hz + immediate on seek/track change)
                          ► UI progress, Discord, external clients, media-session
```

- Keep the raw stream exported and documented; do **not** force one frequency on
  everyone. Sponsor skip must stay ≤200 ms resolution.
- Delete the three duplicated bespoke gates (`use_progress.dart:34`,
  `discord_provider.dart:45`, `positionProvider` users) once they consume the new stream.
- Seek / track transition must be able to force an immediate emission.
- C11: `ref.listen(audioPlayerProvider)` → `select` only the consumed slice, and
  gate position events per client.

Tests: bounded emission rate; immediate emission on seek and on track change;
sponsor-skip accuracy; lyrics highlight; Discord presence ≤1 Hz; connect socket
payload size. Bench: raw ticks/sec vs consumer ticks/sec, 30-min playback CPU.
**Do not claim a CPU win unless measured** — baseline CPU during playback measured ≈0.

### PR 5 result (measured 2026-09-20, `test/position_throttle_test.dart`)

`PositionTicker` (`lib/utils/position_tick.dart`) puts **one** whole-second gate
in front of the raw stream and hands out a single broadcast sequence;
`SpotubeAudioPlayers.positionTickStream` exposes it, `seek()` invalidates the
gate so a discontinuity is reported on the next position event instead of up to
a second later.

| Fan-out of 8 whole-second consumers, 1 h of playback | before | after |
|---|---|---|
| gated dispatches | 144,000 | 28,800 |
| handler calls that render something | 28,800 | 28,800 |
| dispatch wall time (async broadcast, like the real stream) | 499 ms | 151 ms |

That is a **dispatch-count** result, not a CPU claim: in-app CPU during playback
measured ≈0 at baseline, so nothing here is reported as a CPU win.

Migrated to the tick stream: scrobble + next-track prewarm
(`audio_player_streams.dart`), Discord presence, `use_progress`, glance widget,
Android/iOS MediaSession, Windows SMTC, connect-client position events.
Left on the raw stream deliberately: sponsor skip (≤200 ms), the buffering
watchdog in `use_global_subscriptions.dart` (pausing a second late would let mpv
hit the underrun), synced lyrics (both places), scrubbing.

Behavior notes (deviations from the letter of the plan, all in the same
granularity the consumers already had):
- The three bespoke gates are gone; `PositionTickGate` itself was deleted with
  them, so the file now holds only the shared ticker.
- Discord: the old `±500 ms` test compared **consecutive raw events** (~200 ms
  apart), so it could only ever pass on a discontinuity — normal playback never
  refreshed the presence from position. `presenceSeekThreshold` (1500 ms = one
  tick + slack) preserves that on the 1 Hz stream; a seek smaller than 1.5 s no
  longer re-publishes the presence `start` timestamp.
- The connect client's progress bar now moves at 1 Hz instead of 5 Hz — the same
  rate the host's own bar already used, and a seek forces a tick.
- C11: the queue payload shape is unchanged (the client assigns it wholesale to
  `queueProvider`, and there is no index-only event, so narrowing it would be a
  protocol change). Instead the send is gated by `isSameQueuePayload` on
  `tracks`/`currentIndex`/`collections` — the only parts the client cannot get
  from the dedicated playing/position/duration/shuffle/loop/volume events. Freezed
  hands those lists out as `EqualUnmodifiableListView`, whose `==` compares the
  **backing list by identity**, so the check is O(1) and never mistakes a real
  queue mutation for a duplicate. Counters: `connect.queueNotification` vs
  `connect.queueEvent`. Play/pause, loop and shuffle toggles now cost 0 encodes
  per client instead of one full queue `jsonEncode` each.

## PR 6 — C6 + C8: decode size and membership scans

Files: `lib/components/image/universal_image.dart:58-89`,
`lib/modules/theme_background/theme_background_image_provider.dart:30,38`,
`lib/pages/library/user_local_tracks/local_folder.dart:116-121,130-138`,
`lib/modules/player/player_actions.dart:59-70`,
`lib/components/track_presentation/presentation_list.dart:103-106`.

C6:
- Pass display dimensions into `imageProvider` for the **theme background** only
  (a blurred backdrop does not need 640×640); wrap the `FileImage` branch in
  `ResizeImage` like the `MemoryImage` branch.
- **First verify the source-selection ordering independently** for http / asset /
  file / base64 / memory: `Uri.tryParse(path) != null` at `:74` matches base64
  payloads, which likely makes the `MemoryImage`/`ResizeImage` branch unreachable
  (same predicate in `build()` at `:117`). Fix semantics only after a test proves
  what each input currently resolves to; do not silently change which branch a
  given input takes.
- `images.asUrlString(index: images.length - 1)` picks the *smallest* rendition for
  the backdrop — confirm intent before touching.

C8: replace nested scans with `Set` lookups on **stable ids**, not deep freezed
equality: queue membership in `local_folder.dart` (`AudioPlayerState.listContainsTracks`
— keep its public contract), `isDownloaded` in `player_actions.dart` (currently
`artists.asString()` per local file, on every active-track change), selection in
`presentation_list.dart`. Also fold `local_folder.directorySize`'s double recursive
walk (measured 34 ms per 2000 files) into one pass.

Bench: `ImageCache.currentSizeBytes`, decoded dimensions, scroll frame p99;
membership comparisons at 100×100 and 1000×1000.
Regression risk: **visual** (backdrop softness) — keep visible cover art untouched;
folder "playing" highlight semantics.

### PR 6 result (measured 2026-09-20, `test/universal_image_source_test.dart`, `test/player_membership_test.dart`)

Landed — two changes, both measured:

1. **C6, the real gap**: `UniversalImage.imageProvider` accepted `width`/`height`
   and then **dropped them on the file branch**, returning a bare `FileImage`.
   Local artwork is a file path (`local_tracks_provider.dart:117` →
   `localTrackFromFile(art:)`), so every sized request decoded at native
   resolution. Now wrapped in `ResizeImage(fit, allowUpscaling: false)`, the same
   treatment the memory branch already had. `Image.file` in `build()` already
   passed `cacheWidth/cacheHeight`; only the provider path was broken.

   | 1000×1000 sidecar, 80×80 request | before | after |
   |---|---|---|
   | decoded bitmap | 1000×1000 (4,000,000 B RGBA) | 80×80 (25,600 B) |
   | `ImageCache.currentSizeBytes`, 20 covers | 80,000,000 | 512,000 |
   | decode wall time (20 covers) | 72 ms | 65 ms |

   The win is cache residency, not CPU: 20 local covers used to consume the whole
   100 MB `ImageCache` budget; now 100 covers cost 2.56 MB. Parse time is
   unchanged (the file is still read and decoded, just into a smaller bitmap).

2. **C8, `AudioPlayerState.listContainsTracks`**: index the haystack into three
   sets (`localPaths`, `remoteIds`, `allIds`) that reproduce the pair rule in
   `listContainsTrack` exactly — two locals compare `path`, any other pairing
   compares `id`, so a local needle may be satisfied by a remote entry's id.
   Below `needles × haystack ≤ 256` it still scans, so the common single-needle
   case does not pay for building sets. Public contract unchanged.

   | queue × folder, 50 checks | naive | indexed |
   |---|---|---|
   | 100 × 100 | 1,446 µs | 1,026 µs (1.4×) |
   | 1000 × 1000 | 129,763 µs | 2,988 µs (43×) |
   | 2000 × 1 | 91 µs | 91 µs (scan path, unchanged) |

   Benefit is concentrated in the *positive* case (folder really is the playing
   queue); a folder that is not usually short-circuits on the first needle either
   way. Cross-validated against the old implementation on 200 randomized pools.

Rejected after measuring — do not redo without new evidence:

- **Theme-background resize (C6 second half).** `themeBackgroundImageProvider`
  passes no dimensions, so the shell backdrop decodes at native size. On the real
  Caelestia wallpaper here (1828×1029 JPEG) that is 7,524,048 B — and requesting
  1920×1080 with `fit` + `allowUpscaling: false` decodes **exactly the same
  1828×1029**. The album-art backdrop path picks the *largest* Spotify rendition
  (640×640 = 1.6 MB; `asUrlString(index: length - 1)` sorts ascending, so the
  earlier "picks the smallest" note was wrong). Nothing to reclaim without
  changing which URL is fetched, which is a behavior change.
- **`directorySize` single pass (C8).** Measured on a 2000-file tree: materialize
  + `Future.wait` 68 ms cold / 45 ms warm vs `await for` accumulating 70 ms cold /
  48 ms warm. The cost is 2000 stat syscalls, not the intermediate list. No win.
- **`presentation_list.dart` selection scan (C8).** `selectedTracks.any(...)` runs
  per *visible* tile (~15) over a user-sized selection (single digits). Not a
  bottleneck at any observed size.
- **`isDownloaded` in `player_actions.dart` (C8).** Real O(n) —
  `artists.asString()` per local file, ~1.5–2 ms per active-track change at 5000
  files — but it is a correctness smell too: it re-implements the
  name+album+artist match that `track_options_provider.dart` already does. Fixing
  it properly means deduping that logic into one place, which is a refactor, not
  an optimization. Left alone; recorded in `.ai/TODO.md`.

**Defect found — FIXED 2026-09-21.** `AudioPlayerState.containsTracks`
(`state.dart:112`) shadowed the field with its parameter and called
`listContainsTracks(tracks, tracks)`, so it returned `needles.isNotEmpty` and
ignored the playlist entirely. Proven by test: with a queue holding
`/music/in-queue.mp3`, `containsTracks([/music/other-folder.mp3])` returned
`true`. Consequences at the four call sites (`local_folder.dart:59,79,97`,
`top_tracks.dart:69`): folder/playlist **Play**, **Shuffle play** and **Add to
queue** all took the "already playing" branch and did nothing. This was observed
live during PR 5 verification — synthetic clicks on the Downloads folder's play
button produced no queue change. It changes user-visible behavior, so it was
reported first and applied only on an explicit go-ahead: the parameter is now
`needles`, six regression tests were added, and the release build was re-checked
in-app (Downloads Play loaded the queue; Cache folder Play replaced it; Downloads
Add to queue appended 516 tracks).

## PR 7 — C9: persistent local-metadata cache — **NOT IMPLEMENTED (rejected after measurement)**

The plan below is kept as written so the decision is auditable. It was not built:
the benchmark in `.ai/PERFORMANCE.md` ("Local-metadata rescan") disproved the
premise before any code was written.

| library | walk | warm rescan today | simulated cached path |
|---|---|---|---|
| 516 files (real) | 1 ms | **38 ms** | 17 ms |
| 2,000 files | 11 ms | **152 ms** | 67 ms |
| 8,000 files | 15 ms | **510 ms** | 234 ms |

Reasons for rejection: the provider is keepAlive so a rescan happens once per
process (plus explicit refresh and local-track delete), off the track-start path;
the work is async across waves so it costs library latency, not frames; a perfect
cache still pays the `stat()` + art-existence floor, capping the win at ~2.2×; and
it is the only item on the roadmap needing a schema migration.

Side finding kept (moved to PR 9 / C13 retention): extracted artwork in
`<temp>/spotube/` is never pruned — 1,093 files / 39 MB for a 516-track library,
and `/tmp` is tmpfs here.

Original plan:

Files: `lib/provider/local_tracks/local_tracks_provider.dart:95-123,171-224`,
`lib/models/database/*` (new table + `make migrate`).

Cache keyed by `path + mtime + size` → parsed tags (+ art path). Re-read only
new/changed/invalid entries; a user-visible refresh forces a full rescan. Handle
rename, move, delete, unmounted external drives, corrupt metadata (fall back to
filename-derived track, as today). Keep the existing wave bounds and the
`ref.onDispose` cancellation sentinel — **do not rewrite the scan concurrency**.

Migration: explicit, version-paired test like the v7–v12 hardening, rollback
understood, existing DBs keep working.
Bench: initial scan / unchanged rescan / 1-file change / full refresh at 2k and 20k
files (this machine currently has **0** local files — the fixture must create them).

## PR 8 — C4: manifest TTL cache — **MEASURED, NOT IMPLEMENTED**

### PR 8 result (measured 2026-09-21)

The cost is real and it is the largest per-event latency found in this roadmap,
but the cache as specified cannot be validated here, so it was not built.

- Source-verified: a `source_match` **hit** still calls `streams(item)`
  (`sourced_track.dart:170`) — the identity is cached, the manifest is not.
- Measured with the app's own engine binary
  (`~/.local/share/oss.krtirtho.spotube/NewPipeCLI --streams <id>`): 1,456–1,806 ms
  per real manifest (4 runs), 218–382 ms on the error path, 2–3 ms process floor —
  so ~1.2–1.5 s is upstream extraction, not startup.
- Already mitigated on the dominant path: next-track prewarm at 80 % of the
  current track (`audio_player_streams.dart:187-237`) plus the bounded
  current+next retention on `sourcedTrackProvider`; both consumers
  (`activeTrackSourcesProvider`, `queryingTrackInfoProvider`) watch the same
  family entry, so there is exactly one resolution per track.
- Blocking unknown: every manifest fetched on this machine had `audioStreams: []`
  and its single `videoStreams` entry carried **no `url`**, so there is no
  `expire` parameter to derive a TTL from, no way to test "never serve a
  known-expired URL", and no repeat-play time-to-audio benchmark. The plan's own
  precondition ("bench time-to-audio; assert zero new 403-refresh loops") is
  unmeetable from this host.
- Decision: leave the code alone. Building an unexercisable cache in front of the
  403-loop / tv-client-fallback machinery fixed on 2026-09-20 is the worst
  risk-to-benefit pair remaining. Re-entry condition recorded in
  `.ai/PERFORMANCE.md`.

### Original plan

Files: `lib/services/sourced_track/sourced_track.dart:110-128` (hit path
`break`) and `:170` (`streams(item)` always fetched), `source_match` table.

Cache the resolved manifest next to the cached identity with a TTL derived from the
URL's `expire` parameter (reuse `isStreamUrlExpired`), keyed by
`(trackId, sourceType, engine)`. An expired entry is a **miss**. Preserve
`refreshStreamingUrl`, `NoValidStreamError` and the tv-client fallback fixed on
2026-09-20 — never serve a known-expired URL. Ship disabled behind a debug flag
until tests + bench pass.
Bench: time-to-audio on repeat plays; assert zero new 403-refresh loops.

## PR 9 — C10 + C13: startup ordering, cache/history policy — **PLAN ONLY (not executed)**

Corrected against source on 2026-09-21: an earlier pass **already** deferred
`NewPipeExtractor.init`, `YtDlp.setBinaryLocation`, `FlutterDiscordRPC.initialize`
and `localNotifier.setup` into `_initDeferredServices()` (`main.dart:131-155`,
called from a post-frame callback at `:363`) and already releases the splash on
first frame (`:358`). Do not re-plan those.

### C10 — what is actually left on the pre-`runApp` path (`main.dart:183-253`)

| step | constraint | verdict |
|---|---|---|
| `MediaKit.ensureInitialized()` | synchronous; player is built during startup | keep |
| `migrateMacOsFromSandboxToNoSandbox()` | macOS-only, but awaited on every desktop launch | gate on `kIsMacOS`, then keep |
| `MetadataGod.initialize()` | synchronous `.so` load; local scan uses it | keep |
| `await KVStoreService.initialize()` | first-frame consumers (theme cache, prefs) | keep |
| `await windowManager.setPreventClose(true)` | nothing before first frame depends on close behavior | **move** to `_initDeferredServices`, and make `useCloseBehavior` await it |
| `await SMTCWindows.initialize()` (Windows) | media keys only | **move** |
| `await EncryptedKvStoreService.initialize()` | **hard ordering constraint** — `encrypted_text.dart:12,27` dereference `encryptionKeySync!` inside drift type converters, so it must finish before the first read of an encrypted column | keep for now (see below) |
| `AppDatabase()` | lazy connection | keep |
| `await WindowManagerTools.initialize()` | tray/window ops only, all post-first-frame | **move** |

Notes for whoever executes this:
- On Linux non-Flatpak `EncryptedKvStoreService.isUnsupportedPlatform` is true and
  `encryptionKey` just delegates to `KVStoreService.encryptionKey`, which step 4
  already loaded — so this step is cheap **here** and slow on the platforms that
  really use `flutter_secure_storage`. Do not move it before the encrypted-column
  readers are made awaitable, or `encryptionKeySync!` throws a null-check on the
  first DB read.
- Measure before moving anything: time process-start → first frame
  (`:358` post-frame hook) and → splash removal, per step, using
  `guardedStartupInit` timings or `PerfCounters` with `SPOTUBE_PERF_COUNTERS=1` on
  a debug build. Only move a step that measures > ~50 ms; the ordering constraints
  above are real and the roadmap baseline already puts all main-isolate startup
  work at ~2.1 s.
- Regression checks: login state still resolves (it reads the encrypted store),
  close-to-tray still works on Linux/Windows, media keys still work on Windows,
  and no `Null check operator used on a null value` from `encrypted_text.dart`.

### C13 — retention policy

1. **Music cache** (measured 360 MB / 34 files, no quota): optional LRU/quota
   setting, **off by default**. Never evict the current or next track (respect
   `sourcedTrackRetentionProvider`), never touch `.part` files, and report bytes
   freed back to the Settings storage row.
2. **Orphaned extracted artwork** (new PR 7 finding): `<temp>/spotube/` is written
   by the local scan and never pruned — 1,093 files / 39 MB against a 516-track
   library on this machine, and `/tmp` is tmpfs here so the orphans cost RAM.
   Plan: after a scan that completed **without cancellation** and whose directory
   **existed**, delete art files whose source path is gone. Skip pruning for any
   location that failed to stat (unmounted drive) or when `_ScanCancelled` fired.
3. **History**: optional pruning cap as a setting. Pure policy — the table holds
   49 rows and PR 2 made the aggregation scale-independent.

## PR 10 — `.ai/` truth update — **DONE 2026-09-21**

PR 1–8 outcomes, the measured tables, the rejected candidates and the two known
defects are recorded in `.ai/PERFORMANCE.md`, `.ai/AUDIT_STATE.md`,
`.ai/CHANGELOG.md` and `.ai/TODO.md`; this file's status table now matches.
Remaining staleness risk: the startup baseline (~2.1 s) and RSS numbers predate
PR 2–6 and were not re-measured — re-measure before quoting them.

---

## Explicitly out of scope (measured false positives — do not reintroduce)

| Idea | Why rejected |
|---|---|
| C9 persistent local-metadata cache | measured: warm rescan is 38 ms @516 / 152 ms @2k / 510 ms @8k files, once per process, async; a simulated perfect cache only reaches 17/67/234 ms because `stat()` + art-existence checks are an irreducible floor. Only roadmap item needing a schema migration. |
| C4 persistent manifest TTL cache | the 1.4–1.8 s resolution cost is real, but prewarm-at-80 % + bounded current/next retention already cover sequential playback, and this host returns manifests with no stream URLs — so there is no `expire` to key a TTL on and the required tests/bench cannot run. See PR 8 result. |
| Indexes on `history` / `lyrics` / `skip_segment` | measured 6.7→6.8 ms and 12.5→13.5 ms with `INDEX(type,created_at)`; queries read nearly whole table |
| `source_match` index | 0.4→0.03 ms only at 20k rows; 604 rows today; also `uniq_track_match` was deliberately dropped in v9→v10 (multiple rows per track are intended) |
| Download progress provider churn | already throttled to 250 ms (`shouldEmitDownloadProgress`) and progress flows through a per-task `StreamController`, not provider state |
| Download-dir walk per request | measured 0.24 ms @5000 files; already indexed by `DownloadedFileIndex` |
| mpv thread reduction (104 threads) | fixed stack cost, no growth observed |
| mimalloc / large virtual mapping "leak" | still no RSS/PSS/heap evidence |
| Freezed `fromJson` micro-opts, `toList()` removal, `Value(state.tracks)` | identity semantics verified safe (`EqualUnmodifiableListView` compares `_source`; riverpod uses `identical`) |
| Blanket `autoDispose` | breaks Home recents (`recentlyPlayedItems`), lyrics (`syncedLyricsProvider`), plugin/theme VM caches |
| Rewriting local-scan concurrency | already bounded + cancellable |
| Provider-graph cosmetic refactor | not a cost |
| Blur / `surfaceBlur` reduction | mechanism verified (shadcn `AppBar` always builds a `BackdropFilter`, `SurfaceBlur` skips at ≤0) but no frame-time profile exists → needs PR 1 data first |
| "Duplicated expiry refresh" in `resolveServingUrl` | second call is a no-op once the URL is fresh |

## Per-PR validation loop (run after every PR)

```bash
fvm flutter analyze
fvm flutter test <targeted>        # then full: fvm flutter test   (baseline 283 green)
fvm flutter build linux --release  # only for benchmarks
git diff --check && git status --short   # confirm only intended files
```
Benchmark on the same synthetic dataset as the baseline; write the before/after
table into `.ai/PERFORMANCE.md` and the investigation outcome into
`.ai/AUDIT_STATE.md` (completed or disproven).

## Report template (one per PR)

```text
Optimization:
Baseline:
After:
Dataset:
CPU:   Memory:   Latency:   I/O:   Network:
Tests:
Behavior:
Regression risk:
```

## Known gaps — status at roadmap close (2026-09-21)

1. ~~Playback tick dispatch rate never measured~~ **closed by PR 5**:
   18,000 raw events × 8 consumers over 3600 s → 144,000 gated dispatches before,
   28,800 after (568.7 ms → 164.8 ms).
2. No DevTools frame timeline: the release build has no VM service; use a
   `--profile` build. **Still open** — which is why the blur/`surfaceBlur` idea
   stays on the rejected list.
3. ~~No local library on this machine~~ **closed**: the real library is 516 files
   / 4.6 GB (`~/Music/Spotube`), and PR 7 built 2k and 8k synthetic fixtures on top
   of it (deleted after measuring).
4. RSS 500→676 MB after loading liked tracks is *observed*, not attributed to any
   single retention path. ~~**Still open.**~~ **Attributed 2026-10-19: it was
   not a retention path at all.** The Dart VM's live heap is 27.5 MB (the VM's
   own `getMemoryUsage`); the rest was the kernel backing the VM's
   sparsely-touched 5.1 GB arena with 2 MB transparent huge pages.
   `prctl(PR_SET_THP_DISABLE)` (Linux runner + the Android equivalent) drops
   the footprint from **PSS 548 → 315 MB / RSS 648 → 415 MB** with the
   smoothness cost inside run-to-run variance. Attribution, the Flutter
   floor (90 MB PSS) and the per-item verdicts are in `.ai/MEMORY.md`.
5. New, opened by PR 8: remote playback on this host is **not currently
   evidenced** — every manifest fetched returned no stream URLs at all while the
   metadata API returned 429s. Needs its own investigation before any C4 work.
