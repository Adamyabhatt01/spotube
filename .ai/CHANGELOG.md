# AI Change Log

AI-oriented changelog of architectural/performance changes. Not the app
changelog. Concise; only meaningful changes.

## 2026-10-23 — Theme contract v3 enforced, obsidian shipped, theme builds reproducible

- **The theme repo is now `themes/` in the app repo.** Source at
  `themes/themes/<id>/`, published archives at `themes/<id>/plugin.smplug`,
  goldens at `themes/conformance/`. CI is `.github/workflows/themes.yml`.
- **v3 is enforced, not drafted.** Flat node props are canonical; unknown
  props/bindings/actions/asset paths/icons fail the build. `ui.specVersion: 2`
  adds `animate` and `dock: stage`; pixel borders and tiled/scaled backgrounds
  are validated. `schemas/theme.v3.schema.json` is draft-07 and
  `test/schema_test.dart` validates every golden against it; `kitchen-sink`
  must carry every field.
- **Theme archives are byte-reproducible.** `lib/compile.dart` pins the Hetu
  timestamp to `1970-01-01 00:00:00`; CI rebuilds and checks sha256. (App
  plugin archives built by the old toolchain are unaffected.)
- **`themes/tools/preview.dart`** renders a payload and its assets to one
  standalone HTML preview (fonts/images inlined, both schemes, palette,
  components, screens, stage; `#mode=light&screen=...` states).
- **`obsidian`**: pixel-Minecraft theme, 39 roles/scheme, Silkscreen + VT323
  (OFL), 20 pixel icons, transparent obsidian tile, stage dock, record whose
  label turns with the track, now-playing and colophon screens. Artifact
  `themes/obsidian/plugin.smplug` (~95 kB); 20 strict tests.
- **`build.dart --theme` no longer erases the catalog.** The index merges a
  subset build into the existing entries; `build_test.dart` covers the index
  and the merge.
- **Host side so far:** the app reads v3 colour roles through
  `ThemeSemanticColors` (commit `bd31cb36`). Still open: `getUi()`
  endpoint/cache, the v3 UI model/renderer/action dispatcher, asset resolver +
  `FontLoader`, and the stage dock/animations. Until then a v3 theme still
  draws only its two colour schemes.

## 2026-10-23 — A disposed radio player no longer aborts the app

- **`media_kit` pin moved to `8ce5e0a4`** (one commit, +5 lines): disposing a
  `Player` now clears libmpv's wakeup callback before closing the FFI
  `NativeCallable`. On the old pin (`d310049`), stopping radio and starting
  music disposed the dedicated radio player, and libmpv's event thread could
  invoke the closed callback and abort the process in
  `DLRT_GetFfiCallbackMetadata`. The fix covers every player dispose.
- No app code changed; `pubspec.lock` resolves all media_kit packages to the
  new ref.

## 2026-10-22 — The radio plugins moved to their own repositories

- **The two radio directories are now standalone repositories**:
  `Adamyabhatt01/spotube-plugin-internet-radio-browser` and
  `Adamyabhatt01/spotube-plugin-internet-radio-somafm`. Each holds the Hetu
  source, the manifest, the build tooling, a CI workflow that rebuilds the
  archive on a tag, and a release with the `.smplug` asset.
- **The manifests moved to version 1.0.1 and the `repository` field now points
  at the plugin's own repository** instead of a subdirectory of the app. The
  version bump matters: the bundled seed only replaces an installed plugin
  when the version moves, so without it an install that already had 1.0.0
  would keep the old repository link forever.
- **Identity was left alone on purpose.** The `author` field stays `Spotube`:
  Spotube identifies a plugin by name *and* author, so changing it would give
  every existing install a second copy of the same directory.
- **The bundled archives are unchanged apart from the manifest.** The
  bytecode is byte-identical to the previous build (same compiler, same
  source) except for its embedded compile timestamp — the compiler is pinned
  to `hetu_script_dev_tools 0.1.0+2`, the release that carries
  `hetu_script 0.4.2+1`, the version the app's own VM runs. The current
  `hetu_script_dev_tools` release compiles with `hetu_script 0.6.x`, whose
  bytecode the app cannot load.
- **Radio plugins still do not participate in the update check.** The updater
  only asks the default metadata plugin and the default audio-source plugin,
  so a new release of a radio directory is noticed by reinstalling, not by
  the app offering an update.

## 2026-10-22 — Android lyrics opened a hidden tab and a full-size palette

- **Symptom**: opening the lyrics page on Android lagged and jittered, and the
  Radio page refetched itself every time it was opened.
- **The hidden Plain tab was laid out on every open.** Flutter's `IndexedStack`
  wraps each child in `Visibility(maintainSize: true)`, so the non-selected
  tab stays mounted *and laid out* — only painting is skipped. The Plain tab is
  one giant, non-lazy `SelectableText`, so opening the page laid out a
  **28,800-pixel-tall** text block for a 120-line lyric, for a tab the user
  may never open. The repo's own guard test said the tab was absent, but
  `find.byType` skips offstage elements, so it could not see it. Flutter has
  no "mounted but never laid out" primitive (`Offstage` lays its child out
  with the same constraints), so the tab now only enters the tree once it has
  been asked for, and stays there afterwards. First frame at n=300: ~112 ms →
  ~50 ms (host JIT).
- **The palette was quantised at full resolution, on the UI isolate.** The
  code claimed a "50px sample", but `PaletteGenerator.fromImageProvider`
  passes `size:` to the `ImageConfiguration`, and `MemoryImage` ignores it —
  the artwork was decoded at its native size and *every* pixel was walked.
  Measured quantizer cost: 50×50 → 2 ms, 300×300 → 19 ms, 640×640 → **81 ms**
  (host JIT; a phone is several times slower), on every artwork change while
  the lyrics page is open. The artwork is now downscaled by the decode itself
  (`ResizeImage`), and the palette reads the *smallest* rendition instead of
  pulling the full-size cover a second time.
- **The Radio page refetched five requests on every visit.** The station
  family and the tag/country lists were auto-disposed, and the Radio page is
  torn down whenever the user leaves the tab; worse, the plugin-state sync
  invalidated all three on *any* plugin emission (auth and progress included).
  The browse answers are now held for five minutes past their last listener
  (`ref.cacheFor`, the pattern every other single-item provider already
  uses), and the invalidation is scoped to a change in the set of radio
  directories.
- **The country filter was there but unreachable.** It sat at the end of the
  horizontally scrolling tag rail — after up to thirty tag chips, so off-screen
  on a phone — and it disappeared with the rail while a search was typed. It
  has a row of its own now, always on screen, with a searchable popup (the
  directory can return a hundred countries), and it rides along with a typed
  search term instead of being dropped by it.
- **The bookmarked stations had no home.** The heart already saved them
  (`radio_favorites_table`), but they were only reachable from the Radio
  page's own rail, with nowhere to review the list or drop one. They are now a
  library entry ("Stations") with their own page, and the Radio page's
  favorites rail links to it.
- **Tests**: `test/lyrics_open_cost_test.dart` (the false-negative guard is
  now a real one), `test/radio_stations_provider_test.dart` (a revisit makes
  zero directory calls), `test/radio_ui_test.dart` (country filter is on
  screen without scrolling), `test/sidebar_order_test.dart`.

## 2026-10-22 — The library never synced: the re-read was thrown away

- **Symptom**: a playlist created on one device never appeared on another,
  while the liked tracks did.
- **The root cause was a one-way latch.** `SavedListCacheMixin` marks a list
  "discarded" in `ref.onDispose`, so a re-read in flight when the list's
  build is replaced throws its result away. Riverpod fires a build's
  `onDispose` when that build is replaced — and the flag was never cleared
  for the build that replaced it, so after the second build the instance was
  "discarded" for the rest of its life and *every* later re-read was
  discarded at the exact moment it had the answer. The liked list escaped it
  only because its provider is auto-disposed and gets a fresh instance; the
  playlists, albums and artists providers keep theirs, so they kept the
  latch.
- **Three more defects on the same path**: the auth provider re-published
  its answer on every auth event (a token refresh included), rebuilding
  every saved list — and on a rejected token that looped
  (read → 401 → refresh → rebuild → read); the plugin answered "not signed
  in" until it had read its stored credentials, and the host published that
  lie and corrected it a moment later; and a rejected token was never
  refreshed, because the plugin only refreshes at the token's stated expiry
  while Spotify invalidates tokens before that.
- **Also fixed**: the playlist *create* no longer dies on a throttled
  read-back (plugin 0.2.11 — the read-back was the last step of the
  create, so a 429 reported a successful creation as a failure and the
  playlist never appeared); a create that reports a failure now looks for
  the playlist it actually made and adopts it; the library-repair write goes
  through the rate-limit gate; and the "your playlist did not reach the
  library" warning uses the root navigator's context (the dialog's own
  `ToastLayer` dies with the dialog, so the warning was silently dropped).
- **Every re-read is logged** (`[library] <list>: N rows, M new`). The
  release log file otherwise only receives error reports, so a re-read that
  silently did nothing left no trace. The test machine's log now reads
  `[library] savedPlaylists: 61 rows, 7 new, complete=true`.
- **Tests**: `test/saved_library_refresh_test.dart`,
  `test/saved_library_lists_sync_test.dart`,
  `test/playlist_library_membership_test.dart`, and the 401 behaviour in
  `test/rate_limit_test.dart` (a 401 refreshes the session once and retries
  once; a 401 the session cannot fix is surfaced once; the gate stays open
  either way). Full suite 1638 pass / 2 skip; analyzer clean.

## 2026-10-22 — The Android release build needed a stale-file guard

- `make apk-arm64` failed with `package dev.flutter.plugins.integration_test
  does not exist`. The Android plugin registrant is generated **per build mode**:
  a debug build's version registers the `integration_test` dev dependency, and
  the release classpath does not contain it (Flutter's Gradle plugin strips dev
  dependencies from release variants). A stale debug registrant therefore
  fails the release compile, and the tool only rewrites the file when it
  regenerates the platform tooling — which it does not always do.
- The release APK targets now delete the registrant first
  (`make clean-android-registrant`), so a release build always regenerates it
  in release mode. Do not move `integration_test` out of `dev_dependencies` to
  work around it: that breaks the smoke test, and adding it to the release
  classpath ships test code to users.

## 2026-10-22 — The library is re-read, so two devices agree

- **Ask**: a playlist created on one device did not show up on another device
  signed into the same account, although Spotify itself showed it.
- **The creation side was never the problem.** `MetadataPluginPlaylistNotifier.create`
  calls the plugin's `create`, which creates the playlist *and* follows it into
  the account's library rootlist. The playlist really was in the account.
- **The reading side never asked again.** `metadataPluginSavedPlaylistsProvider`
  is a plain (non-autoDispose) `AsyncNotifierProvider`; its build serves the disk
  snapshot and revalidates *behind* it, and that revalidation only ever ran
  inside `build()`. The sidebar is always mounted and watches the same provider
  (`sidebarPlaylistIndexProvider`), so the list was fetched **at app startup** and
  then frozen. The only invalidations were pull-to-refresh, the error-box retry,
  playlist deletion and login/logout. No app resume, no connectivity restore, no
  window focus, no timer, no page-open. Hence "Spotify shows it, the other
  Spotube does not": Spotify's web player re-fetches on every load.
- **Fix — `SavedListCacheMixin.refresh()`** (`lib/provider/metadata_plugin/utils/paginated.dart`):
  a network-only re-read that replaces the list and re-persists the snapshot.
  Depth is `refreshAllPages` (renamed from `refreshAllPagesOnWarmBuild`): the
  playlists list walks every page, because Spotify *appends* a new playlist to
  the **end** of the library and a page-one probe cannot see it; the other lists
  keep the page-one probe.
- **Fix — one owner for the triggers**: `SavedLibraryRefresher`
  (`lib/provider/metadata_plugin/library/library_refresh.dart`) with a 1-minute
  shared cooldown per list, wired to **app start**, app resume, window focus
  (desktop), connectivity restored, the Playlists page being opened, and a
  10-minute foreground heartbeat.
- **All four saved lists are in it now** — playlists, liked tracks, saved
  albums and followed artists. Each at the depth it needs: the playlists,
  albums and artists lists are small, so a re-read walks every page of them;
  the liked-tracks list can hold thousands of rows and Spotify orders it by
  the time a track was saved, so a newly liked track arrives at its *head* and
  a page-one probe is enough — it is probed, never walked.
- **A re-read costs one request in the common case.** A page-one probe says
  whether the library moved (its reported total changed, or it carries a row
  the list never had); only then are the remaining pages read. The comparison
  is between two of the *plugin's* own counts, not between its count and the
  row count — those are different numbers and reading a difference between
  them would walk the library for nothing.
- **Fix — creation is verified against the library.** The plugin's rootlist
  write is invisible to the host and fails silently; the host now asks the
  network what the library holds after a create, repairs it with
  `playlist.save(id)` (the same rootlist write) when the playlist is missing, and
  tells the user (new l10n `warning` + `playlist_library_sync_failed`) when even
  the repair failed.
