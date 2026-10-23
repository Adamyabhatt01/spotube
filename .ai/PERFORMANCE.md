# Performance Knowledge Base

Persistent record of measured Spotube performance facts. Do not invent values;
"Not measured" is an acceptable entry.

## Environment (dev/test)

- OS: Linux
- Flutter: 3.35.2 (stable), Dart SDK `>=3.0.0 <4.0.0`
- Builds via `fvm`
- RAM/GPU specifics: not recorded. Add only if relevant to a task.

## Baseline measurements

| Metric | Value | Build | Scenario | Date | Notes |
|--------|-------|-------|----------|------|-------|
| Idle RSS (release, feature-fixed) | ~573 MB | Linux release | Fresh app open, plugins loaded | 2026-09-19 | After Hetu VM caching fix |
| Idle RSS (release, pre-fix) | ~570–580 MB rising to ~722–725 MB | Linux release | Same scenario | 2026-09-19 | Was climbing; plateaued after fix |
| Hetu `to compile` events (post-fix) | flat (7 at startup, ~8–9 distinct modules total) | Linux release | Idle | 2026-09-19 | One-time distinct modules, no recurring churn |
| Hetu `to compile` events (pre-fix) | climbing (22+, recurring same module) | Linux release | During playback | 2026-09-19 | VMs rebuilt per stream request |
| `writePlaylistMembership` 500 tracks (baseline) | 36 ms | Test, NativeDatabase.memory() | Full rewrite of a 500-track order | 2026-09-23 | opt/downloads-perf Phase 0; harness test prints this in expanded reporter |
| Idle RSS/PSS (release, HEAD `9b294a0c`, fresh build) | RSS 612→648→676→629 MB / PSS 540→576→606→545 MB at +25s/+95s/+220s/+350s | Linux release | Fresh launch, real profile (2.4 MB DB, 4.6 GB local lib), untouched | 2026-09-24 | Peak at ~3.5 min as home+library+art load, then settles back — front-loaded settling, not a leak. Threads 109, fds 78. Hetu `to compile` flat at 7 (5 distinct modules). Zero 401/429/cast errors. Old Sep-22 bundle was stale; rebuilt before measuring. |
| Idle RSS/PSS (release, fresh build, **measured**) | **PSS 496.7 MB / RSS 610.0 MB at t+30s; PSS 548.1 MB / RSS 648.1 MB at t+300s** | Linux release | Fresh launch, idle, home screen only (not driven) | 2026-10-19 | `scripts/mem-report`; PSS is primary. Confirms the 2026-09-24 PSS series (540→606 MB) and supersedes the 348 MB PSS in `OPTIMIZATION_PLAN.md:41` — that figure predates it by 200 MB. Full attribution + Flutter floor (PSS 90 MB / RSS 188 MB) in `.ai/MEMORY.md`. |
| Idle RSS/PSS (release, **after the THP fix**) | **PSS 280.5 MB / RSS 380.1 MB at t+30s; PSS 314.8 MB / RSS 415.2 MB at t+300s (app process)** | Linux release | Fresh launch, idle, not driven | 2026-10-19 | `prctl(PR_SET_THP_DISABLE)`: the Dart VM's 5.1 GB heap arena was being backed by 2 MB transparent huge pages, so a few KB touched cost 2 MB of RSS. Live Dart heap is 27.5 MB either way. Smoothness unchanged within run-to-run variance (fault rate and CPU overlap across four runs each). Flutter floor 90 MB PSS. |
| Idle RAM/CPU (release, fork.2 `2be74adf`) | **PSS 303–330 MB / RSS 376–419 MB across t+30s..t+5min; CPU median 27.1% of one core, range 22.6–33.4%** | Linux release | Two fresh 5-min runs, visible window, no interaction | 2026-10-20 | PSS 323–330/RSS 409–419 at t+30s; transient 338–368/RSS 411–444 at t+3min (artwork settle); 303–328/376–401 at t+5min. Ten 25s CPU windows, run means 29.1% and 26.6%. Compositor/NVIDIA work excluded. Harness/output in `build/bench/` (ignored). |

