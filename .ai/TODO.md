# AI Work Queue

Distinguish verified problems from hypotheses. Only mark something as a problem
when proven with evidence.

## P0

- None.

## P1 (continued)

- [OPEN — hypothesis, not measured] The floating title bar still costs a
  backdrop-filter pass per frame on Android. `lib/components/titlebar/titlebar.dart`
  passes `surfaceBlur: 0` to shadcn's `AppBar`, but shadcn's `AppBar` builds a
  `BackdropFilter` **unconditionally** (`shadcn_flutter/lib/src/components/layout/scaffold.dart:739`),
  so a zero-sigma filter is still created and still samples the backdrop on
  every frame the content under the bar changes — exactly the class of cost the
  app already removed elsewhere ("in-app blur over a transparent region blurs
  nothing while still costing a filter per frame"). The fix is to stop using
  shadcn's `AppBar` when the blur is zero, which is a shared-component change
  and therefore not something to do blind. **Not yet proven on a device**: the
  AVD cannot show the artwork-backed lyrics page.

## P1

- [OPEN — needs a human, on two signed-in devices] A playlist created on one
  device did not show up on the other (same account), although Spotify showed
  it. The cause was a one-way "discarded" latch in the saved-list mixin: every
  re-read was thrown away at the moment it had the answer (see
  `.ai/AUDIT_STATE.md` — "A re-read that was thrown away every time"). The
  desktop now logs `[library] savedPlaylists: 61 rows, 7 new` at startup, so
  the path works there. **The phone pass is still owed**: install the APK
  (versionCode 6507, build 4507), sign in on both devices, create a playlist
  on one and check that it appears on the other without a restart — and the
  same for a liked track, a saved album and a followed artist. Settings →
  Logs shows the `[library]` lines that say what each re-read found.
- [DONE 2026-10-21] The fork's Spotify plugin is bundled, preinstalled and the
  default metadata source (seed order + a guarded one-time handover); anonymous
  Home now shows the login fallback instead of the plugin's raw credential
  exception. See `.ai/CHANGELOG.md`.
- [OPEN — needs a human, on a phone] Two Android fixes are code-complete and
  unit-tested but cannot be seen on the AVD, because it has no Spotify
  credentials and every artwork-bearing surface (playlist/album header, lyrics
  backdrop) is behind them:
  1. Remove a song from a playlist while signed in. The 0.2.10 plugin's
     `removeTracks` no longer asserts on an identifier it never receives, the
     host awaits and reports the call, and the local mirror row is deleted.
     Expect: the row disappears, stays gone after leaving and re-entering, and
     the downloaded file survives for other playlists.
  2. Open a playlist (or album) and look at the header **before touching
     anything**: the frost over the cover should be there immediately instead
     of arriving with the first scroll. Same for the lyrics page of a track
     that has artwork.
  See `.ai/AUDIT_STATE.md` — "Playlist header frost was flat until the first
  scroll" and the removal entry.
- [DONE 2026-10-22] Published. Plugin `0.2.10` is on `Adamyabhatt01/spotube-plugin-spotify`
  (`main` + tag + a release whose asset is named exactly `plugin.smplug`, which is what the
  in-app `checkUpdate` matches on — `core.ht:74`), its dependency's fix is on that repo's `main`,
  and the bundled archive plus the spotube-side fixes are committed and tagged `v5.1.2-fork.6`.
- [DONE 2026-10-22, from fork.6] `Spotube-<ver>-android-nightly-debug.apk` is no longer shipped.
  Its `applicationIdSuffix ".nightly"` made it a different app with its own empty data dir, which
  is what "the update forgot my settings" actually was (`.ai/AUDIT_STATE.md`). fork.6 publishes 4
  APKs, an `.aab`, the Linux bundle and checksums — nothing debug. Use
  `--debug --flavor stable` locally when a debuggable artifact is wanted.
- [DONE 2026-10-21] Stats-history consistency: one calendar window for every
  Stats family, legacy album/playlist rows dropped before grouping, the top
  playlists `fetch` crash removed, and the capped `fetchAll` walk finalized
  with `hasMore:false`. See `.ai/AUDIT_STATE.md`.
- [DONE 2026-10-20] Per-playlist automatic downloads and independent main
  playlist order (schema v28). Startup/connectivity sync, paged membership
  writes, deletion generations, global-file reuse, missing-file requeue,
  failed-task retry, and the `PlaylistOrderDialogButton`. See
  `.ai/AUDIT_STATE.md`; manual offline/auto-download eyeball pass still worth
  doing on a fresh install.
- [DONE 2026-09-23, committed on `opt/downloads-perf`] Desktop volume-control
  visibility mode (`VolumeControlMode` always/hover/hidden, schema v16 → v17,
  default **always**). Model, migration, notifier setter, `revealOnHover` slider,
  `BottomPlayerVolume` and the Settings → Desktop selector are all wired;
  `flutter analyze` clean and the footer-intrinsic + v16→v17 migration covered
  by tests. Shipped in the baseline commit. Still needs an eyeball pass on the
  three modes in the running bar; `/test/` is gitignored in this fork, so the
  footer test half is local-only.

- [OPEN] Playlist mirroring: two claims unit-proven but never seen in the app.
  (a) kill mid-download → the row reads **interrupted**, not completed, and a
  fresh download of it works; (b) airplane mode → a mirrored playlist renders its
  cached membership and order and the Playlists section still lists it. Now
  committed on `opt/downloads-perf` alongside the offline UX (mirror-only
  library, `isOnlineProvider`, skip-`AnonymousFallback`-when-mirror-exists).
  Still needs a manual offline pass on the fresh install.
- [CLOSED 2026-09-23] The v16 schema snapshot `drift_schemas/app_db/drift_schema_v16.json`
  and the three new table definitions, `lib/services/downloads/` and
  `lib/provider/playlist_download_provider.dart` are now on `opt/downloads-perf`
  as the `feat(downloads): baseline (pre-optimization)` commit. Migration tests
  for v16 and v17 remain local-only because `/test/` is gitignored in this fork.
- [OPEN] Downloads / playlists optimization plan (Phases 1–4) — deliberately
  **not** started. Phase 0 landed the baseline + harness on `opt/downloads-perf`;
  see AUDIT_STATE for the two premises in the pasted plan that turned out to be
  wrong (`playback_cache_mirror.dart` exists; the third membership index in
  Phase 1.5 is redundant). Do not run a Phase 1+ item until it is individually
  re-justified against a Phase 0 measurement.

- [DONE 2026-09-23] Metadata fetch latency, first three fixes: the
  `resolveFirstAvailable` production crash (an arity bug hidden behind a
  `Function` receiver), a 15 s `metadataRequestBudget` on every `runGated`
  attempt, and `sourceCandidateKey` surviving all three `SourcedTrack` rebuild
  paths. See `.ai/AUDIT_STATE.md`.
- [DONE 2026-09-23] Cascade ceilings + the fallback memo: `sourceCandidateBudget`
  20 s per candidate, `engineCallBudget` 15 s per engine call,
  `fallbackCascadeBudget` 45 s returning a partial list, and
  `ServerPlaybackRoutes.fallbackUrlsFor` (5 s / 16 entries) so HEAD and GET share
  one cascade per track start.
- [DONE 2026-09-23] Saved lists are stale-while-revalidate: a snapshot is the
  build result and the revalidation runs behind it instead of the page waiting
  on the network for its rows.
- [DONE 2026-09-23] Spotify 401/403 surfaces as `spotify_login_expired` in
  `ErrorBox` via the pure `isCredentialError`, deliberately not via the
  rate-limit gate (a quota backoff cannot fix credentials).
- [DONE 2026-09-23] `PerfCounters` wiring for fetch latency:
  `metadata.request[.timeout]`, `source.resolve[.timeout]`, `engine.*[.timeout]`,
  `playback.fallbackCascade[.budget]`, `playback.fallbackUrlsReused` and
  `dio.<host>` through a `_TimingInterceptor` on the previously
  interceptor-free `globalDio`.
- [OPEN] The plan's `metadata.invoke.<method>` per-plugin-method counter does not
  exist: all ~45 `endpoints/*.dart` `.invoke(` sites funnel through one gated
  choke point already, so the aggregate `metadata.request` replaced the
  `hetuInvoke` wrapper rather than duplicating it. Per-method timing needs a
  wrapper if a specific method ever has to be isolated.
- [DONE 2026-09-23, partly] First live run of the new release build: zero cast
  errors after the yt-dlp fix, and three real `source_match_table` rows written —
  so resolution runs end to end. It also caught that fix, which 604 green tests
  missed.
- [OPEN] The ceiling half of that check still needs a **profile** build, since
  `kPerfCountersEnabled = !kReleaseMode` means a release session cannot show
  counters at all: `SPOTUBE_PERF_COUNTERS=00:00:10` must report
  `source.resolve.timeout == 0` and no `engine.*.timeout`, proving the ceilings
  bound the worst case without ever firing on the normal path.
- [OPEN] Anything under `lib/services/youtube_engine/` has no unit seam
  (`YtDlp.instance` is a singleton), so it is not done until a release run has
  resolved a track — see the C-regression entry in `AUDIT_STATE.md`.
- [OPEN] Plugin-side timeouts: `src/segments/core.ht` and `auth.ht` in
  `spotube-plugin-spotify` build `HttpClient()` with no options, so Dio gets a
  null `BaseOptions` and every timeout is infinite. Adding `HttpBaseOptions`
  compiles clean but is not installed — confirmed from `plugins_table`, which
  still reads `0.2.3-inline` (do not infer otherwise from a runtime error naming
  the audit repo's `.ht` path: Hetu bakes source paths into shipped bytecode).
  It would replace a working plugin with unreleased 0.2.4 bytecode. This is also
  the only fix for paths `runGated` does not cover (`scrobble`, `theme`,
  `core.checkUpdate`, `user.me`), and for the fact that a host `.timeout()`
  abandons the await without cancelling the in-VM request.
- [USER ACTION] Recurring Spotify 401s on the Home browse path are the likeliest
  single cause of "everything sluggish at once" and need re-authentication in
  settings; no code change backs off a 401 on purpose.
- [DONE 2026-09-21] `AudioPlayerState.containsTracks` (PR 6 finding) shadowed the
  state field with its parameter and called `listContainsTracks(tracks, tracks)`,
  so it returned `needles.isNotEmpty` and never consulted the queue. Folder/playlist
  **Play**, **Shuffle play** and **Add to queue** took the "already playing" branch
  and did nothing. Fixed on an explicit go-ahead (parameter renamed to `needles`),
  covered by `test/player_membership_test.dart` and verified in the release build —
  see `.ai/AUDIT_STATE.md` Verification Status.
- [DONE 2026-09-21, in working tree] Extracted embedded artwork orphan pruning:
  `pruneOrphanedArt` (`lib/provider/local_tracks/local_tracks_provider.dart:104`)
  deletes art not in the scan's keep-set, run only after a fully-scanned,
  non-cancelled pass (`:287-293`), so unmounted/failed locations can't cause
  deletion of live covers. Covered by `test/local_artwork_test.dart`. Remaining
  follow-up is just committing it with the rest of the working tree.
- [DONE 2026-09-21, plugin side] Library Artists/Albums 429 root cause: the
  Hetu Spotify plugin discarded the complete `libraryV3` GQL payloads and
  re-hydrated each page via REST `GET /v1/albums|artists?ids=…` (2 requests
  per page; the REST half is what Spotify throttles). Fixed by converting
  `item["item"]["data"]` inline — same field maps as `browse.ht`/`search.ht`
  — so savedAlbums/savedArtists are now 1 GQL request/page, zero REST, like
  savedTracks/savedPlaylists already were. Commits: standalone
  `hetu_spotify_gql_client` `deb5ecc` (branch `inline-library-hydration`),
  audit repo `2ba9a63` (plugin 0.2.3-inline, submodule pointer bumped).
  Live-verified: both pages render, 0 logged 429s, snapshots persisted.
  [OPEN] Upstream PR to `sonic-liberation/hetu_spotify_gql_client` — the
  branch is ready; not pushed.
- [OPEN] Hetu plugin VMs are never disposed — `hetu_script` 0.4.2 exposes no
  dispose API, so `PluginVmCache` eviction only drops the reference. A removed
  or updated plugin's VM stays alive until GC takes the isolate.
  Evidence: `lib/provider/metadata_plugin/metadata_plugin_provider.dart`.
- [DONE 2026-10-19] The command line was dead on Linux. The runner
  returned `FALSE` from `local_command_line` while declaring
  `G_APPLICATION_HANDLES_COMMAND_LINE`, so GLib exited 1 and the Dart
  entrypoint never ran — `spotube --version` printed nothing. Fixed to
  match the Flutter template; the parser also ignores unknown switches
  now. See `.ai/AUDIT_STATE.md`.
- [DONE 2026-10-19] 227 MB of the reported "Dart heap" was transparent
  huge pages. The live heap is 27.5 MB; the rest was the kernel backing
  the VM's arena with 2 MB pages. `prctl(PR_SET_THP_DISABLE)` in the
  Linux runner and the Android equivalent: **PSS 548 → 315 MB, RSS 648 →
  415 MB**, smoothness unchanged within variance. See `.ai/MEMORY.md`.
- [DONE 2026-10-19] Local control channel, CLI control and an MCP
  server (`spotube --mcp`, official dart-lang `dart_mcp`). The channel is
  local-only and separate from the LAN-exposed connect server; the MCP
  server is a separate process, so it costs the running app no memory.
- [DONE 2026-10-19] Device-aware image budget. The three caches share
  one budget (a quarter of the platform's per-app heap limit, bounded
  8–64 MB), and the artwork memo is bounded by bytes rather than entry
  count.
- [DONE 2026-10-19] Playback crash on a null container preset. The
  playback routes force-unwrapped `SourcedTrack.qualityPreset` in four
  places; it is nullable by design (the plugin publishes presets
  asynchronously, and a persisted index can point past the end of a
  shrunken list), so the stream request threw and the player reported
  "Failed to open http://127.0.0.1:<port>/stream/<id>". Fixed via
  `SourcedTrack.container` (same fallback chain `url` uses) plus index
  clamping on restore. See `.ai/AUDIT_STATE.md`.
- [USER ACTION] The metadata plugin's Spotify token is rejected (346 ×
  401 in the release log, most recently 2026-10-19 18:53). Search and
  the Home browse sections return nothing until the account is
  re-authenticated via Settings → Metadata plugins. The host cannot fix
  this: `authentication_table` is empty and never read — auth is entirely
  plugin-side. The host now offers a Login button on the credential
  error. This is the likely cause of "cannot search song".
- [OPEN] The RAM plan's item 1.1 (drop the WebKit webview) is **dropped
  on measured evidence**: WebKit costs 7.4 MB at idle (1.3% of 571 MB
  RSS) and no WebKit helper process exists until a webview is opened.
  Removing it would also break plugin authentication, because the webview
  lives in the metadata plugin and is a declared `PluginApis.webview`
  capability. Full attribution in `.ai/MEMORY.md`.
- [OPEN] RAM items 1.2 (unify the image-retention budgets) and 1.5
  (bound `PluginVmCache`) are **deferred pending a heap histogram**. The
  measured footprint is 365 MB of Dart heap in one 5.1 GB reservation;
  the image-cache ceilings (64 MB + 24 MB) are ceilings, not usage, so
  neither item can be sized until the heap is attributed. A DevTools
  `--profile` heap histogram at idle is the missing measurement.
- [OPEN] `SpotubeMedia.serverPort` is a process-global that keeps the last bound
  port; toggling connect off/on reuses it instead of re-deriving, so the "random
  port" path is effectively once-per-process.
  Evidence: `lib/provider/server/server.dart`.
  Partially addressed 2026-10-20: queue restore now awaits the first bind, so a
  cold-start restart no longer builds `:0` URIs. A rebind that actually moves
  the port while a queue is loaded still leaves that queue stale.

## P2

- [DONE 2026-09-21] Working-tree backlog committed: 11 logical commits on
  `master` (chore tooling, bonsoir 6, drift v13, YouTube 403, lyrics registry,
  player/queue perf, history perf, artwork+plugins, server+downloads,
  remediation catch-all, i18n) at 351 tests green, analyze clean. Not pushed.
- [DONE 2026-10-24] Theme-plugin UI extension, phases 2-4 (phase 0-1 landed
  2026-09-21, see `.ai/CHANGELOG.md`): slots, overlay screens, `getUi()` /
  `onUiAction()`, flattened-node renderer, templates/bindings/conditionals,
  animations, assets/fonts, whitelisted actions and the `stage` dock are all
  wired. Obsidian ships and was checked at full width, 908×1038 and 700×1038.
  **Still host-owned:** `layout.responsive` and entry ordering
  (`navItems`/`libraryItems`, home/settings section lists, `titlebar`,
  `enforce`) are validated but not consumed; the host keeps its own breakpoints
  and user preferences. On Linux, `windowManager.setTitle` updates GTK's title
  but Hyprland still reports the initial `Spotube` title.
- [DONE 2026-09-23] `isDownloaded` in `player_actions.dart` no longer re-implements
  the name + album + artist match: both it and `track_options_provider` read one
  `track_download_table` row through `downloadStateOfProvider`, so the
  O(local library) scan with `artists.asString()` per file (~1.5–2 ms per
  active-track change at 5,000 files, measured in PR 6) is gone and a renamed or
  re-tagged file stops reading as "not downloaded". Deduped into one place, which
  is what the old note called the right fix.

## Investigations Needed

- [OPEN 2026-10-20] **yt-dlp on Android via a Termux bridge** — the only
  shippable way to get the yt-dlp engine working on a normal Android device
  (run yt-dlp inside Termux, talk to it over Termux's `RunCommandService`).
  Deliberately not implemented: it needs six independent assumptions to
  hold (Termux installed, the `RUN_COMMAND` permission granted by the user
  in Termux's settings, shared-storage access for the output file, the
  Android background-service restriction on `am startservice`, a yt-dlp
  inside Termux's PATH, and a Python inside Termux) and **none of them can
  be verified without a device in hand**. Revisit only with a device.
  Full reasoning and the four bundling blockers: `.ai/MEMORY.md`,
  "yt-dlp on Android".
- [OPEN] `ScrobblerNotifier` credential-diff gate (H-01) unit coverage. The
  documented blocker ("needs the encrypted keystore mocked") is only half of
  it — corrected 2026-09-27: the keystore is mockable on the test host
  (`SharedPreferences.setMockInitialValues` + `KVStoreService.initialize()`;
  Linux non-flatpak delegates to it). The real blocker is
  `LastFM.authenticateWithPasswordHash` — a static on scrobblenaut with no
  seam, making a live network call; without an upstream injection point any
  gate exercise either calls the real API (not hermetic, flaky) or never
  reaches it. Re-entry: a scrobblenaut seam (upstream change), or a
  host-side LastFM client override.
- [OPEN] Whether the write-only-if-empty guard in `SyncedLyricsNotifier` should
  let an upgraded (e.g. synchronized) result replace cached plain lyrics.
  Evidence: `lib/provider/lyrics/synced.dart` writes only when cache empty.
  Hypothesis: replaying a track may not refresh improved lyrics.
- [CLOSED 2026-09-27] The C4 re-entry regression test the docs said could not
  be written now exists: `test/manifest_cache_test.dart`
  "second serve of an unexpired match skips re-extraction" (an `expire`-bearing
  manifest through the `fetchFromTrack` cache-hit path proving `streams()` runs
  once) plus "unknown-expiry manifests keep re-extracting". The ManifestCache
  (LRU-32, strict expiry) is built, tested and bounded; the `.ai/PERFORMANCE.md`
  C4 entry was updated to "implemented + bounded" accordingly.

## Ideas — Not Yet Validated

- [HYPOTHESIS] A local lyrics synchronizer (plain → timed) would need an audio
  decode path; currently none exists (no PCM/FFT deps). Feasibility of
  ffmpeg-if-present decode is unverified.
- [HYPOTHESIS] Additional lyric providers (e.g. JioSaavn for Indian catalog)
  could improve coverage; not validated for reliability/licensing.
- [HYPOTHESIS] PSS vs RSS comparison on Linux could reveal whether any remaining
  "high" RSS is live heap or allocator reservation.