- **Fix — honest snapshots.** `persistSnapshot` used to refuse to write a list
  that was still paging, so a library with more playlists than fit on one page
  never had a snapshot at all, and the optimistic insert after a create never
  reached the disk either. The payload is now `{"v":2,"complete":bool,"items":[…]}`
  — same table, same column, no migration — and a v1 bare array still reads as a
  complete list. An incomplete snapshot is served with `hasMore: true`, so the
  page keeps paging instead of mistaking one page for the account.
- **Fix — a revalidation that was silently thrown away.** `_revalidate`/`_revalidateAll`
  bail out on `!identical(state.value, served)`, but the framework assigns
  `state` one microtask *after* `build()` returns — a revalidation that resolved
  in the same microtask batch compared against a still-null `state.value` and
  discarded its fresh result, with no log. They now yield once
  (`_awaitBuildDelivery`) before the comparison.
- **Fix — the error reporter could throw.** `AppLogger.reportError` touched a
  `late final` logger and died with a `LateInitializationError` when the logger
  had not been initialized, hiding the error it was supposed to report. It now
  goes through a null-safe accessor.
- **Tests**: `test/saved_library_refresh_test.dart` (two provider containers
  over one shared account: a playlist created on one device reaches the other
  only after a refresh; the re-read reaches past page one; the re-read is
  persisted; a failed re-read keeps the last-known-good list; an unchanged
  library costs one request; a changed one is read to the end; partial vs.
  complete snapshots; the refresher's cooldown), `test/saved_library_lists_sync_test.dart`
  (all four lists are re-read; the liked list is never walked; one failing
  list does not stop the others; a list skipped for being offline is not held
  back by the cooldown) and `test/playlist_library_membership_test.dart` (a
  missing library row is repaired, an existing one is left alone, a refused
  repair is reported). Full suite 1636 pass / 2 skip; analyzer clean.
- **Not covered**: the deep list of saved *podcasts* / shows does not exist —
  there is no such provider. Everything the app has a saved list for is in
  the sync.
- **Still unverified, needs two signed-in devices**: the end-to-end pass (create
  on A, see it on B without a restart; and the same for a liked track, a saved
  album and a followed artist).

## 2026-10-22 — Published: plugin 0.2.10 and app v5.1.2-fork.6

- **The plugin release has a naming contract, and it had never been met.** In-app
  update polls `releases/latest` and reads it in `core.ht:42-88`: `tag_name` is
  split on `.` and `int.parse`d (so the tag must be bare `0.2.10`, never `v0.2.10`)
  and the asset is chosen by `asset["name"] == "plugin.smplug"` — strict equality.
  The repo had **zero releases**, so the check always found nothing; a 404 is
  swallowed by `use_global_subscriptions.dart`, which is why it never looked like
  a bug, just a silent Settings badge that never appeared. A release named
  anything else is invisible to the app.
- **Publish order is not arbitrary.** `dependencies/hetu_spotify_gql_client` `main`
  (d64fbd3→87958f3) first, because the parent's gitlink points at that commit and
  an unreachable submodule breaks `--recurse-submodules` clones; then parent `main`
  + tag `0.2.10`; then the release with `--asset-file-name plugin.smplug`.
- **GitHub Actions cannot cut these releases.** `spotube-release-binary.yml` is
  `workflow_dispatch`, needs `KEYSTORE` / `KEY_PROPERTIES` / `DOTENV_RELEASE` (no
  signing material on the fork, and none to be had), and tags `v${PUBSPEC_VERSION}`
  — which is upstream's `v5.1.2`, with no `-fork.N`. Built locally instead, as
  fork.1–.4 were: 4 APKs, `.aab`, `make tar`, hand-computed sums. `android/key.properties`
  → `/home/adamya/spotube-local-debug.jks` is the signing key.
- **Version codes confirmed, not assumed.** `5.1.2+4506` (upstream build 45 + fork
  build 06) → `aapt dump badging` reports 4506 universal, 5506 armeabi-v7a, 6506
  arm64, 8506 x86_64, i.e. `abiIndex * 1000 + versionCode`. Bumped from 4501 so
  fork.6 is an upgrade rather than a same-code reinstall.
- **fork.6 ships the user's WIP by their choice**: local-library wipe
  (`selectFilesToDelete` roots paths inside download/cache only, then subtracts
  user-added folders), the playbutton navigation fix, l10n keys, gradle hygiene.
  Eight grouped commits; gated on analyze clean + **1614 pass / 2 skip**; the tag
  is the built commit, so the old "source may run behind the binaries" caveat no
  longer applies from this release on.
- **Deliberate exclusions.** No `*-android-nightly-debug.apk` (its `.nightly`
  suffix is what "the update forgot my settings" really was — TODO item now closed).
  `v5.1.2-fork.5` left unpushed: it names a commit already on `master` and never
  had binaries. `linux/*.appdata.xml` not touched — its `<release>` lines and
  `id`/`developer_name` are upstream's.
- **Installed locally** via `scripts/install-local.sh --skip-build` (no sudo:
  `/usr/local/share/spotube-custom` was already writable), and the installed
  `libapp.so` is byte-identical to the released bundle. The 0.2.10 kernel hash
  `ca093b62…` matches across plugin repo `dist/`, the APK and the desktop install.
- **Still unverified, needs a signed-in phone**: removal persisting in a real
  playlist, and the frost appearing before the first scroll on a header that has
  artwork. Neither surface is reachable anonymously, so neither is testable here.

## 2026-10-22 — Remove-from-playlist, lyrics open cost, Android artwork frost

- **Ask**: three Android reports — removing a song from a playlist "not working
  properly", 1-2s of lag when opening lyrics, and the playlist header's frost
  being flat until the first scroll.
- **Removal was three stacked failures.** The bundled plugin's
  `removeTracks(playlistId, {uris})` asserted on `tracks`, an identifier it never
  receives, so the DELETE was never built; the host called it un-awaited with no
  catch and passed `playlistId ?? ""`; and nothing wrote the local mirror, so a
  downloaded playlist re-painted the row. Fixed in plugin 0.2.10 (also stopped
  `checkUpdate` polling the upstream repo, which offered to replace Adamya's
  build with Sonic Liberation's), in `track_options_provider.dart` (await +
  guard + `showToast`, matching that file's four existing failure paths), and in
  `download_store.dart` (`detachTracksFromPlaylist` — membership rows only, the
  file stays for other playlists). `test/playlist_track_removal_test.dart` +
  a version pin in `test/bundled_plugins_seed_test.dart`.
- **Lyrics: the plan's biggest item was wrong, and the instrument proved it.**
  `IndexedStack` builds only its selected child, so `PlainLyrics` and its O(n²)
  join were never part of the open cost (`test/lyrics_open_cost_test.dart`:
  `PlainLyrics=0 SelectableText=0 SyncedLyrics=1` at open). What was real:
  `ShimmerLyrics` overflowed **417px per row** at phone width, the lyrics header
  row overflowed by 33px, `scrollToIndex` ran inside `itemBuilder`, and the join
  is O(n²) (fixed, worth microseconds, not the stutter).
- **Frost**: new `FrostedArtwork` (`lib/components/image/frosted_artwork.dart`)
  bakes the blur into the cover with `ImageFiltered` on Android and sets
  `surfaceBlur: 0` on the panel above it, replacing a `BackdropFilter` that was
  sampling a backdrop which had not resolved yet. Used by the playlist/album
  header and the lyrics page; `artworkIsSelfFrosted` gates it so desktop/iOS keep
  the old path. Android also stops watching `scrollInFlightProvider` there —
  nothing to freeze without a backdrop.
- **Measured**: see `.ai/PERFORMANCE.md` — host-side numbers, one usable AVD
  round (no regression, nothing banked), and the reason the frost's visual
  before/after cannot be produced on this AVD at all.
- **Open**: both artwork fixes and the real removal need a signed-in phone;
  `.ai/TODO.md` carries them as one P1.

## 2026-10-21 — The fork's own Spotify plugin is now the bundled metadata default

- **Ask**: recommend `Adamyabhatt01/spotube-plugin-spotify` instead of relying on
  whatever the remote index happens to surface, and stop the previous seed
  (Musicbrainz/Listenbrainz) from keeping the recommendation.
- **Bundle**: `assets/plugins/spotube-plugin-spotify/plugin.smplug` (0.2.9,
  sha256 `4b1ae107…`), declared in `pubspec.yaml` and in `assets.gen.dart`. It
  carries `authentication` + `metadata` and **no `audio-source`**, so it cannot
  move the audio default off YouTube Audio.
- **Seed order is the policy** (`bundledPlugins`,
  `lib/provider/metadata_plugin/metadata_plugin_provider.dart:44`): `addPlugin`
  hands an ability's default to the *first* installed plugin carrying it, so
  Spotify is listed ahead of Musicbrainz, and Radio Browser ahead of SomaFM.
- **Existing installs**: `addPlugin` only claims an unclaimed slot, so
  `handOverDefaultMetadata` moves the metadata default from the previous bundled
  seed to the newly installed one. It fires only for a row this pass created and
  only while the current default is another bundled seed — a default the user
  picked from the index is never overwritten, and audio/theme/radio never move.
- **Consequence, mitigated**: the plugin resolves browse from the logged-in
  account, so an anonymous Home used to render the plugin's raw
  `nullObject [credentials]` exception. `HomePageBrowseSection` now shows the
  existing `AnonymousFallback` ("You're not logged in" → Login → Settings →
  Plugins) when the default plugin declares `authentication` and is not
  authenticated. Non-auth defaults are untouched.
- **Verified on the AVD** (android-35 x86_64, release/stable, R8 on): `adb
  install -r` over the previous build added row 5 `Spotify | Adamya Bhatt |
  0.2.9` with `selected_for_metadata=1`, flipped Musicbrainz to 0, left the audio
  and radio defaults alone, and re-launching was idempotent (no duplicate row).
  Hetu loaded the shipped kernel — the failure it reported came from
  `src/segments/browse.ht:16` *inside the plugin*, which is proof the bytecode
  runs on 3.38.10.
- **Tests**: `test/bundled_plugins_seed_test.dart` (packaging + parse + seed
  order) and `test/bundled_plugin_default_handover_test.dart` (handover, the
  user-chosen-default guard, and the three no-op branches).

## 2026-10-21 — Delete local library (Android + desktop)

- **Gap**: the Local Library page could add folders but never clear what the app
  owned; the only file removal in the app was the cache folder's `clearCache`.
- **New action**: "Delete local library" on the Local Library toolbar →
  confirmation dialog naming the blast radius (file count, bytes, both folder
  paths, "downloads in progress will be canceled", and what is left alone) →
  `PlaylistMirrorService.forgetEverything()` → delete cache leaf + selected
  files in waves of 32 → one `ref.invalidate(localTracksProvider)`.
- **Ownership boundary** (`lib/services/downloads/local_library_wipe.dart`, pure
  and disk-free): a recorded `filePath` is not permission to delete. Only paths
  inside the download root or the cache leaf qualify, minus anything under a
  user-added library location — so adopted pre-existing files, files left at an
  older download location, and the user's own music keep their bytes while
  losing their rows. The download root is never deleted recursively.
- **Invalidation**: generations now fold a global `_epoch`
  (`_generationOf = _epoch + per-id delta`), because an unseen playlist reads as
  generation 0 and a per-id bump cannot change that answer. `forgetEverything`
  bumps the epoch, drops deferred auto-syncs, yields once so a parked enqueue
  lands against the queue it is about to empty, empties the queue (a late
  completion writes nothing: `_setStatus` persists only on a live-task match),
  then deletes rows in one transaction. Background auto-sync self-neutralizes —
  it iterates the now-empty mirror header list.
- **Scope**: mirrors, membership and download records only. History, sidebar
  pins, `mainPlaylistOrder`, preferences, Spotify-side collections and
  `library_snapshot_table` are untouched.
- **Tests**: `test/local_library_wipe_test.dart` — boundary cases (incl. download
  root inside a library location ⇒ nothing deleted), bulk clear leaves other
  tables alone, an in-flight walk writes nothing back, queue emptied.

## 2026-10-21 — Android album tap-to-play glitch closure (`a3eec4fc` follow-up)

- **Cause**: the cover-tap-mapped-to-play defect in `AlbumCard` was fixed in
  `a3eec4fc`, but the installed APK predated it. Two latent tap defects remained.
- **Fixes**: `onCoverPressed` deleted from `PlaybuttonCard`/`PlaybuttonTile` —
  no caller survived `a3eec4fc`, and removing the parameter makes a whole-cover
  play mapping impossible to reintroduce (compiler-enforced). Corner play/queue
  buttons stay always shown on touch (`hovered || kIsMobile`); they are small
  descendants that only win their own regions, so the rest of the cover
  navigates. `PlaybuttonTile` row `enabled` now follows `onTap != null` instead
  of `canPressPlay`, so taps navigate while tracks resolve.
- **Android build**: `android/gradle.properties` gains `org.gradle.parallel` and
  `org.gradle.caching`, and `enableJetifier=false` after moving the last legacy
  coordinate (`com.android.support:multidex` → `androidx.multidex`; the app
  source already imported `androidx.multidex.MultiDex`). Release APKs are built
  with `make apk-arm64`, which pins `--flavor stable` — three flavors were being
  R8'd serially and flutter then printed a false "failed to produce an .apk".
- **Tests**: hover-reveal/loading-glyph/interaction suites green, full suite
  green; `flutter analyze` clean.

## 2026-10-20 — Playlist auto-downloads + independent main order (uncommitted)

- **Schema v28**: `playlist_download_mirror_table.auto_download` (default off)
  and nullable `preferences_table.main_playlist_order`. The v27→v28 step seeds
  main order from sidebar pins only where the new column is NULL; `""` is the
  intentional-empty marker, so a cleared order is never repopulated.
- **Auto sync**: `PlaylistMirrorService` now maintains opted-in playlists
  page-by-page (50/page), queues per page, and writes header + complete
  membership only after the full walk. Startup idle and an offline→online edge
  trigger it; success is throttled, failure retries immediately and schedules\n  bounded 30s/60s/120s backoff retries (production only). Global
  download rows are reused across playlists; missing/empty files are marked
  `missing` and requeued. Persisted `failed`/`interrupted` rows and in-memory
  failed tasks are retried, including when a failed attempt left a non-empty
  file; retries write to an id-suffixed path so the old file is never reused or
  overwritten. Canceled stays canceled. Queued downloads wait for audio-source
  presets instead of failing before the plugin loads. Liked Tracks is
  automatic-download capable too, fetched from `user.savedTracks`.
  File validation is existence + non-zero size only.
- **Deletion safety**: `forget()` bumps a per-playlist generation before
  deleting mirror metadata; every playlist-scoped write/enqueue rechecks the
  generation, auto flag, and header. Disabling auto-download only clears the
  flag. No path deletes an audio file or a global download row.
- **Ordering/UI**: the Playlists page uses `mainPlaylistOrder` and a new
  reorder dialog, no longer sorting by pins. Main cover/name open the playlist;
  sidebar pins keep cover-play/name-navigate. `PlaylistCard` no longer maps its
  cover to play.
- **Tests**: new auto-download, order, interaction, and v27→v28 migration tests;
  persisted-failure retry and presets-wait coverage. Full suite 1550 pass /
  2 skip; `flutter analyze` clean.

## 2026-10-20 — Android bottom chrome, spinner truthfulness (`2be74adf`)

- **Cause**: the pinned Flutter 3.35.2 Impeller engine reuses the MSAA inline
  pass (`kDontCare`) for nested backdrop blurs, so a play/pause repaint through
  the floating player's `SurfaceCard` ghosted the wallpaper under it beside the
  nav bar's filter. Upstream flutter/flutter#173622; engine fix `84f5d26`
  (PR #174083) first ships in stable **3.38.0** — all 3.35.x builds still have
  the bug (verified against 3.35.2–3.35.7 sources). The old scroll freeze then
  dropped the chrome's blur to zero, which with a translucent theme removed the
  only visible tint, and source-resolution completion rebuilt the card.
- **Fix**: new shared `PlayerPlayPauseButton`
  (`lib/modules/player/player_play_pause_button.dart`) owns the
  `audioPlayerProvider.playing` watch and wraps the button in a
  `RepaintBoundary`. It shows the spinner/disabled state only while
  `isFetchingActiveTrack && !playing`; a downloaded/local stream can be audible
  before the source manifest settles. The collapsed transport row is its own
  consumer. Both bottom-chrome surfaces keep `theme.surfaceBlur` through scrolls
  (the freeze was not a measured CPU win), and Android release builds disable
  Impeller in the main manifest until the Flutter bump to >= 3.38.
- **Tests**: new `test/player_play_pause_isolation_test.dart`. Pre-fix failure
  proven (the widgets followed the idle global player, not app state);
  post-fix the icon flips, the card/controls widget instances stay identical,
  a genuine track change still rebuilds the card, playing+resolving keeps an
  enabled pause button, paused+resolving still spins, and a frozen scroll does
  not zero the card's blur. Full suite 1495 pass / 2 skip; `flutter analyze`
  clean; release APK built.
- **Residual**: track changes still rebuild the mini-player card by design;
  the Impeller manifest workaround holds until Flutter is bumped to >= 3.38,
  which remains the root fix.

## 2026-10-20 — Android cold start, crash guards, mobile search, queue restore (uncommitted)

- **Startup**: `startupSplashGateCap` 6 s → 2 s; a settled theme provider is
  enough to paint, including a resolved `null`. Native splash is preserved
  before the pre-frame init, `KVStoreService.initialize()` overlaps the device
  memory probe, and phase timing (`[startup] ...`) now goes through
  `AppLogger.logStartupLine`, so release builds write it to Settings > Logs.
  Radio-directory sync and the control server subscribe post-splash.
- **Crash guards**: fixed the synced-lyrics `useRef`-inside-`useEffect` hook
  mismatch; expected no-lyrics/no-track misses now log quietly. Album,
  playlist, artist and header paths guard empty artists/dates/owner names and
  read saved-list notifiers only on action instead of during page build.
  Empty queues disable shuffle/play/queue actions instead of calling
  `Random().nextInt(0)`. `FlutterError.onError` reports framework
  build/layout/paint failures to Settings > Logs.
- **Mobile search**: desktop-style Radio button hidden on narrow widths,
  16 px gutters, pinned search field, horizontally scrolling scope/result
  chips, localized "Music", and the grid/list toggle hidden below `mdAndUp`.
- **Search landing (Search only)**: the Music scope now shows recent searches,
  the personalized Browse rails (taste-based artists / recommended songs) and
  New Releases, with no Recently Played. The Radio scope drops the leading
  Music shortcut and the Recent rail; `useStationSearchSlivers` exposes
  `showMusicShortcut` / `showRecentRail` (both default `true`) so the actual
  Radio page is unchanged. The Search station field uses the 16 px phone
  gutters when the shortcut is hidden.
- **Queue restore**: restore no longer builds `SpotubeMedia` URIs before the
  local playback server binds (`:0` URLs made mpv skip through the whole
  playlist on every restart). It waits on `playbackServerPortProvider`, which
  first waits for the initial preferences load so a custom `connectPort` is
  honored. See `AUDIT_STATE.md`.
- **Tests**: startup gate, narrow search layout, crash guards (blank initials,
  empty artist sort), server-port ordering; full suite 1490 pass / 2 skip,
  `flutter analyze` clean.

## 2026-10-20 — Playback-cache and plugin-update correctness pass (uncommitted)

- Area: `lib/services/playback_cache_mirror.dart`,
  `lib/provider/metadata_plugin/metadata_plugin_provider.dart`;
  `test/playback_cache_mirror_test.dart`, `test/plugin_extraction_test.dart`,
  `test/plugin_update_test.dart`.
- **Mirror lifecycle leaks fixed.** `attach()` failure left the per-track slot
  reserved, disabling caching for that track until restart; `finish()` errors
  skipped controller closure and slot release; the slot was released before the
  `.part` rename, so a concurrent request could recreate/delete it; `_abandon`
  deleted after releasing. Cleanup now deletes before release, `finish` holds
  the reservation through the rename and releases in `finally`, `onDone`
  always closes the controller, and a throwing `onComplete` no longer holds
  the HTTP response open (the completed cache stays valid).
- **Bundled plugin updates compared the wrong version.** Detection compared
  `pluginApiVersion` only, so a normal `1.0.0 → 1.0.1` release with an
  unchanged API was extracted but never registered. `shouldUpdatePlugin()`
  now compares the plugin's semantic version first (API only as a same-version
  fallback); identity lookups use name+author instead of the lossy slug.
- **Plugin replacement is no longer remove-then-add.** The old row was deleted
  before the new insert, losing every selected/default flag and leaving the
  plugin unreachable if the insert failed or the process died between the two.
  `replacePluginRow()` now updates the existing row in one transaction
  (preserving id and all flags); the old version directory is deleted only
  after the row points at the new one.
- **Extraction is staged and swapped.** Archives were written directly over
  the live plugin directory and a failed re-extraction deleted it. Extraction
  now writes to `.staging-*`, promotes via a deterministic `.backup` rename,
  restores the old directory on failure, and recovers an interrupted swap on
  the next validation/extraction.
- **Tests**: mirror attach-failure slot release, throwing `onComplete` stream
  closure + valid cache; failed re-extraction preserves byte-identical old
  files, successful swap removes stale files, interrupted swap recovers,
  version-only update detection, and row update preserves id/flags.

## 2026-10-20 — Browse search dropdown sizes to its content and never slices a row (uncommitted)

- Area: `lib/modules/home/home_search_suggestions.dart`,
  `lib/modules/home/home_search_bar.dart`,
  `test/home_search_live_test.dart` (4 new cases).
- **The bug**: the suggestion panel was capped at a fixed
  `searchSuggestionPanelMaxHeight = 360`. Anything longer scrolled, and the
  fold cut whichever song landed on it — the reported "dropdown abruptly cuts
  the song at the bottom". The panel also never used the room it actually had.
- **Height is now measured, not guessed.** The bar keeps a `GlobalKey` on the
  `CompositedTransformTarget` and passes
  `suggestionPanelMaxHeight(context, fieldKey)` = window bottom − field bottom
  − 16px gutter. A short list stays short (the `ConstrainedBox` is a max), a
  long one opens at full length, and neither runs past the window.
- **The fold lands between rows.** `_RowSnappedScrollView` measures the
  Column's children after layout and trims the viewport to the last whole
  row, so an overflowing panel ends on a row edge instead of through a row.
  The gutter moved *outside* the viewport for this: padding inside a scroll
  view is content, so at the fold it showed a few pixels of the next row.
- **Tests**: short list < 360; long list > 360; no row straddles the fold
  (verified to fail with the snap disabled); taller window → taller panel.

## 2026-10-20 — Play/pause glyph follows the audio, not the selection; yt-dlp offered on Android (uncommitted)

- Area: `lib/components/play_pause_icon.dart` (new),
  `lib/components/track_tile/track_tile.dart`,
  `lib/components/playbutton_view/{playbutton_card,playbutton_tile}.dart`,
  `lib/modules/album/album_card.dart`,
  `lib/modules/playlist/{playlist_card,use_playlist_play}.dart`,
  `lib/modules/root/sidebar/sidebar_pin_tile.dart`,
  `lib/modules/track_presentation/{presentation_top,use_action_callbacks}.dart`,
  `lib/pages/artist/section/top_tracks.dart`, `lib/pages/track/track.dart`,
  `lib/services/youtube_engine/yt_dlp_engine.dart`,
  `lib/services/sourced_track/source_resolver.dart`,
  `lib/modules/settings/youtube_engine_not_installed_dialog.dart`,
  `lib/l10n/app_en.arb` (+ regenerated), `pubspec.yaml` (no new dep).
- **The bug**: `isPlaying` on a track row and on a play button means
  "this is what the player is on" — it survives a pause, so the row stays
  highlighted. The glyph read that same flag as "is sounding", so
  **pausing from the sidebar or an album card left the tile showing
  "pause"**. Every affected surface now reads the real state
  (`AudioPlayerState.playing`, kept in sync from `audioPlayer.playingStream`)
  or takes an explicit `isActuallyPlaying`.
- **The glyph now animates.** A bare `Icon(icon: playing ? a : b)` snaps
  with no motion. `AnimatedPlayPauseIcon` (new) cross-fades and scales
  between the two glyphs; the track tile already had an `AnimatedSwitcher`
  but the play/pause pair was a same-type swap inside it.
- **Track page**: the play button now resumes a paused active track
  instead of only ever pausing it.
- **Album/playlist header** (`useActionCallbacks`): the button is a real
  pause/resume control when the collection is already loaded, instead of
  reloading it from the top.
- **yt-dlp on Android**: the engine is now offered there
  (`kIsDesktop || kIsAndroid`) and searches `/data/local/tmp` and the
  app's own directory, with an execute-bit check (an `adb push` writes
  0644, which fails at exec time and reads as a broken engine). A
  missing binary is a **skip** in the resolution cascade, not a failure.
  It still cannot be *bundled*: no official yt-dlp build exists for
  Android, yt-dlp needs CPython 3.10+, and the only Android CPython is
  GPL-3 while the app is BSD-4-Clause. Full reasoning in
  `.ai/MEMORY.md`.
- Tests: `test/animated_play_pause_icon_test.dart` (5, including the
  `Button.leading` and `IconButton.icon` container paths),
  `test/track_tile_playing_glyph_test.dart` (3, verified to fail against
  the old behaviour), `test/yt_dlp_android_exec_test.dart` (5), plus two
  new cases in `test/source_engine_fallback_test.dart`. Full suite
  **1468 green / 0 failed**, `flutter analyze` clean.
- Builds: Linux release built and launched (PSS 336 MB idle, control
  socket up, 0 errors); Android **arm64-v8a** release APK built
  (`app-arm64-v8a-stable-release.apk`, **68.2 MB**). The play/pause glyph
  was verified on the running release build: the "Liked Tracks" card
  shows ⏸ while the track plays and ⏵ once paused, on a collection that
  *is* in the queue (the exact case that used to stick on ⏸).
- **arm64-v8a-only APK** (`make apk-arm64`, new). `--target-platform
  android-arm64` alone is **not** enough: it narrows the Dart AOT, but
  with ABI splits disabled the Flutter Gradle plugin sets
  `buildType.ndk.abiFilters` to all three ABIs, so mpv / metadata_god /
  media_kit / flutter_discord_rpc still ship for armeabi-v7a and x86_64
  (91.7 MB APK). `--split-per-abi` makes the plugin emit
  `splits.abi.include("arm64-v8a")` and nothing else → **68.2 MB**, and
  `aapt2 dump badging` reports `native-code: 'arm64-v8a'` with no other
  ABI present. The plugin's per-ABI `versionCodeOverride`
  (arm64 = 2 × 1000 + versionCode → 6501) keeps Play Store versioning
  correct. Verified: `libspotube.so` exports
  `Java_oss_krtirtho_spotube_MemoryBacking_nativePrctl`, and R8 kept
  `MemoryBacking` + `DeviceMemoryChannel`.

## 2026-10-19 — RAM: transparent huge pages were 227 MB of phantom RSS; CLI, control channel and MCP server (uncommitted)

- Area: `linux/main.cc` (THP + MCP stdout), `linux/my_application.cc` /
  `.h` (command-line handling, MCP stdout), `android/.../MemoryBacking.kt`,
  `MainActivity.kt`, `DeviceMemoryChannel.kt`, `cpp/memory_backing.cpp` +
  `CMakeLists.txt`, `lib/services/memory/{device_memory_profile,memory_budget}.dart`,
  `lib/services/control/{control_protocol,control_server,control_commands,mcp_server}.dart`,
  `lib/provider/server/{control_server_provider,control_command_delivery}.dart`,
  `lib/services/cli/cli.dart`, `lib/main.dart`, `lib/utils/service_utils.dart`,
  `lib/components/image/universal_image.dart`, `pubspec.yaml`
  (`dart_mcp`), `.ai/MEMORY.md` (new).
- **RAM**: the plan's premise was a ~365 MB Dart heap. The live heap is
  **27.5 MB** (the VM's own `getMemoryUsage`). The rest was the kernel
  backing the VM's sparsely-touched 5.1 GB arena with 2 MB transparent
  huge pages. `prctl(PR_SET_THP_DISABLE)` (Linux runner + the Android
  equivalent) drops AnonHugePages 250 MB → 0 and the footprint from
  **PSS 548 → 315 MB / RSS 648 → 415 MB**, with the smoothness cost
  inside run-to-run variance (fault rate and CPU overlap between THP on
  and off across four runs each). The Flutter floor is 90 MB PSS.
- **Image budget**: the three caches now share one device-aware budget
  (a quarter of the platform's per-app heap limit, bounded 8–64 MB);
  the artwork memo is bounded by **bytes** instead of entry count.
- **CLI**: the Linux runner returned `FALSE` from `local_command_line`
  while declaring `G_APPLICATION_HANDLES_COMMAND_LINE`, so GLib exited
  1 and **the Dart entrypoint never ran** — every flag was dead
  (`--version` printed nothing). Fixed to match the Flutter template
  (`TRUE` + `G_APPLICATION_NON_UNIQUE`); the parser also ignores unknown
  switches instead of aborting.
- **Control channel**: a local-only endpoint (Unix socket / loopback
  port) separate from the LAN-exposed connect server.
  `spotube --play/--search/--pause/--resume/--next/--previous/--status/
  --volume` drive the running instance.
- **MCP**: `spotube --mcp` runs the official dart-lang `dart_mcp` server
  on stdio (four tools) over the same command vocabulary, in its own
  process, so it costs the running app no memory. The Linux runner
  parks stdout on a dedicated descriptor in `--mcp` mode, because the
  native media_kit plugin prints to stdout before Dart starts.
- Tests: `test/control_channel_test.dart` (21 green) covers the wire
  protocol, the socket round trip and the budget policy. Full suite
  **1426 green / 0 failed**, `flutter analyze` clean, Linux release
  build succeeded and was driven end to end (CLI commands, MCP
  initialize/tools/list/tools/call).
- Not measured: the 5k-tracks and 1-hour-playback checkpoints (the
  profile's Spotify token is rejected), and the Android APK build
  (no licensed toolchain on this host).

## 2026-10-19 — Playback crash on a null container preset; measured RAM baseline (uncommitted)

- Area: `services/sourced_track/sourced_track.dart` (`container` getter),
  `models/metadata/audio_source.dart`
  (`fileExtensionForContainer`), `provider/server/routes/playback.dart`
  (4 force-unwraps → `container`), `services/metadata/endpoints/
  audio_source.dart` (guarded `supportedPresets`),
  `provider/metadata_plugin/audio_source/quality_presets.dart`
  (`clampPresetIndex`), `provider/download_manager_provider.dart`,
  `pages/settings/sections/playback.dart`,
  `components/fallbacks/error_box.dart` (Login button on a 401),
  `scripts/mem-report` (new), `.ai/MEMORY.md` (new).
- **Fix**: `SourcedTrack.qualityPreset` is nullable by design (the
  audio-source plugin publishes presets asynchronously; a persisted index
  can point past the end of a shrunken list). `playback.dart`
  force-unwrapped it in four places, so the stream request threw and the
  player reported "Failed to open http://127.0.0.1:<port>/stream/<id>".
  `container` now resolves through the same fallback chain `url` already
  used. The persisted index is clamped on restore, which also removes two
  direct-index `RangeError` sites (download pump, Settings → Playback).
  The cache path is now passed into `_finalizeCachedTrack` instead of
  re-derived, so the metadata lands on the file that was mirrored.
- **Measurement**: `scripts/mem-report` (new) samples PSS/RSS/smaps_rollup
  + the top private mappings + the whole process tree. Measured fresh
  release build: **PSS 496.7 MB / RSS 610.0 MB at t+30s, PSS 548.1 MB /
  RSS 648.1 MB at t+300s**, against a stock-Flutter floor of **PSS 90.0 MB
  / RSS 188.0 MB** (a `flutter create` app measured with the same
  harness). The dominant consumer is the **Dart heap: ~365 MB of 571 MB
  RSS**, in one 5.1 GB reservation with 230 MB in transparent huge pages.
- **WebKit at idle is 7.4 MB** (1.3% of RSS) and spawns no helper process
  until a webview is opened — the RAM plan's item 1.1 is dropped on
  evidence. The webview is not host code (it lives in the metadata plugin
  and is a declared `PluginApis.webview` capability), so removing it
  would break plugin authentication. The plan's PSS baseline of 348 MB
  was stale by ~200 MB.
- Tests: `test/source_quality_fallback_test.dart` (container resolution,
  extension mapping, index clamp) and
  `test/search_tab_scaffold_test.dart` (credential error offers
  re-authentication). Full suite 1403 green / 2 skipped, `flutter analyze`
  clean, Linux release build succeeded.
- Not measured: the 5k-liked-tracks and 1-hour-playback checkpoints (need
  a live Spotify session; the test profile's token is rejected), and a
  DevTools heap histogram to attribute the 365 MB Dart heap. The latter is
  the blocking measurement for RAM items 1.2 and 1.5.

## 2026-10-01 — Radio station sidebar pins (uncommitted)

- Area: `models/database/{tables/preferences,database}.dart` (schema 25→26,
  `pinned_station_ids`), `provider/radio/pinned_station.dart` (new),
  `provider/user_preferences/` (toggle/setter), `modules/radio/
  radio_station_tile.dart` (pin buttons), `modules/root/sidebar/
  {sidebar,sidebar_station_pin_tile,sidebar_order_dialog}.dart`,
  `pages/settings/sections/sidebar.dart`, `l10n/app_en.arb`
  (`pinned_stations{,_description}`, en-only precedent).
- Storage mirrors playlist pins: comma-joined string list of station
  `favoriteKey`s, guarded `from25To26`, `make migrate` snapshots green
  (all →v26 pairs pass).
- Resolution order per pin: favorites snapshot → history snapshot →
  owning directory `byId` → null (skip-never-crash, playlist rule).
  Synchronous snapshot reads (not awaited futures): awaiting inside the
  build lets a snapshot emission rebuild mid-flight and discard the
  in-flight `byId`, multiplying directory calls; verified by watching a
  rebuild loop reproduce in a probe test before switching.
- Whole pin row plays (no station-detail route exists): play/pause/resume
  toggle via `radioPlaybackController`. Active station reads secondary
  style instead of route selection.
- Sidebar DnD shares the `pins` group: raw favoriteKeys can never collide
  with playlist ids through `resolveSidebarDrop` (unknown id → null drop),
  so cross-type moves are no-ops by construction.
- Tests: `test/radio_pinned_station_test.dart` (resolution ×4, incl.
  malformed keys), pin-toggle widget test in `radio_ui_test.dart` (needs
  seeded prefs row — the notifier's first load seeds via path_provider,
  which has no plugin in widget tests — plus a 10 s pump past the pin
  toast's dismiss timer). Full suite 396 green, `flutter analyze lib`
  clean.

## 2026-09-30 — Shell-owned glass: backdrop derives from foot.ini + shell.json (uncommitted)

- Area: `modules/theme_caelestia/caelestia_glass_config.dart` (new),
  `modules/theme_background/{theme_shell_source,caelestia_shell_source,
  caelestia_theme_source}.dart`, `provider/metadata_plugin/
  metadata_plugin_provider.dart`, `services/theme_definition_cache.dart`.
  No schema, no model, no codegen change.
- Change: the Caelestia shell now owns the *glass*, not just the palette.
  `ThemeShellSource.getGlass()` (nullable, defaults to null so non-Caelestia
  shells and missing configs keep the plugin's authored numbers) reads
  `~/.config/foot/foot.ini` `[colors-<mode>] alpha`/`blur` and
  `~/.config/caelestia/shell.json` `appearance.transparency`, and builds
  `background = {opacity: 1.0, blur: kShellBlurSigma(16), overlay:
  #AA<scheme surface>}` plus `surfaces.opacity = transparency.base`.
  `mergeShellPalette` applies it before the existing re-sanitize; radius,
  density, tokens and `surfaces.blur` stay plugin-owned.
- Why `opacity: 1.0` with an alpha-bearing veil: `ThemeBackgroundLayer` wraps
  `Stack[Image, BackdropFilter, ColoredBox]` in `Opacity`, so the old
  `opacity: 0.55` scaled the whole composite against the palette background —
  a second, unintended blend. Drawing the wallpaper at full strength and
  letting the veil carry the alpha reproduces foot's composite.
- Overlay byte order is **AARRGGBB** (`ThemeConverter._color` feeds an 8-digit
  string into `Color(int)`); CSS `RRGGBBAA` would swap alpha into red.
- `watchTheme()` fans three directory watches (state dir, `caelestia/`,
  `foot/`) through `_mergeSignals` into the existing 300 ms coalescer.
  Hand-rolled merge because `rxdart` is transitive-only.
- Cache payload bumped to `v2` so a warm start never replays the old
  translucent-veil semantics.
- `ThemeBackgroundScope` now leaves `ScaffoldTheme.backgroundColor`
  **transparent** instead of painting the opaque `background` role. It painted
  `#130c0e` over the `Stack`, so the derived glass was computed correctly and
  never reached the screen on any normal page. Safe because the shell layer
  draws the wallpaper at full strength, so it is itself opaque.
- `themeBackgroundImageProvider` split: `themeBackdropUrlProvider` (size-
  independent URL, null when nothing can paint) → `themeBackdropActiveProvider`
  (bool) → the sized family. Three opaque paints that the shell glass had to
  displace are now each gated on that one predicate instead of being applied
  for every theme:
  - `ThemeBackgroundScope` (already gated by construction),
  - `modules/root/sidebar/sidebar.dart` — the transparent
    `colorScheme.background` that stops shadcn's pinned `NavigationLabel` from
    banding across the backdrop,
  - `components/titlebar/titlebar.dart` — `AppBar` now gets
    `backgroundColor: Colors.transparent` while a backdrop is active, so the
    strip *is* the ground. Its `card`-at-`surfaceOpacity` fill was inert to a
    veil change (3/255 against 61 for the sidebar). Painting the backdrop's own
    veil there instead was measured and rejected: the ground behind the bar is
    already veiled, so a second veil composites to ~95% surface — right colour
    at rest, still inert. `headers` sit in a flex column rather than over the
    body, so nothing scrolls under the bar except on the four
    `floatingHeader: true` pages, which keep a blur-only frost.
- The gate is shell-only: `themeBackdropUrlProvider` returns null unless the
  theme declares `ThemeBackgroundSource.shell`, so the album-art branch is gone
  and no theme the user picked themselves turns on a transparent ground, bare
  title bar or unfilled sidebar headings. Caelestia-scoped by construction,
  since `"source": "shell"` is served only by `CaelestiaShellSource` and its
  wallpaper path is null without Caelestia state. Pinned by four new cases in
  `test/backdrop_decode_test.dart`.
- The glass is now plugin-decidable, not user-decidable: `mergeShellPalette`
  applies *both* halves of the derived glass only when the plugin declares
  `background.source == shell`. A plugin that wants the shell's colors on a
  plain background keeps its own `surfaces.opacity`/`blur` and its own
  backdrop block byte-for-byte — i.e. exactly the pre-shell-glass appearance —
  with no app setting and no schema change. Shipping as a second theme:
  `../spotube-theme/caelestia_theme_plain.ht` →
  `caelestia-plain-1.0.0.smplug`, pinned end-to-end by
  `test/caelestia_plain_theme_test.dart` (Hetu bytecode → production endpoint
  → production merge), which skips when the sibling checkout is absent.
- Verified: `flutter analyze` clean; `flutter test` 1226 passed / 2 skipped;
  release Linux build OK. Live re-derive confirmed twice over: against the
  app's own `theme_definition_cache.v2` (exact values in AUDIT_STATE) and
  pixel-wise — `foot.ini alpha` 0.78 → 0.02 changed **63.8% of screen pixels**
  (mean delta 72/255) with no restart. Title bar after the fix: 32–35/255, in
  line with the 34–47 around it. Configs restored byte-exactly.
- Known limits: in light mode `ThemeConverter.adaptOverlayForBrightness`
  replaces the veil *color* with white while keeping the alpha, so the
  surface-derived hue is dark-mode only. Several `BackdropFilter`s elsewhere
  remain hard-coded (`mini_lyrics.dart:224`, `connect/control.dart:344`,
  `player_actions.dart:108`, `player.dart:93`, `pages/track/track.dart:107`).

## 2026-09-29 — Radio browse: country dropdown + card consistency (uncommitted)

- Area: radio browse UI only (`pages/radio/radio.dart`,
  `modules/radio/radio_station_tile.dart`,
  `components/playbutton_view/playbutton_view.dart`). No
  provider/model/service/persistence change.
- Change: `_BrowseRail` keeps `Popular` + tag chips but replaces the
  truncated country chips (`take(30)`) with a `Select` dropdown listing all
  countries as `name (stationCount)` with a `None` clear option; writes the
  same country code through the existing exclusive tag/country/search query,
  session-local. `RadioStationCard` overlay moved to bottom-right, card cover
  uses `cardCornerRadius`, empty subtitle keeps the `'\n'` slot, tile cover
  `48→50×scale` — matching the shared playbutton card/tile geometry.
  `PlaybuttonView` gained optional `gridLoadingItem`/`listLoadingItem`
  (defaults unchanged); radio passes shimmer bones matching its own rows.
- Verified: `flutter analyze` clean on touched files; radio suites green
  (58 passed incl. new `radio_ui_test` dropdown case; `test/` is gitignored,
  local-only). Manual phone/desktop visual pass still pending.

## 2026-09-27 — Optimization/cleanup audit execution (PRs 1–5 of the audit plan, uncommitted)

- Area: playback proxy, downloads, kv-store, error handling, dead code,
  dependencies, plugin-pagination layer, layering.
- Files: `provider/server/routes/playback.dart`, `provider/download_manager_provider.dart`,
  `services/kv_store/encrypted_kv_store.dart`,
  `provider/metadata_plugin/audio_source/quality_presets.dart`,
  `provider/glance/glance.dart`, `utils/service_utils.dart`,
  `provider/metadata_plugin/utils/family_paginated.dart`,
  `collections/{spotube_icons,fake}.dart`, `pages/library/user_playlists.dart`,
  `pages/lyrics/synced_lyrics.dart`, `services/sourced_track/source_resolver.dart`,
  `theme_definition_cache.dart` (moved `modules/theme_background/` → `services/`),
  `models/color.dart` (new — `SpotubeColor` moved out of the picker dialog),
  `models/sort.dart` (new — `SortBy` moved out of the local-library page),
  `pubspec.yaml`.
- Change (all UI-preserving, all tested unless noted):
  - **UA-pin LRU** (`_userAgentFor`): was `clear()` at the >16-entry bound —
    wiped the *playing* track's pinned UA, re-randomizing it mid-playback
    (a seek re-probe then draws a fresh random client → 403 → full-cascade
    rebuild). Now LRU with access-refresh: the playing track is re-touched on
    every HEAD/GET, so it is never the oldest entry; others evict
    oldest-first. `test/playback_proxy_requests_test.dart`
    "the playing track UA survives the 16-entry bound" (red on the old shape
    by construction: a re-touched track id + two more inserts + a third probe
    of the original id).
  - **`EncryptedKvStoreService`** reports both catch paths via
    `AppLogger.reportError` — a secure-storage failure silently switching to
    the legacy key (data loss with no trail) is now diagnosable.
  - **`quality_presets`**: `_initialize`'s async callback was passed to
    `whenData`, which discards the future — a missing audio-source plugin
    threw an *unhandled async error*, never an `AsyncError` on the provider.
    Now `_restorePersistedState` reports and returns; `_updatePreferences`
    same shape fixed. Success path identical.
  - **`_getSourcedTrack`** adds `orElse` → null (doc said "or null"; the
    missing `orElse` made a removed-from-queue track 500 instead of 404).
    Live playback check pending: mpv treats both as stream failures reaching
    the same fallback machinery, but the status change is a behavior delta —
    RUNTIME VERIFICATION REQUIRED.
  - **`clearAll`** closes dropped tasks' stream controllers, mirroring
    `_pruneTerminalTasks` (it dropped them unclosed). `download_cancel_test`
    "clearAll closes the dropped task stream controllers".
  - **Pagination engine deduplicated**: `family_paginated.dart` re-implemented
    the mixin's members twice (~320 lines, incl. the dangerous
    `dynamicItem.id` dynamic-invocation pattern ×3); the two family base
    classes now apply `PaginatedAsyncNotifierMixin` directly (its
    `on AsyncNotifierBase<...>` constraint accepts family notifiers —
    verified against riverpod 2.6.1 sources). The dead non-autoDispose twin
    `FamilyPaginatedAsyncNotifier` (zero references) was deleted;
    `snapshotKey` defaults null, so the snapshot-persist path stays a no-op
    for families — identical to the copies. 40 pagination/snapshot/lifecycle
    tests green.
  - **`trackFileStem`** (`service_utils.dart`): the `"<name> - <artists>"`
    stem was re-derived inline at four on-disk-naming sites with two
    spellings (`", "` downloads vs `","` cache-prefix matching); one source
    of truth, formats byte-for-byte preserved
    (`download_playlist_dedup_test`, `playback_proxy_requests_test`,
    `chunk_download_test` green).
  - **Layering moves**: `SortBy` → `models/sort.dart` (utils→pages inversion),
    `SpotubeColor` → `models/color.dart` (provider/models→modules inversion;
    the drift converter now imports the model file), `theme_definition_cache.dart`
    → `services/` (provider→modules inversion). Import repoints only.
    Note: the mover must repoint `test/track_tile_play_target_test.dart`'s
    `show SortBy` import — caught by analyze after the move.
  - **Diagnostics**: cascade candidate failures in `source_resolver.dart` are
    counted (`playback.fallbackCascade.candidateFailure`, debug-only) + a lazy
    log line instead of bare `catch (_)`; `glance.dart` routes the background
    callback through `AppLogger.reportError` with the stack (was a plain
    `Logger()` per invocation, no trace) and its one `package:http` GET now
    rides dio with `validateStatus: always-true` (same shape);
    `theme_definition_cache` write catches report like the read path.
  - **Dead code/deps/assets**: 19 unused `SpotubeIcons` constants removed
    (grep-verified zero refs); the commented-out PlaylistGenerator block
    (`user_playlists.dart`) removed; `win32_registry` (zero imports anywhere)
    and `http` (one call site) removed from pubspec after `pub get` + registrant
    check; `spotube-logo-light.png`, `assets/images/logos/` (3 files) and the
    `fixing_bugs.svg` declaration removed (native-manifest re-grep clean;
    unused in lib/). `browseSection` removed from `FakeData` — but
    `FakeData.album`/`.playlist` were **not** dead (referenced internally by
    the history entries; the audit grep missed same-file refs) and were kept.
  - **Doc fix**: `.ai/PERFORMANCE.md` C4 entry updated to "implemented +
    bounded" — the ManifestCache (LRU-32, strict expiry) is built and tested
    (`manifest_cache_test.dart`), and the previously unwritable C4 re-entry
    regression test exists ("second serve of an unexpired match skips
    re-extraction"). The stale "not built / cannot be validated" entry was
    superseding real work.
- Not executed (report-only per plan): R-02 god-file splits beyond the local_folder
  handler extraction (done — two cache handlers extracted verbatim), F4 role
  providers (high risk), F3 search notifiers (WIP consumers), F6 history window
  unification (EXCLUDED — UI/UX change), `fluentui_system_icons` replacement
  (EXCLUDED — icon glyphs would differ), scrobbler gate test (needs a
  scrobblenaut seam; blocker corrected in `.ai/TODO.md`).
- Verified: `flutter analyze` clean for lib/ (3 pre-existing scratch-file
  infos); full suite 1189+ passing, the single pre-existing radio-test failure
  unchanged ("Bad state: open failed"; also two compile-only-in-test radio
  errors pre-existing). No new failures.

## 2026-09-27 — Internet radio becomes a real Hetu plugin ability (PR-1..5, uncommitted)

- Area: metadata-plugin subsystem, Drift schema, Settings, radio directory layer.
- Motivation: the shipped Radio feature was an in-app Dart extension point
  (static `radioProviders` + a hard-coded `RadioBrowserProvider`) with no
  Settings surface, so users could not see/enable/reorder/extend radio sources
  the way they can metadata / audio-source / theme providers.
- Files: `models/metadata/plugin.dart` (`radio` ability) + generated;
  `models/database/tables/metadata_plugins.dart` (`selectedForRadio`) +
  `database.dart` (schema 24→25, `from24To25`) + `drift_schemas/`/`database.steps.dart`;
  new `services/metadata/endpoints/radio.dart` (`MetadataPluginRadioEndpoint`);
  `provider/metadata_plugin/metadata_plugin_provider.dart`
  (`defaultRadioPlugin(Config)`, `setDefaultRadioPlugin`, `radioPluginProvider`,
  `isAnyRadioPluginSelected` + `addPlugin` seeding, two bundled plugins in
  `_loadDefaultPlugins`); new `provider/radio/plugin_directory_adapter.dart`;
  `provider/radio/stations.dart` (`radioProvidersFor` + `radioPluginDirectorySyncProvider`);
  `services/radio/radio_directory_provider.dart` (in-app provider + UA cache
  removed); `main.dart` (watch the sync provider at root);
  `pages/settings/metadata_plugins.dart` + `modules/metadata_plugins/installed_plugin.dart`
  (Radio tab/badge/default button, mobile-scroll tabs); `metadata.dart`
  (`@visibleForTesting MetadataPlugin.forTesting`). New plugin sources under
  `plugins/internet-radio-{browser,somafm}/`, `scripts/build-radio-plugin.sh`,
  `scripts/plugin_zip.dart`, bundled `assets/plugins/*/plugin.smplug`.
- Change: `radio` is an additive optional ability (no plugin-API bump); plugins
  without a `radio` member are never routed to the endpoint. The existing Radio
  UI, playback, ICY title and persistence are unchanged because the plugin
  adapter implements the same `RadioDirectoryProvider` interface.
- Verified: full radio + drift + new-adapter set green (354 tests in the
  touched files); `flutter analyze` clean on the changed files; both compiled
  `.smplug` plugins round-tripped live through the production endpoint over
  HTTP (SomaFM stations/tags/byId/search/non-US-empty; Radio Browser
  stations/tags), which caught a real bug (a bare `{}` `queryParameters` is an
  HTStruct and must be `.toJson()`).
- Deferred: new UI strings stay literal English to avoid regenerating the
  user's dirty `app_localizations*.dart`. All changes are UNCOMMITTED; the
  user's search-redesign WIP in the shared dirty files is untouched.

## 2026-09-27 — Second-pass roadmap PRs 10–13: snapshot debounce, battery/logging hygiene, cleanup (uncommitted)

- Area: library snapshot persistence, Discord RPC retry, release-mode logging,
  tray/blacklist error handling, dead code, filter-hook duplication.
- Files: `provider/metadata_plugin/utils/paginated.dart` + 4 saved-list
  notifiers, `provider/discord_provider.dart`,
  `services/sourced_track/sourced_track.dart`, `provider/server/server.dart`,
  `services/youtube_engine/yt_dlp_process.dart`, `provider/blacklist_provider.dart`,
  `provider/tray_manager/tray_manager.dart`, new `hooks/utils/use_debounced_filter.dart`,
  4 library/settings pages, `services/artwork_cache_manager.dart`, plus the
  A-01 deletions (`edit_instance_url_dialog.dart`, dead `ServiceUtils`/
  `PrimitiveUtils`/player-stream/`ImagePlaceholder` members), and
  `test/{image_decode_size,universal_image_source}_test.dart`.
- Change: library toggles persist snapshots through a 2s trailing debounce
  (`scheduleSnapshotPersist`) instead of one full-list write per toggle;
  Discord connect retries are capped at 12 and stopped via `disconnect()`;
  hot release-mode logs are `kDebugMode`-guarded or lazy-closure; two
  dropped-error sites now await/report; the keystroke-debounce + empty-fast-path
  preamble is one hook; ~150 lines of commented-out widgets and reference-free
  members are gone. UI byte-identical throughout.
- Fixed: two image widget tests broke under the full run because PR 8 wired
  `ArtworkCacheManager.instance` into the http provider branch, whose
  construction needs `getTemporaryDirectory()`. Test-side only — registered the
  existing `FakePathProvider`; no production change.
- Tests: full `fvm flutter test` green (1091 passed / 2 skipped); `dart
  analyze` clean across `lib/`.

## 2026-09-27 — Second-pass roadmap PRs 8–9: network ceilings + download I/O (uncommitted)

- Area: connectivity probing, artwork caching, plugin index HTTP cache,
  chunked downloader, disk hygiene around downloads.
- Files: `services/connectivity_adapter.dart`,
  `services/artwork_cache_manager.dart` (new) + 4 image call sites,
  `provider/metadata_plugin/core/repositories.dart`, `extensions/dio.dart`,
  `services/music_cache_policy.dart`, `provider/user_preferences/user_preferences_provider.dart`,
  `provider/download_manager_provider.dart`.
- Change: single-flight connectivity probes with explicit 5s ceilings; one
  `ArtworkCacheManager` singleton (1500 objects, same FCM key) wired through
  every artwork call site; 60s TTL + conditional-request cache for the plugin
  index; `chunkDownload` writes range slices positionally into a staging
  `.part` and renames once, with size-adaptive connection counts; startup
  sweep of legacy `.chunk_dl_*` scratch; a completed download evicts the
  playback-cache copy of the same track.
- Measured: 5 MiB loopback transfer writes 10.5 MB vs 15.7 MB for the old
  parts+concatenate flow (~33% less, byte-identical output); 5 concurrent
  connectivity probes cost one set of HEADs.
- Tests: `chunk_download_test` +3 (multi-connection exactness, misreported
  length fallback, staging sweep), new `connectivity_probe_ceilings_test`,
  `plugin_index_cache_test`; download+cache subsets 73 green.

## 2026-09-27 — Second-pass roadmap PRs 1–7 (uncommitted)

- Area: drift open args, startup I/O, playback/proxy pipeline, queue ops,
  connect hygiene, history/plugin/scrobbler query repetition.
- Files: `models/database/database.dart`, `services/music_cache_policy.dart`,
  `provider/server/{pipeline,routes/playback,routes/connect}.dart`,
  `services/{audio_player/custom_player,playback_cache_mirror}.dart`,
  `provider/audio_player/audio_player.dart`, `hooks/configurators/use_endless_playback.dart`,
  `provider/history/top/playlists.dart`, `provider/scrobbler/scrobbler.dart`,
  `provider/metadata_plugin/metadata_plugin_provider.dart` (+3 more, see
  `.ai/AUDIT_STATE.md` "Second-pass optimization roadmap").
- Change: WAL + PRAGMAs; batched `stat()` waves; broadcast-stream wrapper
  removed so cancels reach dio; mpv disk cache/vid/sid off; shuffle events
  re-permute instead of decoding; per-track stable user-agent; playlists
  top-list aggregated in SQL; scrobbler auth de-duplicated; plugin file checks
  memoized per `slug@version`.
- Measured: playlist history write → 3ms at 5002 rows (was linear in history
  size); numbers in `.ai/PERFORMANCE.md`. Deferred with evidence: PB-04
  (no safe media_kit bulk-append), PB-05 (wire contract), D-03 (no win found).
- Tests: full suite green (1076/2 skipped) + new pragma, shuffle-identity,
  playlist-grouping suites.

## 2026-09-26 — Roadmap PR 5: startup deferral (R-01, R-02)

- Area: `lib/main.dart` only.
- Commits: `e9e0eef4` harness, `dc4f46cc` R-01, `6d7e6d8a` R-02 gate,
  `02fff4db` R-02 warm-ups.
- Change: `WindowManagerTools.initialize` is no longer awaited before
  `runApp`; the splash gate (`startupGateAllowsApp`) is evaluated in `build`
  with the cap timer as the only timer; the eight keep-alive provider
  subscriptions moved from inline `ref.listen` to `listenManual` in a
  post-frame effect behind that gate. `startupSplashGateCap` is now the single
  source for the 6s cap so predicate and timer cannot drift.
- Measured (profile, warm start, `SPOTUBE_STARTUP_LOG`): app visible
  189–209ms → ~50ms; `pre-runApp` 70–76ms → 42–48ms. Numbers and the rejected
  R-04 experiment are in `.ai/PERFORMANCE.md`.
- Coupling to remember: the gate opens on `cachedThemeDefinitionProvider`
  (SharedPreferences only). Anything gated behind it must not be something the
  theme path itself needs, or a cold start waits for the cap.
- Not done: R-03 (target file is the user's untracked search redesign), R-04
  (measured no win, reverted).

## 2026-09-26 — Roadmap PR 4: log cap, music-cache ceiling, `.part` sweep

- Area: `services/logger/logger.dart`, new `services/music_cache_policy.dart`,
  `user_preferences_provider.dart`, `server/routes/playback.dart`, schema v23.
- Change: `.spotube_logs` is capped at 5 MB and rewritten to its last 1 MB
  (cut on a newline) when a release-mode report passes that. The music cache,
  previously unbounded (360 MB / 34 files measured), gains an opt-in
  `music_cache_limit_mb` preference (default 0 = today's behavior) applied on
  each newly cached track and immediately when the setting changes.
  Recency = `max(mtime, last served in-process)`, so the active/next tracks —
  which mpv HEADs before GETting — are never the victims; `.part` is excluded
  from eviction and swept at startup once untouched for >10 min.
- Coupling to remember: `PlaybackCacheMirror.isMirroring()` is the in-flight
  guard the sweep consults; `MusicCacheUsage` is process-local, so a restart
  forgets which files were hot (costs a re-download, never correctness).
- UI: Settings > Playback row "Music cache limit" with **hardcoded English
  literals** — the generated l10n files all carry the uncommitted search
  redesign's regeneration, so a new key would commit someone else's diff.
- Tests: `test/music_cache_policy_test.dart` ×8, `test/log_rotation_test.dart`
  ×3, drift v22→v23 through the existing version-pair matrix. Suite 1068
  green, analyze clean, linux debug build green. End-to-end eviction on a real
  play session: RUNTIME VERIFICATION REQUIRED.

## 2026-09-26 — Roadmap PR 2: dead native plugins dropped

- Area: `pubspec.yaml`, generated plugin registrants.
- Change: removed `app_links`, `audio_service_mpris`,
  `flutter_sharing_intent` (zero importers in `lib/` since deep linking became
  a no-op), plus their transitive `app_links_{linux,platform_interface,web}`
  and `gtk`. Registrants regenerated for linux/windows/macos; `ios/Podfile.lock`
  and `macos/Podfile.lock` stay stale until a macOS runner runs `pod install`.
- Correction to the plan: `flutter_native_splash` is **runtime**-critical
  (`main.dart` preserve/remove around the splash) — it must stay in
  `dependencies`.
- Gate: analyze + suite green, `fvm flutter build linux --debug` green. Android
  debug build not run here: RUNTIME VERIFICATION REQUIRED on an Android box.

## 2026-09-26 — Roadmap PR 3: mDNS discovery gated on enableConnect

- Area: `lib/provider/connect/clients.dart`.
- Change: `ConnectClientsNotifier.build` watches `enableConnect` and, when
  off, returns an empty state without constructing `BonsoirDiscovery` at all;
  toggling rebuilds the provider, so the live browser is stopped through the
  previous build's `onDispose`. `ConnectClientsState.discovery` is nullable;
  `resolveService` guards it. Kills the always-on multicast browsing that ran
  even with Connect off. `enableConnect` is now the master switch for
  discovery as well as broadcast — outbound control needs it on.
- Tests: `test/connect_clients_gate_test.dart` ×3 via fake
  `BonsoirPlatformInterface` + `DeviceInfoPlusLinuxPlugin`. Suite 1035 green,
  analyze clean.

## 2026-09-26 — Roadmap PR 1: download-status dedup, log guards, port rebind

- Area: download manager, playback proxy server, connectivity probe, Connect
  page, six dead files.
- Change: one `downloading` DB write per task instead of two (the claim owns
  it; the second could also revert a late cancel); per-request release logs in
  `server/routes/playback.dart` and the `sourced_track.dart` candidate dump are
  now `kDebugMode`-guarded; the reconnect probe skips `hidden` as well as
  `paused`; the random local-server port is retained-then-retried instead of a
  single `serve()` (Riverpod fires `onDispose` before rebuilds, so rebuild and
  fresh-bind are indistinguishable there); `local_devices.dart` memoizes the
  async-getter futures; six zero-importer files and the commented-out params in
  `form/text_form_field.dart` are gone.
- Tests: 4 new local files (write dedup via drift `QueryInterceptor`, port
  rebind ×5, probe lifecycle, hook-shape memoization). Suite 1032 green,
  analyze clean. Details and the interceptor caveat: `.ai/AUDIT_STATE.md`.

## 2026-09-25 — Browse search panel: keyboard-driven and grouped

- Area: `lib/modules/home/home_search_bar.dart`,
  `lib/modules/home/home_search_suggestions.dart`, `see_all_results_for` l10n.
- Change: the panel is now navigable without a mouse. Arrow keys move a
  highlight (`activeIndex`), Enter activates the highlighted row, Escape
  dismisses. Tapping and Enter share one path — `activateSuggestion` — and the
  panel emits every row through a single `onActivate`, so no row can carry a
  half-wired callback. Added group dividers, a "See all results for …" footer
  (the only row when a query matches nothing), a spinner for the live group
  while it loads, and `Scrollable.ensureVisible` so the highlight follows rows
  past the panel's 360px scroll extent.
- Load-bearing invariant: `suggestionRowsInPaintOrder` is the single source of
  truth for row numbering. The bar counts through it, the panel counts the same
  way as it emits (`nextSelected()`), so a row index cannot mean two things.
  Any new row group must be added in both places, in the same order.
- Tests: 4 new cases in `test/home_search_dropdown_nav_test.dart` (Enter opens
  the highlighted row, Escape dismisses without submitting, ArrowUp wraps onto
  the footer and submits the term, no-match footer submits). Suite 1015 green,
  analyze clean.

## 2026-09-24 — Automatic VPN committed, README refreshed, both pushed

- Validation before shipping: `fvm flutter analyze` clean, **932 tests green**
  (local `test/`, gitignored), `scripts/install-local.sh` built a release Linux
  bundle and installed it to `/usr/local/share/spotube-custom` (backup at
  `~/spotube-local-backup-20260924-204807.tar`).
- `cfbb7c2b feat(vpn)` put the whole uncommitted feature on `master` (11 new
  files, schema v21/v22, 32-locale l10n, Settings → Downloads UI,
  `docs/automatic-vpn.md`); `b80148bb docs` rewrote the README, which was 37
  commits stale since its 2026-09-22 rewrite (`9c91f66a`).
- README was missing: VPN gating, pinned playlists + sidebar reordering + docked
  player (`4efc85f6`), volume-control mode, the desktop perf pass, per-host fetch
  timing; and it claimed schema **v13** when the code is on **v22**.
- Note for future doc work: because `test/` is ignored, the published repo shows
  no tests at all while CI's `flutter test --coverage` gate passes on the empty
  set. README now says so instead of implying a clone can verify this.

## 2026-09-24 — VPN share-only tunnel devices (schema v22)

- Area: `preferences_table.vpn_device_name` (nullable, `schemaVersion`
  21→22, guarded step), `VpnConfig.deviceName`, gate helpers (UUID wins
  when both set), `RefCountVpnManager` device branch (wait bounded +
  cancellable, pin, never `bringUp`/`bringDown` by construction),
  generalized watch (`_watchedUuid`/`_watchedDevice`, recovery re-pins),
  `resolveVpnEndpoint(deviceName:)` (exact-device only, no fallback),
  `VpnConnectionDialog` (system/tunnel sections, tunnel filter =
  backend-verified ∪ hint match so Wi-Fi/Ethernet unselectable, "None"
  clears both), settings row shows the selection, `vpnDeviceNames()`
  manager passthrough.
- Why: provider-app VPNs (Proton/Mullvad/Nord-style) live outside
  NetworkManager, which the NM-only backend cannot see — user-reported
  gap. The device flow needs no backend at all (interface listing +
  pinning are pure Dart), so it works cross-platform incl. nmcli-less
  hosts; system state is never mutated on this path.
- Tests: 6 manager device cases (share/wait/timeout/loss+repin/
  precedence/NM-independence with `UnsupportedVpnBackend`), 4 resolver
  cases (exact wins, absent/addr-less fail closed, UUID flow intact),
  gate-matrix device rows, 2 download e2e (pinned device download,
  wait-for-tunnel). Full suite 932 green (incl. auto-expanded v21→v22
  migration pairs).

## 2026-09-24 — Optional automatic VPN for downloads/playback (schema v21)

- Area: `lib/services/vpn/` (new: manager, lease, nmcli/unsupported backends),
  `lib/provider/vpn/vpn_provider.dart` (new), `lib/models/database/`
  (preferences columns `vpn_mode`, `vpn_connection_uuid`,
  `vpn_auto_disconnect`, `vpn_wait_timeout_sec`; `schemaVersion` 20→21),
  `lib/provider/user_preferences/` (4 setters),
  `lib/provider/download_manager_provider.dart` (lease gate in
  `_downloadTrack` + `beforeAttempt` hook in `_chunkDownloadWithRetry`),
  `lib/provider/server/routes/playback.dart` (lease around upstream
  HEAD/GET only), `lib/pages/settings/sections/downloads.dart` +
  `lib/modules/settings/downloads/vpn_connection_dialog.dart` (new),
  `lib/main.dart` (read-only nmcli probe), `docs/automatic-vpn.md` (new).
- Why: opt-in qBittorrent-style "VPN active when downloading", using only
  the user's existing system VPN (NetworkManager on Linux). Default
  `disabled` = zero behavioral change: no lease, no probe, no polling.
- What changed: `RefCountVpnManager` reference-counts one shared connection
  (`acquire` → first lease connects, concurrent leases share, last release
  drops only Spotube-started connections); ownership snapshotted before
  `bringUp`, pre-existing connections never brought down; waits are bounded
  (configurable timeout) and race download cancellation (activation is
  undone best-effort); retry hook re-verifies against the live backend set
  each attempt (pause-and-wait, never clearnet fallback); return codes never
  trusted without active-set verification; no credentials handled or stored.
- Decisions: downloads-first integration with playback upstream gated behind
  the same lease API; local-file/cache serving takes no lease; failures are
  explicit (`VpnException` taxonomy → download `failed` / HTTP 500), never
  silent; non-Linux and nmcli-less hosts report Unsupported and fail closed.
  Not a kill switch — documented as app-level gating only.
- Tests: `test/vpn_manager_test.dart` (22: states, leases, ownership,
  races, loss/recovery, nmcli parser, gate matrix),
  `test/vpn_download_test.dart` (7: disabled passthrough, shared, owned,
  concurrent sharing, cancel-during-wait, unsupported fail-closed,
  loss-pauses-retry). Migration suite covers v20→21. Full detail in
  `docs/automatic-vpn.md`.

## 2026-09-24 — VPN socket pinning (no schema change)

- Area: `lib/services/vpn/{pinned_client,vpn_pin}.dart` (new),
  `lib/collections/http-override.dart` (allowlist rule extracted to a
  shared static), `lib/services/vpn/vpn_{backend,manager,manager_impl}.dart`
  (`vpnDeviceNames` seam, pin lifecycle: establish/refresh/clear/read),
  `lib/provider/vpn/vpn_provider.dart` (`VpnPinHolder` wiring), the three
  Dio instances (download, playback upstream, `globalDio`) get an
  `IOHttpClientAdapter(createHttpClient:)` with the pinned factory.
- Why: qBittorrent-style hardening without interface binding, which Dart
  cannot do (verified: no `SO_BINDTODEVICE` in the SDK, no source-address
  knob in Dio). Every link verified instead: `Socket.connect(...,
  sourceAddress:)` + `SecureSocket.secure` + the documented
  `ConnectionTask.fromSocket` seam; Dio calls `createHttpClient` once and
  caches, so the factory reads the pin live per connection; connect
  timeouts are Dio-enforced regardless of factory; the SDK's 3-arg→1-arg
  cert adaptation is mirrored around the shared allowlist rule.
- What changed: while a lease is held, Dio sockets bind their local end to
  the tunnel address (resolved per acquire, refreshed after every wait);
  unresolvable pin fails acquisition closed and undoes owned activations;
  proxied requests under a pin throw instead of bypassing; no pin means a
  byte-identical default client. Out of reach by construction: Hetu HTTP,
  engine subprocesses, image-cache fetches, system DNS.
- Tests: `test/vpn_pinning_test.dart` (6: loopback plain/TLS pinned + real
  openssl certs, unpinned delegation, unroutable fail-closed, proxy
  refusal, cert parity), pin lifecycle cases in `test/vpn_manager_test.dart`
  (5), fail-closed e2e in `test/vpn_download_test.dart` (gated downloads
  now run genuinely pinned to loopback) plus `isVpnProtectionError`
  fail-fast classification (Dio normalizes factory throws to `unknown`,
  which the retry loop would otherwise pointlessly retry). Full suite 898
  green.
- Not claimed: packet-level (tcpdump) verification still open — docs say
  "reduces exposure", never "kill switch".

## 2026-09-23 — Downloads become state; playlists mirror Spotify (schema v16)

- Area: `lib/models/database/tables/{track_download,playlist_download,playlist_download_mirror}.dart`,
  `lib/services/downloads/download_store.dart`,
  `lib/provider/download_manager_provider.dart`,
  `lib/provider/playlist_download_provider.dart`,
  `lib/provider/track_options/track_options_provider.dart`,
  `lib/components/track_tile/track_options.dart`,
  `lib/components/track_presentation/presentation_actions.dart`,
  `lib/modules/player/player_actions.dart`, `lib/pages/playlist/playlist.dart`,
  `lib/pages/library/user_playlists.dart`.
- Why: downloads were fire-and-forget. `build()` returned `[]`, so a restart lost
  every completed file, every partial, and the fact that a file existed at all;
  nothing recorded which playlist a download came from; and "is this downloaded?"
  was answered by scanning local tracks and comparing title, album and artists —
  which a rename defeated and which cost grew with the library.
- What changed: three tables, and the split between them is the feature.
  `track_download_table` is one row per owned file keyed by the Spotify track id;
  `playlist_download_table` is membership (`playlist_id`, `track_id`, `position`);
  `playlist_download_mirror_table` is one header per playlist the user chose to
  mirror. A track in three playlists is therefore three membership rows and one
  download row — "never download twice" is a uniqueness constraint, not a rule.
  `addToQueue`/`addAllToQueue` collapse into one `_enqueue` (closing the hole
  where a batch re-queued whatever was in flight) and take the `collectionId`
  every call site already had and dropped. `_setStatus` stays the only writer of
  status and now persists its winner unawaited, refusing `canceled → completed`
  in Dart *and* in SQL. `reconcilePersisted()` at startup makes
  `queued|downloading` read as `interrupted` and a vanished file as `missing`.
  Per-row state comes from `downloadStateOfProvider`, replacing both name-match
  scans; `PlaylistMirrorService` re-syncs membership on open, in the background,
  gated on a mirror row existing.
- Decisions: full membership is stored, not just downloaded rows; pre-existing
  files are adopted lazily and get no playlist; syncing happens on open rather
  than on a timer; **no code path deletes an audio file** — losing a membership
  drops a row, never a file. Playlists are matched by id only, so renaming one
  keeps its downloads and renaming a track keeps its file.
- Evidence tier: 27 tests across `download_persistence_test.dart`,
  `playlist_reconcile_test.dart`, `download_playlist_dedup_test.dart` and one new
  `track_options_select_test.dart` case; 647 green, analyze clean. The v15→v16
  migration was driven on a copy of the real 2 MB `db.sqlite` — twelve tables at
  identical row counts, and both `@TableIndex` entities present, which drift's
  `Migrator.createTable` does not create for you.
- Deviation from plan: a scan-and-backfill of already-downloaded files is
  impossible, not merely undesired — `toMetadata` writes no Spotify id into the
  file, so nothing maps a file back to a `trackId`. Lazy adoption replaces it.

## 2026-09-23 — Metadata fetch latency: crash, unbounded requests, lost candidate key

- Area: `lib/services/sourced_track/source_resolver.dart`,
  `lib/provider/metadata_plugin/utils/rate_limit_gate.dart`,
  `lib/services/metadata/errors/rate_limit.dart`,
  `lib/services/sourced_track/sourced_track.dart`,
  `lib/services/youtube_engine/*`, `lib/provider/server/routes/playback.dart`,
  `lib/provider/metadata_plugin/utils/paginated.dart`,
  `lib/components/fallbacks/error_box.dart`, `lib/l10n/`, `lib/services/dio/dio.dart`,
  `lib/provider/server/sourced_track_provider.dart`.
- Why: "sometimes it takes too long to fetch data from Spotify and music". Three
  confirmed defects with runtime evidence — the fallback cascade crashing on every
  production call, metadata requests bounded by nothing at all, and every
  `SourcedTrack` rebuild path dropping the key that lets the cascade skip the
  candidate already playing. Diagnosed read-only first; details in
  `.ai/AUDIT_STATE.md`.
- What changed: `SourceResolutionAttempt` (a typedef both `attempt` and `resolve`
  are checked against, so the arity bug cannot compile again),
  `metadataRequestBudget` = 15 s applied to every `runGated` attempt, and one
  `sourceCandidateKey:` line on each rebuild path. Then the cascade ceilings:
  `sourceCandidateBudget` 20 s per candidate, `engineCallBudget` 15 s per engine
  call (`withinEngineCallBudget` in `lib/services/youtube_engine/`, plus cleanup in
  `_runMethod`), `fallbackCascadeBudget` 45 s returning a partial list, and
  `ServerPlaybackRoutes.fallbackUrlsFor` — a 5 s / 16-entry memo so HEAD and GET no
  longer each walk the cascade for one dead URL. Saved lists became
  stale-while-revalidate in `SavedListCacheMixin`: the snapshot is the build
  result and the network refresh patches `state` behind it. Finally the two
  closing pieces: `isCredentialError` + a `spotify_login_expired` `ErrorBox`
  message (401/403 named as a credential problem, never fed to the rate-limit
  gate), and latency instrumentation across every path this plan touched —
  `metadata.request`, `source.resolve`, `engine.*`, `playback.fallbackCascade`
  and a `_TimingInterceptor` recording `dio.<host>` on the previously
  interceptor-free `globalDio`.
- Evidence tier: 3 new production-shape fallback tests + 3 candidate-key tests,
  each proven red before its fix; `runGated` gained 3 budget tests, also red
  before (without the timeout the request hangs until the test framework's own
  30 s limit — the production symptom reproduced). The memo gained
  `test/playback_fallback_memo_test.dart` (3 cases; red without it: 6 counted
  searches per track start instead of 3). Stale-while-revalidate gained 2 cases
  in `test/library_snapshot_test.dart` (red before: a held probe made the build
  wait out its whole 15 s budget and end on the stale list). 401 classification
  gained 4 cases in `test/rate_limit_test.dart`, and instrumentation
  `test/dio_instrumentation_test.dart` (3 cases; red before: removing the
  `_record` call from `onError` made a failed request time as nothing). The
  counters gate no behaviour — the file's own rule, and the reason their tests
  assert only that a counter fires.
  587 → 604 passing, then 605 after the follow-up below.
- Same-day follow-up, shipped as its own commit: the Phase 3 engine ceiling had
  cast the *future* instead of the awaited value at two yt-dlp sites, which
  threw on every manifest and stopped playback — 9 times in one session log,
  with 604 tests green. Found by installing the release build and reading the
  log, fixed by casting inside an `async` closure, and fenced by
  `test/engine_call_budget_test.dart` (bans `as Future<` under
  `lib/services/youtube_engine/`; names both broken lines against the old
  build). Verified live afterwards: zero cast errors and three real
  `source_match_table` rows written by the new build.
  **Rule taken from it: a change under `lib/services/youtube_engine/` is not
  done until a release run has resolved a track.**
- Deliberately not done: the planned 45-site `hetuInvoke` wrapper (`runGated` is
  the one choke point all gated reads share, so the surface is smaller and auth
  and POST paths stay untouched), and the plugin-side `HttpBaseOptions` change,
  which compiles but is uninstalled until approved. `.timeout()` abandons rather
  than cancels the in-VM request — see the audit entry.

## 2026-09-22 — Plugin index: one dead registry no longer empties the list

- Area: `lib/provider/metadata_plugin/core/repositories.dart`,
  `lib/pages/settings/metadata_plugins.dart`.
- Why: a phone install showed only the two bundled plugins, with an "Available
  plugins" section that was silently empty. GitHub and Codeberg were awaited as
  one `Future.wait`, so either host being unreachable rejected the whole index,
  and the page renders an `AsyncError` as `[]`. Also fixed a key mismatch
  (`api.github.com` written, `github.com` read) that made the exhausted-source
  skip a no-op for GitHub, and `.any()` short-circuiting before the second host
  was recorded.
- Evidence tier: 6 unit cases in `test/plugin_index_partial_failure_test.dart`
  against a fake `HttpClientAdapter`, including the regression itself (codeberg
  down → GitHub's items still returned) and the all-down case staying an error.
- Baseline note for the smoothness work: the install the user was testing was
  `app-stable-debug.apk` (JIT, assertions on, ~201 MB). PR 11's counts stand, but
  any frame-time judgement needs the release build — rebuilt as
  `flutter build apk --release --flavor stable` in the same pass.

## 2026-09-22 — Android frame-pipeline pass (PR 11)

- Area: `lib/provider/glance/glance.dart` + new `lib/utils/foreground_coalescer.dart`,
  `lib/modules/root/spotube_navigation_bar.dart`, `lib/provider/blacklist_provider.dart`
  + `lib/components/track_tile/track_tile.dart`,
  `lib/components/playbutton_view/playbutton_card.dart`, and new
  `lib/provider/scroll_motion.dart` + `lib/components/scroll_motion_scope.dart`
  (installed in `lib/main.dart`'s router builder).
- Why: "the android app is not working as smoothly as it should" — scrolling,
  the player sheet, playback, general heaviness. Each of the five changes removes
  work that happened **per frame or per second on the device**: a 1 Hz
  platform-channel widget push, a whole nav-bar rebuild per sheet-drag frame, a
  blacklist table scan per row, four controllers per grid card whose target was
  constant on touch, and a `BackdropFilter` re-blurring moving content.
- Evidence tier: **counts, not milliseconds.** No Android device, AVD or adb on
  this host, so nothing here is a frame-time measurement; the four tests named in
  `.ai/PERFORMANCE.md` "Android frame-pipeline pass" measure notifications,
  channel pushes, controllers mounted and `BackdropFilter`-affecting state flips,
  each with a negative control. Full suite green (525) and `analyze` clean.
- Behavior contracts deliberately kept: frosted chrome still blurs at rest and
  returns 400 ms after motion stops (the user's choice was "keep blur,
  repaint-cache it", not "kill blur on mobile"); the desktop hover fade on grid
  cards is unchanged and asserted; a hidden overlay button keeps its slot, so the
  play button does not jump while a card loads.
- Test-calibration side effect: `test/player_membership_test.dart`'s 100×100 gate
  flaked at 1.6–2.4x against its own 2x budget on an idle machine; the small case
  now asserts "never slower" and the 2x claim rests on 1000×1000 (17x).

## 2026-09-21 — Sidebar bottom reservation now follows UI scaling

- Area: `lib/modules/root/sidebar/sidebar.dart`. `if (lgAndUp) const Gap(130) else
  const Gap(65)` became `Gap(sidebarBottomClearanceOf(context))`, which is
  `(lgAndUp ? 130 : 65) * context.theme.scaling`. Identical to the old numbers at
  scaling 1; at 1.5 the reservation grows to 195/97.5 with the player instead of
  staying behind it. Test: `test/sidebar_footer_clearance_test.dart`.
- Why scaling: the player is built from paddings, icons and text that all ride
  `theme.scaling` (which Spotube feeds from the theme plugin's `density`,
  `lib/main.dart:444`), and `root_app.dart:54-60` already scales its own bottom
  inset the same way — the sidebar's literals were the outlier.
- Measured live, debug build: the player is ~103px tall at scaling 1 and ~172-179
  at scaling 1.5 (908px and 1808px wide), so 130/195 clear it. The settings gear
  was visible above the player in all three shots, with 0 layout errors in the run
  log. Sub-820px could not be driven: Hyprland `resizeactive`/`resizewindowactive`
  had no effect on the tiled window, so that branch rests on the unit test.
- The plan was to read the player's real height instead of scaling a constant, and
  that turned out to be impossible here: shadcn's footer-to-body `MediaQuery`
  publication never fires under Flutter 3.35, and `ScaffoldFooterPadding` throws a
  type cast. Evidence in `AUDIT_STATE.md`, "Anything placed in the scaffold footer…".
- Seen but not fixed (out of scope): `SidebarFooter`'s unscaled `Container(width:
  180)` wraps its labels mid-word at scaling 1.5 ("Downlo/ads", "Device/s").

## 2026-09-21 — `ThemeLayout` shell switches: built, then reverted

- Added a `layout` block to the theme contract (`chrome: inset`, `nav: rail`,
  `progress: below`) with host-side rendering in `root_app.dart`, `sidebar.dart`
  and `bottom_player.dart`, so a theme plugin could pick a shell shape. Reverted
  at the user's request — the app keeps the shell it shipped with.
- Kept for the record: the theme ability's whole surface is `getTheme()`
  returning data. A plugin can never ship widgets, so any "make it look like X"
  request has to be answered by the host implementing switches first. That is a
  lot of app-chrome surface for one plugin's aesthetic.
- What actually broke while verifying, and why: the `nav: rail` switch decoupled
  the sidebar's shape from the breakpoints that normally decide it. `lgAndUp` is
  `width > 820` and `mdAndDown` is `width <= 820` (`lib/extensions/constrains.dart:5-11`)
  — the same boundary — so in the shipped code the icon rail and the 180px-wide
  `SidebarFooter` can never co-occur. Forcing the rail at 908px left the wide
  footer in place, and tying the bottom reservation to the switch rather than to
  `lgAndUp` dropped it from `Gap(130)` to `Gap(65)`, which is what pushed the
  settings row under the player. Not a pre-existing defect; my edit created it.
- The black screen had a separate cause worth remembering: shadcn measures the
  scaffold footer with `getMaxIntrinsicHeight`, so moving the seek bar into a `Row`
  with an `Expanded` `Slider` put a `LayoutBuilder` in the footer subtree, threw
  `LayoutBuilder does not support returning intrinsic dimensions`, and the whole
  window painted nothing. See `AUDIT_STATE.md`.

## 2026-09-21 — Theme-plugin layout tokens, phases 0-1 (landed, uncommitted)

- Area: theme contract + card/grid layout. New capability, no behavior change at
  the defaults (asserted explicitly in `test/theme_layout_tokens_test.dart`).
- `ThemeDefinition` gained `tokens` (card widths/heights, gutter, `fontFamily`);
  `density` and the `radius` scale stopped being parsed-but-ignored — density
  rides `AdaptiveScaling.only(sizeScaling/textScaling)`, `radius.small` rounds card
  covers, `fontFamily` overrides shadcn's `sans`/`base` typography.
- Sanitizing moved to `lib/services/metadata/theme_sanitizer.dart` and is now the
  single gate on all three theme-producing paths (plugin endpoint, shell palette
  merge, warm-start cache read). Previously only the endpoint path clamped, so a
  cached or shell-merged definition reached layout unchecked; non-finite values now
  fall back instead of poisoning constraints.
- `AppLayout`/`AppLayoutX` replaces the per-page 150/180/200/225/250/8/10/12
  literals; `components/playbutton_view/card_extent.dart` folded into it. Cell
  heights carry min-content guards, so a theme cannot re-create the 3px clip.
- Cost: one `InheritedWidget` below the app theme with an `==`-guarded notify, and
  a handful of double multiplications per grid build. No new providers, no new
  rebuild triggers, nothing per-frame.
- 14 new tests; 427/427 green, analyze clean, debug build relaunched with 0
  overflow lines.

## 2026-09-21 — `containsTracks` defect fixed (landed, uncommitted)

- Area: queue membership / playback commands. Behavior change, authorized by the
  user after it was reported.
- `AudioPlayerState.containsTracks` (`state.dart:112`) shadowed the state field
  with its parameter, so the predicate collapsed to `needles.isNotEmpty` and every
  caller read its own tracks as "the queue that is playing". Folder/playlist
  **Play**, **Shuffle play** and **Add to queue** therefore short-circuited and did
  nothing. The parameter is now `needles` and the method delegates to
  `listContainsTracks(tracks, needles)`.
- Call sites affected: `local_folder.dart:59,79,97` and `top_tracks.dart:69`
  (remote-device path; `queueProvider` is `StateProvider<AudioPlayerState>`, so the
  intended semantics are the same).
- Verified in the release build, not just by test: Downloads Play loaded the queue,
  switching to Cache folder loaded that instead, Downloads **Add to queue** appended
  516 tracks (drawer header "548 tracks in queue"). The header control correctly
  flipped to stop and Shuffle/Add-to-queue correctly went disabled when the queue
  really was the folder — the positive case PR 6 could not observe.
- 6 new tests in `test/player_membership_test.dart`; 344/344 green, analyze clean.

## 2026-09-20 — Verified optimization roadmap, PR 1–6 (landed, uncommitted)

- Area: instrumentation, history aggregation, queue persistence, playback proxy,
  position-tick fan-out, artwork decode, queue-membership scans.
- PR 1 added `PerfCounters` (`kPerfCountersEnabled`, env `SPOTUBE_PERF_COUNTERS`)
  and the synthetic fixtures the benchmarks below run on; PR 2–5 are documented
  in `.ai/PERFORMANCE.md` under their own headings.
- PR 6 (`C6` + `C8`): `UniversalImage.imageProvider` now honours `width`/`height`
  on the file branch via `ResizeImage(fit, allowUpscaling: false)` — sized local
  artwork went from 4.0 MB to 25.6 kB per 80×80 cover, so 20 covers no longer
  consume the entire 100 MB `ImageCache`. `AudioPlayerState.listContainsTracks`
  indexes the queue into `localPaths`/`remoteIds`/`allIds` sets that reproduce the
  existing pair rule, 43× faster at 1000×1000, and still scans below a 256-pair
  threshold so the single-needle case pays nothing extra.
- Four further candidates were measured and **rejected** (theme-background
  resize, `directorySize` single pass, `presentation_list` selection scan,
  `isDownloaded`) — see `.ai/PERFORMANCE.md` before retrying any of them.
- One real defect found — `AudioPlayerState.containsTracks` ignored the queue
  (`state.dart:112`), making folder/playlist Play, Shuffle play and Add to queue
  no-ops. Reported rather than applied during the pass (it changes user-visible
  behavior); fixed the next day, see the 2026-09-21 entry.
- Tests: `universal_image_source_test.dart`, `player_membership_test.dart` (new)
  plus the PR 1–5 suites. `fvm flutter analyze` clean, 338/338 tests green at the
  time, `fvm flutter build linux --release` green.

## 2026-09-20 — Correctness remediation pass (audit items 1–16)

- Area: playback cache, plugins, downloads, proxy, sources, history, server
  lifecycle, logging, local library.
- Changes (all covered by tests or explicit source verification):
  - Mirrored cache writes now go through `PlaybackCacheMirror`
    (`lib/services/playback_cache_mirror.dart`): only sequential 200/complete
    206 ranges mirror, a short/oversized body aborts into `.part` abandonment,
    and an upstream error is surfaced instead of being swallowed by `onDone`.
  - Plugin cache made public `PluginVmCache` with eviction on failed create and
    on add/update/remove (`metadata_plugin_provider.dart`); resolver keys
    candidates by `(config, version)`.
  - Download cancellation: fresh `CancelToken` per retry, `_setStatus` guarded by
    token identity so a stale worker cannot stomp a re-queued task
    (`download_manager_provider.dart`); `chunkDownload` no longer deletes a
    previously completed file when an attempt fails before touching the target
    (`lib/extensions/dio.dart`).
  - Proxy fidelity: per-request `Host` header, `android` removed from the signed
    client pool (`routes/playback.dart`).
  - `getStreamOfQuality` degrades to another stream in the same container
    instead of throwing when a quality/container disappears; a throwing or hung
    validation candidate is skipped rather than poisoning the whole set
    (`sourced_track.dart`, `validation.dart`).
  - `localTracksProvider` watches a joined location key (drift compares list
    fields by identity) — an unrelated preference write no longer rescans the
    library; embedded artwork now degrades (unknown MIME → `.jpg`) and its temp
    name carries a path digest, so same-basename files stop sharing a cover.
  - History: single JSON parse per row via `ParsedHistoryTrack`, artist counter
    moved to SQL `json_each`, initial-listener events buffered; next-track
    prewarm has a re-entrancy flag and a 15 s per-track cooldown.
  - Server: rebinds serialized through `_rebindChain`; connect pairing is
    fail-closed without a navigator context and a grant is pruned with its
    socket; `useGlobalSubscriptions` cancels the connectivity position
    listener; `AppLogger.logFile` resolved lazily so a startup error can no
    longer hit an uninitialized `late final`.
  - Sleep timer cancels the previous timer before re-arming; unreachable
    `ConnectionCheckerService.didChangeAppLifecycleState` removed and the
    singleton's two subscriptions cancelled in `dispose()`.
- Tests: 283 pass (`fvm flutter test`), `fvm flutter analyze` clean. New files:
  `playback_cache_mirror_test`, `plugin_lifecycle_test`, `download_cancel_test`,
  `source_quality_fallback_test`, `local_library_rescan_test`,
  `local_artwork_test`, plus added cases in `chunk_download_test`,
  `download_first_playback_test`, `stream_validation_test`,
  `position_throttle_test`.
- Contract change to remember: `filterValidBounded` no longer propagates a
  candidate's throw or timeout — it drops that candidate.

## 2026-09-19 — Hetu plugin VM caching + lazy playback fallback

- Area: Source resolution / playback / plugins
- Files: `lib/services/sourced_track/source_resolver.dart`,
  `lib/provider/server/routes/playback.dart`
- Problem: Source fallback rebuilt a fresh Hetu VM per stream request → RSS
  climb and repeated module compiles.
- Change: Global per-`(config, engine)` plugin VM cache; playback HEAD/GET
  fallback made lazy; theme plugin VMs memoized; resolver reuses
  `audioSourcePluginProvider`.
- Measured result: `to compile` flat; RSS plateaus (~573–725 MB) instead of
  climbing.
- Tests: full suite green.

## 2026-09-19 — Lyrics sync rewrite + Better Lyrics provider

- Area: Lyrics
- Files: `lib/modules/lyrics/use_synced_lyrics.dart`,
  `lib/pages/lyrics/synced_lyrics.dart`, `lib/provider/lyrics/synced.dart`,
  `lib/services/lyrics/better_lyrics_provider.dart`,
  `test/better_lyrics_provider_test.dart`
- Problem: Highlight desynced from music (exact-second map lookups).
- Change: Binary-search active line (index-based); added Better Lyrics (Apple
  Music TTML) provider after LRCLib; removed dead `syncedLyricsMapProvider`.
- Measured result: synced highlight tracks position continuously.
- Tests: 8 new tests; suite 238 green.

## 2026-09-19 — Initial AI context system

- Area: Tooling
- Files: `AGENTS.md`, `.ai/*`
- Problem: no persistent AI project knowledge.
- Change: created persistent context (architecture, audit state, performance,
  conventions, changelog, todo) + `scripts/ai-context` summary.
- Measured result: n/a.
- Tests: n/a (docs only).