Not measured: Android RSS/CPU, Android frame time / skipped frames / jank
counts (no device, AVD or adb on this host — see "Android frame-pipeline
pass"), sync-duration numbers (Genius sync not implemented).

## Known performance findings

### Hetu plugin VM churn (FIXED)
- **Finding:** the source-fallback path rebuilt a fresh Hetu VM on every stream
  request, visible as the same plugin module compiling at many distinct
  timestamps and rising RSS.
- **Fix:** playback HEAD/GET fallback made **lazy** (only resolves the cascade
  after a real failure); a **global per-`(config, engine)` plugin VM cache**
  (`_pluginCache` in `source_resolver.dart`) reuses VMs; theme plugin VMs
  memoized; resolver reuses `audioSourcePluginProvider` for the default
  candidate (no duplicate VM).
- **Measured:** `to compile` flat, RSS plateaus (~722–725 MB) instead of
  climbing.

### Lyrics page open: hidden tab layout + full-resolution palette (FIXED)
- **The hidden Plain tab was laid out on every open.** Flutter's
  `IndexedStack` wraps each child in `Visibility(maintainSize: true)`, so the
  non-selected child stays mounted *and laid out* — only `paint` is skipped.
  The Plain tab is one giant, non-lazy `SelectableText`: measured on the real
  page with `skipOffstage: false`, its render object was **28,800 px tall**
  for a 120-line lyric. The repo's guard test reported the tab as absent only
  because `find.byType` skips offstage elements.
  There is no "mounted but never laid out" primitive in Flutter (`Offstage`
  lays its child out with the *same* constraints), so the tab now only enters
  the tree once it has been asked for.
- **Measured** (host, JIT): lyrics-page first frame at n=300 lyric lines
  **~112 ms → ~50 ms**.
- **The palette was quantised at full resolution on the UI isolate.**
  `PaletteGenerator.fromImageProvider` passes `size:` to the
  `ImageConfiguration`, and `MemoryImage` ignores it — the artwork was decoded
  at its native size and every pixel was walked. The code comment claimed a
  "50px sample"; it was not one.
- **Measured** quantizer cost alone (host, JIT, warmed):
  50×50 → **2 ms**, 100×100 → 3 ms, 300×300 → 19 ms, 640×640 → **81 ms**.
  A phone CPU is several times slower, and this ran on the UI isolate on every
  artwork change while the lyrics page was open.
- **Fix**: the artwork is downscaled by the decode itself (`ResizeImage` at
  50 px, `allowUpscaling: false`) before it reaches the quantizer, and the
  palette reads the *smallest* rendition instead of pulling the full-size
  cover a second time.

### Radio browse caching (FIXED)
- **Finding**: the Radio page is torn down whenever the user leaves the tab,
  and its station family plus the tag/country lists were auto-disposed, so
  **every visit refetched everything**. Measured against the real providers
  with a counting fake directory: **5 directory requests per visit**
  (popular + the Music rail + the News rail + tags + countries), and the same
  five again on the next visit.
- The plugin-state sync made it worse: it invalidated all three browse
  providers on *any* plugin-state emission, and that state also carries auth
  and progress updates.
- **Fix**: the browse answers are held for five minutes past their last
  listener (`ref.cacheFor` — the pattern every other single-item provider in
  `lib/provider/metadata_plugin/` already uses), and the invalidation is
  scoped to a change in the set of radio-capable directories.
- **After**: a revisit makes **0** directory calls
  (`test/radio_stations_provider_test.dart`).

### Lyrics sync highlight (FIXED)
- Exact-integer-second map lookups caused the highlight to lag/freeze between
  lines and after seeks.
- Replaced with binary search on the sorted lyric list
  (`use_synced_lyrics.dart`), index-based, `most recent time <= position + delay`.
- Removed dead `syncedLyricsMapProvider`.

### Position tick fan-out (FIXED, PR 5)
- The raw libmpv position stream fires ~5/sec. Eight consumers only render
  whole seconds and each subscribed to the raw stream with its own throttle
  (`use_progress`, Discord presence, glance widget, MediaSession, SMTC,
  scrobble, prewarm, connect clients) — **144,000 gated dispatches per hour of
  playback** to produce 28,800 updates.
- **Fix:** one `PositionTicker` (`lib/utils/position_tick.dart`) behind
  `audioPlayer.positionTickStream`; the bespoke gates are gone and those
  consumers share one sequence. `seek()` calls `_invalidatePositionTick()` so a
  discontinuity is reported on the next position event, not up to a second late.
- **After:** 28,800 dispatches (5x fewer); same 28,800 rendered updates.
  Measured in `test/position_throttle_test.dart` (prints a
  `[position-fanout]` line). **No CPU claim**: in-app playback CPU was ~0 at
  baseline, so this is dispatch work, not measured frame time.
- Still raw on purpose: sponsor skip (needs <=200 ms), the buffering watchdog in
  `use_global_subscriptions.dart`, synced lyrics (both places), scrubbing.
- Connect clients: position events ride the tick stream (1 Hz, was 5 Hz) and the
  whole-queue payload is only sent when `tracks`/`currentIndex`/`collections`
  actually changed (`isSameQueuePayload`; freezed's `EqualUnmodifiableListView`
  makes that an identity check on the backing list, not a deep compare).
  Play/pause/loop/shuffle toggles used to `jsonEncode` the entire queue per
  connected client; they now cost nothing. Counters:
  `connect.queueNotification` vs `connect.queueEvent`.

### Playback-history aggregation (FIXED, PR 2)
- **Finding:** one scrobble re-ran `watch()` over the whole history window; drift
  decoded every row's `data` blob (`MapTypeConverter`) and `HistoryTableData.track`
  parsed it again, and the grouping picked a representative per group — 3+ parses
  per row. Measured **74 ms/write at 5k rows, 263–713 ms at 25k**.
- **Fix:** grouping, counting, representative choice and the "artist still misses
  images" flag moved into one SQLite statement (`json_extract`/`json_each`, per-row
  flags materialized once); Dart parses exactly one track per group. The three
  Stats-page families became `autoDispose`, so a closed Stats page costs nothing.
- **After:** 21–33 ms at 5k, 106–119 ms at 25k, flat in *groups* not rows. ~90 % of
  the residual is `SpotubeTrackObject.fromJson` per group, which the Stats list
  (renders every group) requires.
- **Scope decision, measured:** `topAlbums` (27 ms) and `topPlaylists` (6 ms) at 5k
  rows showed no bottleneck — left unchanged.
- Files: `lib/provider/history/top/{tracks,albums,playlists}.dart`,
  tests `history_track_grouping_test.dart`, `history_image_repair_test.dart`,
  `history_scaling_test.dart`.

### History summary panes (FIXED, audit PR 8)
- **Finding:** the Stats header kept six watched queries alive; every scrobble
  re-scanned `history_table` six times (two of them unwindowed) and pushed six
  separate states, and the provider was keepAlive so it kept doing that with the
  Stats page closed.
- **Fix:** one `UNION ALL` statement computing all six numbers (the artist count
  via the same `json_each` join), one `watch()`, value equality on
  `PlaybackHistorySummary` so a write that moves no number notifies nobody, and
  `autoDispose`. The calendar-month window became a real `[startOfMonth,
  startOfNextMonth)` bound instead of `day: 30, hour: 23`, which had been
  dropping day 31.
- **After:** 1 statement and 1 emission per write, down from 6 and 6
  (`test/history_summary_test.dart` pins both, plus 0 notifications for a
  no-op write).
- Files: `lib/provider/history/summary.dart`, `test/history_summary_test.dart`.

### Queue persistence on playlist events (FIXED, PR 3)
- **Finding:** media_kit emits a playlist event for *index* changes as well as
  membership changes. The listener answered every event by re-decoding each media
  (`SpotubeMedia.media` → `fromJson`) and rewriting the `tracks` column, and the
  mutation path wrote again — so advancing one track in a 600-track queue cost a
  full queue decode plus `jsonEncode` of the queue. Measured **8 ms / 103 KB at 50
  tracks, 32 ms / 1233 KB at 600, 95 ms / 4109 KB at 2000** (two track changes).
- **Fix:** the listener keeps `_lastSyncedMedias` (refreshed whenever a write
  actually carries `tracks`) and, when the event's media are element-for-element
  the same objects, publishes the existing queue and omits the `tracks` column from
  the UPDATE. `SpotubeMedia.media()` returns its argument when it is already a
  `SpotubeMedia`.
- **After:** 0 writes, 0 encodes, 0 KB, 0–2 ms per two track changes at every queue
  size; a real membership change still costs exactly one write (616 KB / 10 ms for
  one 600-track load).
- **Drift fact to remember:** every UPDATE runs a converted column's `toSql` twice
  (`validateIntegrity` + `write` both call `toColumns`), so one queue write is two
  full `jsonEncode`s of the queue.
- Files: `lib/provider/audio_player/audio_player.dart`,
  `lib/services/audio_player/audio_player.dart`, test `queue_persistence_test.dart`.

### Playback proxy request path (FIXED, PR 4)
- **Finding:** mpv probes a stream with HEAD and then GETs it seconds later. The
  HEAD handler asked upstream for the headers, and the GET handler asked **again**
  — only to read the content type for its m3u8 check. Plus every request resolved
  the music-cache directory through a platform channel. Measured at a loopback
  upstream: **2 upstream HEADs and 2 path_provider round trips per track start**.
- **Fix:** `_headProbes` in `ServerPlaybackRoutes` remembers the content type per
  `track id|url` for 5 s (16 entries max), so the GET reuses the answer the HEAD
  already paid for; `UserPreferencesNotifier` resolves the cache *root* once per
  process (Android still re-checks/creates the directory per call, since the OS can
  drop it).
- **After:** **1 upstream HEAD, 1 GET, 0 extra path_provider calls** per track start
  — one upstream round trip off the time-to-audio path.
- **Invariants:** nothing but the content type is cached and the URL is part of the
  key, so a re-signed URL can never inherit a stale answer; range/seek (206 +
  `content-range`), the m3u8 301, proactive expiry re-signing and the reactive
  HEAD-refresh + fallback cascade all still run whenever there is no fresh probe.
- Files: `lib/provider/server/routes/playback.dart`,
  `lib/provider/user_preferences/user_preferences_provider.dart`,
  test `playback_proxy_requests_test.dart`.

### Local-tracks scan bounding
- Directory scan is streamed in bounded waves with concurrency caps, temp dir
  hoisted, stale scans cancelled via `ref.onDispose` sentinel
  (`lib/provider/local_tracks/local_tracks_provider.dart`).

### Sized artwork decode (FIXED, PR 6)
- **Finding:** `UniversalImage.imageProvider` took `width`/`height` and dropped
  them on the **file** branch, returning a bare `FileImage`. Local artwork is a
  file path (`local_tracks_provider.dart:117` → `localTrackFromFile(art:)`), so
  every sized request decoded at native resolution. `Image.file` in `build()`
  already passed `cacheWidth/cacheHeight`; only the provider path was broken.
- **Fix:** wrap in `ResizeImage(policy: fit, allowUpscaling: false)` — what the
  memory branch already did.
- **Measured** (1000×1000 sidecar requested at 80×80, widget test):

  | | before | after |
  |---|---|---|
  | decoded bitmap | 1000×1000 (4.0 MB RGBA) | 80×80 (25.6 kB) |
  | `ImageCache.currentSizeBytes`, 20 covers | 80,000,000 | 512,000 |
  | decode wall time (20 covers) | 72 ms | 65 ms |

- **Conclusion:** the win is cache **residency**, not CPU — 20 local covers used
  to eat the whole 100 MB `ImageCache` budget. Parse time is unchanged (the file
  is still read and decoded, just into a smaller bitmap).
- Files: `lib/components/image/universal_image.dart`,
  test `universal_image_source_test.dart`.
- **Rejected:** the shell backdrop (`themeBackgroundImageProvider`, no
  dimensions) is *not* a win — the real 1828×1029 wallpaper decodes identically
  when asked for 1920×1080 with `fit` + no upscaling. Nothing to reclaim without
  changing which URL is fetched.

### Queue-membership scans (FIXED, PR 6)
- **Finding:** `AudioPlayerState.listContainsTracks` did `needles.every(…)` over
  the whole queue — O(n·m), and the benefit is concentrated in the *positive*
  case (a folder that really is the playing queue), since a non-match
  short-circuits on the first needle either way.
- **Fix:** index the haystack into three sets (`localPaths`, `remoteIds`,
  `allIds`) that reproduce `listContainsTrack`'s pair rule exactly (two locals
  compare `path`, anything else compares `id`, so a local needle may be satisfied
  by a remote entry's id). Below `needles × haystack ≤ 256` it still scans, so
  the common single-needle case does not pay for building sets.
- **Measured** (50 checks, µs):

  | queue × folder | naive | indexed |
  |---|---|---|
  | 100 × 100 | 1,446 | 1,026 (1.4×) |
  | 1000 × 1000 | 129,763 | 2,988 (43×) |
  | 2000 × 1 | 91 | 91 (scan path) |

- Cross-validated against the old implementation on 200 randomized pools.
- Files: `lib/provider/audio_player/state.dart`, test `player_membership_test.dart`.
- **Rejected after measuring:** `directorySize` single-pass (cost is the 2000
  stat syscalls, not the intermediate list — 68/45 ms vs 70/48 ms),
  `presentation_list.dart` per-tile `selectedTracks.any(...)` (only runs over
  ~15 visible tiles), and `isDownloaded` in `player_actions.dart` (real O(n) but
  the right fix was deduping its name+album+artist match with
  `track_options_provider`, a refactor — see `.ai/TODO.md`).
- **That refactor landed 2026-09-23:** both `player_actions.dart` and
  `track_options_provider` now read this track's `track_download_table` row
  through `downloadStateOfProvider`, so the per-active-track O(local library) scan
  (~1.5–2 ms at 5,000 files) is gone and the cost of the answer is one indexed
  lookup by primary key. It also stopped being only a performance question: name
  matching reported a renamed or re-tagged file as not downloaded.
- **Related defect, FIXED 2026-09-21:** `AudioPlayerState.containsTracks` shadowed
  the field with its parameter and called `listContainsTracks(tracks, tracks)`, so
  it returned `needles.isNotEmpty` and ignored the queue. That made folder/playlist
  Play, Shuffle play and Add to queue no-ops at the four call sites. The parameter
  is now `needles`, so the shadowing cannot come back silently; the indexed
  predicate above is what the method calls.

### Remote manifest resolution (C4, FIXED — implemented + bounded)
- **Structural finding (source-verified):** on a `source_match` cache **hit**,
  `SourcedTrack.fetchFromTrack` still calls `audioSource.audioSource.streams(item)`
  (`sourced_track.dart:170`), i.e. the stream manifest is re-resolved on every
  play even though the match identity was cached.
- **Measured cost** (the desktop engine is a subprocess; timed directly with the
  app's own binary `~/.local/share/oss.krtirtho.spotube/NewPipeCLI --streams <id>`):

  | invocation | wall |
  |---|---|
  | `--help` (process floor) | 2–3 ms |
  | `--streams <unresolvable id>` (error path) | 218–382 ms |
  | `--streams <real video>` ×4 | **1,456–1,806 ms** |

  So a resolution is ~1.2–1.5 s of YouTube extraction round trip, not process
  startup. This is the single largest per-event latency measured in this roadmap.
- **Status update (2026-09-27):** the manifest cache **is now built** —
  `lib/services/sourced_track/manifest_cache.dart`, an LRU-32 keyed
  `trackId|sourceSlug|matchId` with strict-expiry lookup, wired into the
  `fetchFromTrack` cache-hit path (`sourced_track.dart:315–336`), pinned by
  `test/manifest_cache_test.dart`. The original C4 risk was avoided by
  construction: manifests with unknown expiry (missing/malformed/non-positive
  `expire`, poisoned via `manifestMinExpireSeconds`, `stream_url_expiry.dart:41–51`)
  are never stored, and failures never populate the cache — so no known-expired
  URL can ever be served. The mitigation notes below (prewarm + bounded
  retention) still cover the dominant path; the cache covers the repeat play
  outside the prewarm window. The earlier "not built / cannot be validated"
  entry is superseded: an `expire`-bearing fixture now exists in the test
  suite, which was the blocking unknown.
- **Why the dominant path was already mitigated:**
  1. `subscribeToPosition` pre-resolves
     the **next** track's `sourcedTrackProvider` at 80 % of the current track
     (`audio_player_streams.dart:187-237`, PR 5), and `sourcedTrackProvider` is an
     autoDispose family with bounded retention covering current + next. Sequential
     playback therefore never waits on a manifest. `activeTrackSourcesProvider` and
     `queryingTrackInfoProvider` watch the **same** family entry, so there is one
     resolution per track, not two.
  2. The remaining exposure was a repeat play of a track outside that window, plus
     the first track of a fresh queue — now covered by the LRU-32 cache.
  3. The TTL policy risk (an unexercisable cache in front of the 403-refresh-loop
     and tv-client fallback) was avoided by the strict-expiry rule above.
- **Separate observation worth its own investigation:** manifests fetched on this
  machine carry no stream URLs at all while the metadata API is returning 429s —
  consistent with upstream bot-gating rather than a Spotube defect, and **not
  verified** either way. The currently playing queue is local files, which need no
  sourcing, so remote playback on this host is not currently evidenced.

### Local-metadata rescan (C9, MEASURED — not a bottleneck, not implemented)
- **Hypothesis:** every `localTracksProvider` build re-reads tags for every file
  through the metadata_god bridge, so a persistent `path + mtime + size` cache
  would pay for itself.
- **Measured** (real bridge, `ExternalLibrary.open` on the built
  `libmetadata_god.so`, waves of 32 — the provider's own concurrency; fixture
  files carry a 36 kB embedded cover, like the real library):

  | library | walk | cold scan (art extracted) | warm scan (what a rescan costs) | cached path simulated |
  |---|---|---|---|---|
  | 516 files (real `~/Music/Spotube`, btrfs/NVMe) | 1 ms | 98 ms | **38 ms** | 17 ms |
  | 2,000 files (tmpfs) | 11 ms | 431 ms | **152 ms** | 67 ms |
  | 8,000 files (tmpfs) | 15 ms | 1,282 ms | **510 ms** | 234 ms |

  Object construction is 1–13 ms and the metadata read is **99 µs/file** on real
  files (47 µs on tag-only files).
- **Why it was rejected:**
  1. The rescan runs **once per process** — `localTracksProvider` is a keepAlive
     `FutureProvider` — plus on explicit user refresh and after deleting a local
     track. It is not on the track-start path.
  2. It does not block frames: the bridge calls are async and `collectInWaves`
     yields between waves, so the cost is library *appearance* latency, not jank.
  3. The best case is only ~2.2× and the cache cannot go below the filesystem
     floor — the simulated cached path still spent 234 ms of its own on 8,000
     `stat()` + 8,000 `File.exists()` calls, which any correct invalidation
     scheme must keep (mtime/size check, and re-extraction when the OS wipes the
     temp art dir).
  4. It is the only roadmap item needing a **schema migration**, so it carries
     the highest risk per unit of measured benefit.
- **New evidence that would justify revisiting:** a profile showing the scan
  attributed to user-visible latency (e.g. the library page blank for seconds on
  a slow/spinning disk), or a per-download invalidation making the scan frequent.
- **What the measurement did surface (different item):** extracted artwork is
  written to `<temp>/spotube/` and **never deleted** — this machine holds 1,093
  art files / 39 MB for a 516-track library, and `/tmp` is tmpfs here, so the
  orphans cost RAM. That belongs with PR 9's retention policy (C13), not with C9.

### Local-library invalidation bursts (C5, MEASURED — already coalesced, no code changed)
- **Hypothesis:** deleting N local tracks triggered N full directory walks
  ("1 full rescan per file"), so the invalidation call sites needed coalescing.
- **Measured** with a counting provider body in
  `test/local_tracks_rescan_coalescing_test.dart` (Riverpod 2.6.1 semantics, the
  walk itself irrelevant to the question):

  | scenario | invalidations | walks |
  |---|---|---|
  | initial read | 0 | 1 |
  | 3 invalidations in one event-loop turn | 3 | **1** |
  | 3 user actions, one per turn | 3 | 3 |

- **Why nothing was implemented:** the burst case is already coalesced by
  Riverpod itself — `invalidate` marks the element dirty and the pending build
  flushes once per turn, so a coalescer in app code would only duplicate it. The
  sequential case is one walk per deliberate user action, which is the intended
  behavior, and a warm walk is 38 ms at 516 files (see C9 above). There is also
  no bulk-delete UI for local files: `TrackOptionValue.delete` handles one track,
  and the other call sites are pull-to-refresh, a refresh button, and
  Android/iOS-only permission grants.
- **What the tests now guard:** that the one-per-turn coalescing keeps holding
  (a regression there would silently make every delete 2–3 walks), and that a
  single delete does not invalidate twice.
- Throwaway benchmark files were deleted after the numbers were recorded; the
  fixture library is not kept.

### Downloaded-file lookup per request (FIXED, modest win)
- **Measured (Linux tmpfs, dev build, 5,000 files in the download folder,
  matching name last):** one full `Directory.list()` walk ≈ 0.24 ms; 100 walks
  = 24 ms. `DownloadedFileIndex` served the same 100 lookups in 28 ms, of which
  one was the index build. Directory mtime is reported in **milliseconds**, so
  the index re-lists on every miss (never worse than before) and verifies hits
  with a single stat.
- **Conclusion:** the per-request walk was real but small on local storage; the
  fix removes it for downloaded tracks (HEAD + one range GET per seek all hit the
  index) and should matter more on slow/removable filesystems, which were **not
  measured** here. Do not cite this as a large win.
- Files: `lib/provider/server/routes/playback.dart`,
  `test/download_first_playback_test.dart`.

### Metadata plugin bootstrap at startup (FIXED, audit PR 10)
- **Finding:** `metadataPluginsProvider.build()` re-inflated both bundled
  `.smplug` archives on *every* launch (3 + 3 files, 145 KB + 27 KB) before the
  plugin list — and therefore the first frame — could resolve; the root widget
  also held `ref.listen`s on both plugin update checkers, which started two
  release-feed requests (each able to pull a plugin VM online) pre-frame.
- **Fix:** read only `plugin.json` out of the archive and skip the writes when
  the same version is registered and its `plugin.out` is present with the
  declared size (a crashed extraction leaves a short file, and that still
  re-extracts); move both update checks behind a 5 s idle timer in
  `useGlobalSubscriptions`, which Settings > Plugins also triggers on demand.
- **After:** bundled-plugin load in the plugin path went from ~20 ms to ~1.5 ms
  (JIT, warm cache; `extract` 15.5 + 1.3 ms vs `skip-check` 1.1 + 0.5 ms), and
  the release requests are off the launch path.
- Files: `lib/provider/metadata_plugin/metadata_plugin_provider.dart`,
  `lib/modules/root/use_global_subscriptions.dart`, `lib/main.dart`,
  `test/plugin_extraction_test.dart`.

### Download tasks / retention
- Download manager has bounded per-task retention. Sourced-track cache bounded
  via `sourcedTrackRetentionProvider` (keeps current + next tracks' manifests).

### Provider retention
- `trackOptionsStateProvider` / `trackOptionActionsProvider` are
  `autoDispose.family`. They used to be kept alive per track object, so every
  row the user ever opened a menu on kept resubscribing to the player, the
  download list and the blacklist and re-scanned the queue on each change. The
  two whole-list watches are now `select`s (the active track's download task,
  and a bool from `BlackListNotifier.matches`). Measured in the JIT VM with 50
  mounted rows × 20 download-progress ticks over a 500-track queue:
  **~25 ms → ~12 ms**, and unmounted rows cost nothing afterwards.
  Dart 3 records already compare by value, so the old code did not over-notify;
  the win is skipped rebuilds and released entries.
- `sourcedTrackProvider` is autoDispose with bounded retention; `syncedLyricsProvider`
  is intentionally **not** autoDispose (keyed per track).
- `historyTopTracksProvider` / `historyTopAlbumsProvider` / `historyTopPlaylistsProvider`
  are autoDispose (Stats-page only) — their `watch()` recomputation is the reason.
  `recentlyPlayedItems` stays keepAlive (Home section is always mounted) and is
  `LIMIT 10` bounded.

### mimalloc
- **No leak conclusion established.** A large virtual mapping may be allocator
  reservation rather than live retained app memory. Do **not** classify RSS/virtual
  growth as a leak without RSS/PSS/heap evidence. (Only note this if you observe
  a large mapping again; re-measure before concluding.)

### Android frame-pipeline pass (FIXED, PR 11)
- **Report:** "the android app is not working as smoothly as it should" —
  scrolling jank, player-sheet stutter, stutter during playback, general
  heaviness. **Frame time is not measured here**: this host has no Android
  device, AVD or adb, so every number below is a *count* of work removed
  (channel calls, provider notifications, mounted controllers), not a
  before/after in milliseconds. Treat the GPU claims as mechanism-verified.
- **Glance widget (Android-only):** `_saveWidgetData` + `HomeWidget.updateWidget`
  ran per playing/duration event **and per 1 Hz position tick** for the whole
  session, in the foreground included. `ForegroundCoalescer` folds them:
  **60 requests → 0 pushes while foreground, 1 push on leaving foreground**,
  0 pushes on a background transition with nothing pending.
  `test/glance_push_coalescing_test.dart`.
- **Nav bar during a sheet drag:** 30 provider notifications per full drag
  (raw `navigationPanelHeight`) → **1** (`navigationPanelCoversBar`); closing
  the sheet is also 1. The raw count is asserted in the same test as the
  negative control, so a future `select` removal cannot silently pass.
  `test/navigation_bar_panel_lift_test.dart`.
- **Blacklist membership per row:** 5,000 entries × 200 mounted rows × 5
  rebuilds, old table scan vs the shared id set: **~62.5 ms → ~1.7 ms (35-38x)**
  in the JIT VM, gate at >5x. The set itself builds **once per table change no
  matter how many rows ask** (200 watchers + 1 probe).
  `test/blacklist_row_membership_test.dart`.
- **Per-card animations:** a `PlaybuttonCard` mounted 4 `AnimationController`s
  (2 `AnimatedScale` + 2 `AnimatedOpacity`) whose target was constant on touch.
  Now **0 on a touch host, 4 on a pointer host** (asserted both ways, including
  the scale/opacity values the pointer branch must keep).
  `test/playbutton_card_hover_reveal_test.dart`.
- **Backdrop blur while scrolling:** shadcn emits a real `BackdropFilter` for
  any `surfaceBlur > 0`, so the nav bar and collapsed player re-blurred every
  frame of a scroll. `chromeBlurFrozen` now suppresses it at rest boundaries:
  **30 frames of a one-finger drag → 1 notification up, 1 down after the fling
  settles and its 400 ms countdown**, and **0** on a host that is not a phone.
  There is no counter to desync, so a scrollable destroyed mid-fling cannot
  leave the chrome unblurred permanently (asserted).
  `test/scroll_blur_freeze_test.dart`.
- **Also:** `test/player_membership_test.dart`'s 100×100 case measured
  1.6–2.4x against a 2x gate on an *idle* machine — the small case now only
  asserts "never slower"; the 2x budget lives on 1000×1000, measured 17x.

### Metadata request ceilings (FIXED, 2026-09-23 — one *bound*, not a speedup)

- Nothing bounded a Spotify metadata request. `hetu_std`'s `HttpClient` gives Dio
  a null `BaseOptions` when constructed option-less and the Spotify plugin
  constructs both of its clients that way, so connect/receive/send timeouts are
  all infinite; metadata bypasses `globalDio`, so its 15s/30s/15s never applied.
- Now `runGated` caps each attempt at `metadataRequestBudget` (15 s).
- **Not measured, and deliberately not claimed:** no healthy-session number. This
  records a worst case, not an improvement — the only before/after evidence is
  that a request which never completes went from hanging indefinitely (its own
  test timed out at the framework's 30 s ceiling) to failing at the budget.
- What it does not fix: the ceiling is host-side and **abandons rather than
  cancels** — the in-VM Dio call keeps running. Non-gated paths (`scrobble`,
  `theme`, `core.checkUpdate`, `user.me`) remain uncapped. Engine and source
  calls are separately bounded, see the next entry.

### Source-resolution ceilings and the fallback memo (FIXED, 2026-09-23)

- Same shape as above: **a bound on the worst case, plus one real removal of
  duplicated work.** No healthy-session timing was taken, so time-to-first-audio
  is claimed *unchanged* only because the ceilings must never fire on a healthy
  network (`source.resolve.timeout == 0` in a profile counter dump is the check
  that this held) — not because it was measured before and after.
- `sourceCandidateBudget` 20 s wraps each `resolveFirstAvailable` step
  (~10× the 1,456–1,806 ms healthy manifest measured earlier). A
  `TimeoutException` is recorded as an *engine failure*, never a miss, so a
  stalled backend cannot be cached as "this track does not exist".
- `engineCallBudget` 15 s covers every engine crossing:
  `newpipe|yt_dlp.{searchVideos,getStreamManifest,getVideo}` via
  `withinEngineCallBudget`, and `_runMethod` in `youtube_explode_engine.dart`,
  which additionally drops its `_pendingCalls` entry and closes the reply port
  so a timed-out caller cannot strand either.
- `ServerPlaybackRoutes.fallbackUrlsFor` memoizes `playbackFallbackUrls` per
  `track.id|primaryUrl` (5 s, 16 entries): the HEAD preflight and the stream GET
  used to each walk the full cascade for the same dead URL. Counted in
  `test/playback_fallback_memo_test.dart` — 3 searches per track start instead
  of 6. A re-signed URL misses the memo by design (it is part of the key).
- `fallbackCascadeBudget` 45 s returns a *partial* list rather than hanging the
  walk; mpv gives up on the proxy long before that.
- Still true: `.timeout()` abandons the Dart future, and the orphaned
  `NewPipeCLI` / `yt-dlp` process runs to its own completion — `Process.run`
  exposes no handle, so killing it needs a fork or an upstream
  `Process.start`. The cascade is bounded, not cancelled.

### Saved lists: stale-while-revalidate (FIXED, 2026-09-23)

- `buildSavedList` awaited the network inside `build()` and only consulted
  `library_snapshot_table` in the `catch`, so a warm library paid the whole
  retry chain (2 × 30 s cooldown, now also 15 s per attempt) before showing
  rows it already had on disk.
- Now: read the snapshot first; if it exists it *is* the build result and the
  revalidation runs behind it, patching `state` when it lands. Cold snapshots
  still block (there is nothing to show) and `RateLimitedUntilException` still
  fast-fails — it just fails in the background now.
- Two deliberate consequences, both tested: a failed revalidation is logged and
  otherwise invisible (a stale list beats an `ErrorBox` over data we have), and
  a page someone else moved first is left alone — the patch is skipped unless
  `state.value` is still the exact page this build served, so an optimistic
  favorite can't be rolled back by a fetch that started before it.
- Evidence: `test/library_snapshot_test.dart` "the snapshot answers while the
  probe is still open" holds a request open and asserts the rows arrive anyway;
  against the old ordering it waits the full 15 s and ends on the stale list —
  the spinner, reproduced.

### Latency instrumentation (ADDED, 2026-09-23 — measures, changes nothing)

- Before this, nothing in the app measured fetch latency, so "sometimes slow"
  could only be inferred from things that *throw* — which is exactly how the
  2026-09-23 round had to be diagnosed.
- Counters now covering the network: `metadata.request` (+`.timeout`) per gated
  plugin read, `source.resolve` (+`.timeout`) per track resolution,
  `engine.<call>` (+`.timeout`) per engine invocation,
  `playback.fallbackCascade` (+`.budget`) and `playback.fallbackUrlsReused`,
  and `dio.<host>` from a `_TimingInterceptor` on `globalDio`.
- Keyed by **host**, never path: these URLs carry signed tokens and per-video
  ids, so a path key would grow the map without bound and leak into a log dump.
- `kPerfCountersEnabled = !kReleaseMode`, so a release session still cannot dump
  them — read a profile/debug build with `SPOTUBE_PERF_COUNTERS=00:00:10`.
- **No baseline recorded yet**, deliberately: every number in this file is a
  measurement, and these have only run under test. The first thing to establish
  is what a *healthy* fetch costs, since the 2026-09-23 ceilings are bounds whose
  normal state is never firing.

## Measurement rules

- Release builds should be preferred for final performance measurements.
- RSS is not equivalent to live Dart objects; consider PSS when appropriate.
- Allocator reservations must not automatically be treated as leaks.
- Debug builds should not be the sole basis for memory conclusions.
- Performance claims need before/after measurements.
- Profile before major rewrites.
## Roadmap PR 1 (2026-09-26) — structural reductions, not yet benchmarked

- R-10: one fewer `track_download` INSERT..ON CONFLICT per download task
  (proven structurally: interceptor counts 1 `downloading` write with the fix,
  and the removed call was an unconditional second one). Wall-clock effect on
  a download: RUNTIME VERIFICATION REQUIRED.
- R-07: three per-proxy-request log paths no longer allocate/interpolate in
  release (the response-headers dump interpolates a full header map per GET).
  Hot-path effect during streaming: RUNTIME VERIFICATION REQUIRED.
- R-19/R-06/R-20/R-15d: correctness, battery and cleanliness changes; no
  performance claim is made for them.

## Roadmap PR 5 (2026-09-26) — startup deferral, measured

Timeline harness: `SPOTUBE_STARTUP_LOG=<path>` in a profile build (a run cut
short by a signal loses buffered stdout, hence the flushing file sink). Every
number below is process-start → phase, Linux desktop, warm start.

| phase | before PR 5 | R-01 (unawait WMTools) | R-02 (gate in build) |
| --- | --- | --- | --- |
| pre-runApp | 70, 76 | 42, 43 | 42–48 |
| firstFrame | 76, 80 | 46, 48 | 46–54 |
| app visible (splashReady) | 189, 209 | 103, 103 | 48–55 |
| deferred services complete | 286, 366 | 350–420 | 335–397 |

- R-01 `WindowManagerTools.initialize` is fire-and-forget (`unawaited`): it was
  holding up the pre-`runApp` path for its own 27–53ms while nothing before the
  first frame needs a window method channel. `pre-runApp` 70–76ms → 42–48ms.
- R-02 the splash gate is evaluated in `build` instead of on a 50ms poll. Both
  theme providers are watched, so the rebuild that carries a theme re-runs the
  predicate in that same frame; the timer now only fires the cap. `splashReady`
  103ms → ~50ms, i.e. the app became visible one poll interval earlier on every
  start. The cache-only path is what opens it: `cachedThemeDefinitionProvider`
  needs nothing but SharedPreferences, so gating the warm-up listeners behind it
  cannot deadlock theme resolution on the plugin stack.
- R-02 (second commit) the eight keep-alive `ref.listen` calls became
  `listenManual` subscriptions in a post-frame effect behind the same gate.
  Measured delta: none (~0ms, inside run-to-run noise) — the roadmap's estimate
  for this half was wrong. Kept because it removes provider construction from
  the build that produces the first themed frame, which is where the cold-start
  cost lives, and because a warm-up that never ran is a smaller failure surface.
  Verified live: playback proxy still binds, hetu plugin VMs still load.
- R-03 **not attempted**: its target is `readLibrarySnapshot(ref)` in
  `lib/modules/home/home_search_bar.dart`, an untracked work-in-progress file of
  the user's search redesign. Editing or committing it would trample that work.
- R-04 **measured and rejected**: overlapping the whole deferred batch (`Future.wait`
  of all eight `guardedStartupInit` steps) left the total where it was — 363ms
  mean vs 368ms sequential — because `NewPipeExtractor.init` alone grew from
  ~200ms to ~315ms under the contention and everything else finishes inside its
  window anyway. Awaiting `NewPipeExtractor` first and overlapping only the rest
  gave 335–397ms, i.e. a ~10–30ms shift on a phase that is already after first
  paint and not on any interaction path. Code reverted; do not re-litigate
  without new evidence (e.g. a machine where the tail steps are much slower).

## Second-pass roadmap PR 7 (2026-09-27) — history playlist aggregation

`test/history_scaling_test.dart -r expanded`, one history write with the Stats
watcher live, 5002 rows (in-memory DB):

| provider | writeToSettle | itemsAfter | rowParses |
| --- | --- | --- | --- |
| topTracks | 23ms | 1667 | 3334 |
| topAlbums | 29ms | 820 | 0 |
| topPlaylists | **3ms** | 834 | 0 |

Before the SQL aggregation, the playlists watch path materialized and
JSON-decoded every playlist-history row per write (drift `MapTypeConverter` +
`SpotubeSimplePlaylistObject.fromJson`), i.e. cost linear in history size; it
is now flat and the cheapest of the three. Equivalence with the legacy Dart
grouping is pinned for all six durations by
`test/history_playlist_grouping_test.dart`. D-03 (`recent.dart` window query)
was left alone: no measured cost to remove, and a GROUP BY rewrite is wrong on
`created_at` ties — see `.ai/AUDIT_STATE.md`.

## Wallpaper backdrop latency (2026-09-30) — debounce removed for the image

`test/shell_wallpaper_signal_test.dart`, real inotify against a temp state dir,
latency measured from the first write of a Caelestia apply burst:

| watch | form | emit latency | emissions per burst |
| --- | --- | --- | --- |
| `watchBackground` (before) | `_coalesceEvents`, 300ms trailing | **302ms** | 1 |
| `watchBackground` (after) | `_distinctPathSignal`, resolve-per-event | **<300ms**, the `current` create itself | 1 |
| `watchTheme` | unchanged | 300ms trailing | 1 |

Caelestia's apply writes `path.txt` → unlink `current` → symlink `current` →
thumbnail link inside ~1ms (`15:06:05.8707/.8711` observed on the real state
dir), so four raw events carry exactly one change of the resolved path.
Collapsing them by *equality* rather than by *time* keeps the single emission
and drops the fixed tax; the palette watch keeps its debounce because a theme
recompute is not self-distinguishing and rebuilds the tree. A null from
`getBackgroundPath()` is the one case still time-gated (`_removalGrace`),
because the unlink/symlink hole is indistinguishable from a real removal
instant-by-instant — an incoming path cancels the pending grace timer.

## No-guesswork audit 2026-10-05 (correctness bounds, not speedups)

| Check | Value | Source | Date | Notes |
|---|---|---|---|---|
| `source_match` lookup @933 rows | 0.04 ms/lookup (100 in 3.5 ms) | Live read-only DB query | 2026-10-05 | Confirms 0.4 ms @20k prior; no index migration |
| Queue 600-track load (unchanged path) | 10 ms / 616 KB, 1 write | `queue_persistence_test.dart` | 2026-10-05 | Corrupt-guard adds no cost to healthy path |
| Queue 50/600/2000 index-change | 0/0/1 ms, 0 writes | `queue_persistence_test.dart` | 2026-10-05 | Regression green after `fromSql` guard |
| New counter `playback.headProbeFailure` | debug-only | `playback.dart:551` | 2026-10-05 | Observation only, gates no behavior |
| Download resolve ceiling | 20 s per `resolve`/`resolveMatch` | `sourceCandidateBudget` | 2026-10-05 | Bounds worst case; healthy manifests ~1.5 s so never fires normally |
| Glance Dio ceiling | 5 s connect/receive/send | `glance.dart:18-24` | 2026-10-05 | Was unbounded; bounds worst case only |

## Android every-start launch 2026-10-05 (structural, no device numbers)

No on-device timing on this host (no adb/emulator/device) — nothing below
is claimed as a millisecond win. What changed is *where* work happens:

| Change | Effect by construction | Files |
|---|---|---|
| NewPipe init eager → lazy single-flight | Every start stops paying `NewPipe.init(DownloaderImpl.init(OkHttpClient()))`; first engine call pays it inside an already network-bound call | `newpipe_engine.dart`, `main.dart` (eager block + now-unused import removed) |
| Startup phases in release log file | `[startup] main/pre-runApp/firstFrame/splashReady/deferred…` + per-step `step <name>: Xms` now appended to `.spotube_logs` in release (was debug/profile-only); ~15 short lines/start vs 5 MB rotation | `logger.dart` (`logStartupLine`), `main.dart` (`_startupLog`, `guardedStartupInit`) |

Attribution loop for the reporter: launch the release app twice, open
Settings > Logs, share the `[startup]` lines. The slowest phase/step then
gets a targeted fix with a before/after number — no further launch change
without one.

## Build-size pass 2026-10-06 (measured, Linux; Android config-only)

Baselines recorded on this machine (release builds, current tree):

| Metric | Value |
|---|---|
| Linux release bundle | 98,811,332 B (libflutter 41M, libapp 18M) |
| Linux `data/flutter_assets` heavies | NewPipeCLI 11M, shadcn 6.1M, fluentui 4.4M, country_flags 3.3M, simple_icons 1.3M; fonts 1.6M |
| Android APKs (Oct 5/6 artifacts) | universal 137M, arm64 64M, armeabi 61M, x86_64 66M |
| Startup (release, `[startup]` log) | splashReady ~59ms, deferred complete ~196-202ms (WindowManagerTools 96-143ms fire-and-forget, YtDlp 33-60ms, MetadataGod 4-6ms, Vpn.probe 21-41ms) |
| RSS @26s idle (release) | 565 MB (RSS 565,268 KB) |

Changes (behavior-preserving only; no Dart touched):

| Change | Measured | Files |
|---|---|---|
| Linux `--obfuscate --split-debug-info` | bundle 98.8M → 95.4M (-3.4M), libapp.so 18M → 15M (-17%); symbols to `build/app/outputs/symbols` (7.6M, not shipped) | `scripts/install-local.sh:69` |
| Android R8 + resource shrink wired to dormant rules | config only — no licensed Android toolchain on this host (no sdkmanager, license unknown), so no APK built here; CI must verify boot + playback + Glance | `android/app/build.gradle` release block, `proguard-rules.pro` (pre-existing keeps) |
| Makefile `apk` collects per-ABI outputs | was stale path (`apk/release/app-release.apk`) + universal-only; now globs `flutter-apk/app-*-release.apk` → `build/Spotube-android-<abi>.apk` | `Makefile` |

Investigated, no change (with reason):

| Idea | Why not |
|---|---|
| `uses-material-design: false` | `Icons.` used in 43 places (`spotube_icons.dart` + 5 call sites); removal is a visual-behavior change. Release already tree-shakes icons by default. |
| Strip `integration_test` from release registrant | disproven: no such entry in current `GeneratedPluginRegistrant.java`; registrant regenerates at build time anyway. |
| Defer `MediaKit.ensureInitialized()` | re-confirmed keep: queue-restore builds on first frame and can reach the backend (`main.dart:306-317` comment); PR9 verdict stands without new evidence. |
| Orphan artwork sweep | already landed in tree: `pruneOrphanedArt` + keep-set + full-scan/cancel guards (`local_tracks_provider.dart:93-132,219-293`), pinned by `test/local_artwork_test.dart` (11 green, re-run 2026-10-06). |
| Music-cache LRU quota | deferred: evicting cached tracks changes offline availability = behavior change; existing sweeps already remove staging/mirror orphans (`sweepStaleMusicCacheMirrors`, startup ~32ms). Needs sign-off. |

## Android lyrics + frost pass (2026-10-21/22)

Every number below is either a debug-VM widget-test/host measurement (repeatable,
single-threaded) or an AVD run labelled as such. **An AVD is not a phone**: report
deltas, never absolutes.

### Host-side, deterministic

| Measurement | Before | After |
|---|---|---|
| `LyricsPage` first frame, 120-line payload (`test/lyrics_open_cost_test.dart`, debug VM) | 78ms | 76-77ms |
| same, 300-line payload | 87ms | 65-74ms |
| same, 40-line payload | 136ms | 120-133ms |
| plain-lyrics join, per call | n=40 45µs, n=120 43µs, n=300 51µs, n=800 100µs | 17µs, 20µs, 42µs, 27µs |
| `ShimmerLyrics` widest row at phone width | 471px `Bone.text` in a 480px page → `RenderFlex overflowed by 417 pixels` on every row | 355px widest, 34 rows for the 480x1067 viewport |
| lyrics header row | `Row(Tabs, Spacer, Text)` overflowed by 33px at 480px | fits; attribution ellipsized |

Read these honestly:

- The join is a real O(n²)→O(n) removal (`elementAtOrNull(i+1)` walks `i+1`
  elements per line) and byte-identical output at every size, but it costs
  **microseconds** — it is not the 1-2s the user felt, and is not claimed as it.
- The first-frame timings move less than their own run-to-run spread. The
  instrument's job is to catch a future regression and to hold the `IndexedStack`
  disproof (`PlainLyrics=0 SelectableText=0 SyncedLyrics=1` at open), not to
  advertise a win.
- The two overflow rows are defects found by building the instrument, not by
  reading the code. They were visible on a phone-width page in a release build,
  where the overflow report itself is not printed.

### AVD (android-35 x86_64, `-gpu host`, release/stable, R8 on, 1080x2400@60Hz)

`scripts/android-bench`, local-library folder-list scroll, 12 swipes @650ms:

| Metric | baseline (3 rounds, build of 20:23) | after (1 round, build of 23:45) |
|---|---|---|
| cold start TotalTime | 515ms (480-1012) | 593ms |
| frames delivered / covered span | 583 / 12.68s | 585 / 12.75s |
| fps | 45.9 | 45.8 |
| interval p50 / p90 | 16.68 / 17.69ms | 16.65 / 17.69ms |
| interval p99 | 433.0ms (432.9-433.2) | 351.4ms |
| worst stall | 452.8ms (450-500) | 469.0ms |
| missed deadlines / janky >2 vsync | 16 / 1.20% | 14 / 1.54% |
| TOTAL PSS / native heap | 140,688 / 34,828 KB | 143,389 / 34,676 KB |
| cpu (% of one core) | 53.1 (53.1-57.0) | 57.9 |

Verdict: **no regression, and no improvement claimed.** The scene measured
contains none of the widgets this pass touched, so it is a guard rail. The p99
delta is the one number that beats the baseline's best round, and one round
cannot satisfy the acceptance rule (worst before-round must beat the best
after-round), so it is recorded and not banked.

Two environmental limits, both new evidence for the open repeatability item:

- `-gpu host` gfxstream died mid-drive twice this session with
  `glGenTextures/glBindTexture/… error null ctx`, killing the guest. A 5-round
  run is not reliably obtainable on this host; round 2 of this run was lost.
- The p99 ≈ 433ms / worst-stall ≈ 450ms shape is the per-swipe stall from the
  earlier Android pass and is still there. It is not the lyrics page and not the
  header.

### Not measurable here

The actual B2/C1 win is removing a full-screen σ10 `BackdropFilter` (lyrics) and
a header-sized one (playlist) from the Android scene. That cost is in the raster
thread, and the AVD cannot reach a surface with artwork in it without Spotify
credentials — Home, Search and Playlists all render the anonymous fallback, and a
scanned local file has no `album.images`, so its lyrics page has no backdrop at
all. No number is offered for it; the before/after is a screenshot pair on a
signed-in phone and sits in `.ai/TODO.md`.
