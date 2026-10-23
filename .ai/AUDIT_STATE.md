# Audit State

Persistent state of performance/architecture investigations. Populate from real
evidence only. This is the file future agents must check before reinvestigating.

## Completed

### v3 theme host + obsidian compact/seek pass — 2026-10-23/24
- **Scope closed**: host renderer, slots/screens, bindings/actions, assets/fonts,
  stage player, background and splash branding are implemented under
  `lib/modules/theme_ui/` and consumed by root/sidebar/home/bottom player.
- **Seek**: `progress` now supports tap and horizontal drag. Stage and docked
  bars were observed staying in sync at 2:49 after a wide tap and at 2:31 after
  a 700 px tap. The node deliberately avoids `LayoutBuilder` because the
  scaffold footer asks for intrinsic dimensions.
- **Compact**: no RenderFlex overflow at 908×1038 or 700×1038 after the hero and
  `player.leading` became `expanded` and volume hides below 800 px of actual
  player width. The horizontal rail replaces labels below the breakpoint and
  the overlay player is used below 820 px.
- **Saved-library refresh**: a refresh that resumes after Riverpod invalidates
  the notifier was still reading `rateLimitGateProvider` and
  `metadataSessionRefresherProvider`. `primeMetadataPlugin` now captures the
  plugin future, gate and refresher together; the runtime startup logs
  revalidate all four saved lists with no `_didChangeDependency` assertion.
- **Known limits**: `layout.responsive`, entry ordering, home/settings section
  lists, `titlebar` and `enforce` are model-validated but not host-consumed.
  Hyprland continues to report `Spotube` even though GTK's `getTitle()` returns
  the theme's `Obsidian` (compositor/GTK CSD issue; native title-bar change was
  reverted). Splash branding is code-complete but the theme gate usually
  dismisses the splash before the window maps, so it was inspected rather than
  captured.

### Radio -> music switch aborted the process — libmpv's wakeup callback outlived its Dart side — fixed 2026-10-23
- **Symptom**: playing a radio station and then starting any music track
  killed the app outright (SIGABRT, no Dart stack). Two core dumps from the
  installed build are on this machine (`coredumpctl list spotube`,
  2026-10-22 22:45).
- **Crash signature**: `abort` <- `dart::Assert::Fail` <-
  `DLRT_GetFfiCallbackMetadata`, on an mpv thread: a `dart:ffi`
  `NativeCallable` was invoked after it had been closed.
- **Root cause**: the `media_kit` pin (`d310049`, v1.2.1) closes libmpv's
  wakeup `NativeCallable` in `InitializerNativeCallable.dispose`, but only
  schedules `mpv_terminate_destroy` 5 s later. A radio -> music switch stops
  radio, which disposes the dedicated radio `Player`; libmpv's event thread
  could fire the closed callback inside that window.
- **Fix**: pin bumped to `8ce5e0a497d61181c9f46b53372528e195b3b5ae`
  (upstream "fix flutter338 crash", the next commit after the old pin). Its
  entire repo delta is +5 lines: `mpv_set_wakeup_callback(ctx, nullptr,
  nullptr)` before `close()`. No app code changed.
- **Not the radio provider caches**: the browse cache work in fork.7 is
  unrelated — *any* `Player.dispose()` on the old pin has this window. The
  music player is a singleton (never disposed), so only the radio player's
  per-session dispose exposed it.

### A re-read that was thrown away every time — the library never synced — fixed 2026-10-22
- **Symptom**: a playlist created on one device never appeared on another,
  while the liked tracks did. The library was re-read over and over and
  never took the answer.
- **The root cause was a one-way latch.** `SavedListCacheMixin` marks a list
  "discarded" in `ref.onDispose`, so a re-read that is in flight when the
  list's build is replaced throws its result away (the replacement build
  would overwrite it). Riverpod fires a build's `onDispose` when that build
  is replaced — and the flag was **never cleared for the build that
  replaced it**. So after the second build the instance was "discarded" for
  the rest of its life, and *every* later re-read was discarded at the exact
  moment it had the answer.
- **Why the liked list worked and the playlists list did not**: the liked
  provider is auto-disposed and gets a fresh instance (a fresh, unlatched
  flag) every time it is invalidated; the playlists, albums and artists
  providers keep their instance across the rebuild, so they kept the latch.
  Same code, different lifetime — which is why only one of the four
  misbehaved.
- **Fix**: `_discarded = false` at the start of every build.
- **Three more defects on the same path, all fixed**:
  1. **The auth provider re-published its answer on every auth event** (a
     token refresh included), which rebuilt every provider watching it — the
     saved lists among them. On a rejected token that looped: read → 401 →
     refresh the token → rebuild → read → 401 → … The library never
     settled. The auth state now only changes when the *answer* changes.
  2. **The plugin answered "not signed in" until it had read its stored
     credentials**, and the host published that as the truth and corrected
     it a moment later. The plugin now reports when its credentials have
     landed (`auth.isLoaded()`), and the host waits for that before
     answering.
  3. **A rejected token was never refreshed.** The plugin only refreshes at
     the token's *stated* expiry, but Spotify invalidates tokens before
     that — so the app stayed 401-ing (with a stale library) until the user
     signed in again, and a restart did not help either. A 401 now
     refreshes the session from its stored cookies and retries once
     (`metadataSessionRefresherProvider`, a seam so a test can stand in).
- **Also fixed**: the playlist *create* no longer dies on a throttled
  read-back (plugin 0.2.11 — the read-back was the last step of the
  create, so a 429 reported a successful creation as a failure and the
  playlist never appeared); a create that reports a failure now looks for
  the playlist it actually made and adopts it; the library-repair write goes
  through the rate-limit gate; and the "your playlist did not reach the
  library" warning uses the root navigator's context (the dialog's own
  `ToastLayer` dies with the dialog, so the warning was silently dropped).
- **Evidence it works**: the on-device log of the test machine now reads
  `[library] savedPlaylists: 61 rows, 7 new, complete=true` — the seven
  playlists created on the other device during the test, picked up by the
  startup re-read.
- **Every re-read is logged** (`[library] <list>: N rows, M new`) — the
  release log file otherwise only receives error reports, so a re-read that
  silently did nothing left no trace.
- **Do not reinvestigate** "the playlist did not appear" without a log
  excerpt: the `[library]` lines in Settings → Logs say what the re-read
  found.

### The library-write repair was invisible and unretried — fixed 2026-10-22
- **Found while chasing "liked syncs, playlists do not"** (the liked list always
  worked: its provider is autoDispose and Spotify orders liked tracks newest
  first, so the page-one probe always saw a new like; the playlists list was
  the broken one).
- **Evidence the sync itself works**: on the test device the saved-playlists
  snapshot contained the newly created playlist after the startup sync, and
  the playlist was in the account's library — so both the read and the
  library write had landed.
- **Bug 1 — the warning could never be seen.** The create dialog puts a
  `ToastLayer` around *itself* (`showPlaylistDialog`), and the
  "your playlist did not reach the library" warning only arrives after the
  network has answered — by which time the dialog is popped and its context
  (and its toast layer) are gone. The warning was therefore silently
  dropped, which is the worst possible outcome: the one message that
  explains the exact symptom never reached the user. Fixed to use
  `rootNavigatorKey.currentContext`, which lives under the app's own
  `ToastLayer` (the one `ShadcnApp` installs) and never dies.
- **Bug 2 — the repair's write was not behind the rate-limit gate.** The
  library write (`playlist.save` → `addItemsToRootlist`) was a bare plugin
  call. This account is throttled by Spotify often enough that an unretried
  429 lost the write silently — and a playlist that is not in the library is
  in no device's library. It now goes through `runGated` with the bounded
  cooldown retry like every other metadata write.
- **Bug 3 — the failure had no trace.** The release log file only receives
  error reports, so a failed repair left nothing to look at. It is now
  reported as an error too, which puts it in **Settings → Logs** on the
  device — the only place a release build shows it.
- **Do not** try to fix "the playlist did not appear" by re-reading the
  library harder: the read and the write both land. Look at Settings → Logs
  for the library-membership error first, then check whether the device runs
  a build that predates the sync (the liked list working is *not* evidence
  that the build is new — that list always worked).

### A release APK failed to compile on a stale plugin registrant — fixed 2026-10-22
- **Symptom**: `make apk-arm64` died at `:app:compileStableReleaseJavaWithJavac`
  with `package dev.flutter.plugins.integration_test does not exist`.
- **Cause**: `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
  is generated **per build mode**. The Flutter tool filters dev dependencies out
  of it for a release build (`injectPlugins(releaseMode: …)` in
  `flutter_tools/lib/src/flutter_plugins.dart`), but a *debug* build's version
  registers `integration_test` — and the release classpath does not contain that
  package, because Flutter's Gradle plugin strips dev dependencies from the
  release variant (`PluginHandler.configurePluginProject`: `buildType.name !=
  "release"`). A **stale debug registrant** therefore fails the release
  compile.
- **Why it was stale**: the tool only rewrites the file when it regenerates the
  platform tooling, which it does not always do (a skipped `pub get` skips it
  too). The file on disk was left over from a debug build.
- **Fix**: the release APK targets now delete the registrant first
  (`make clean-android-registrant`, called by `apk` and `apk-arm64`), so a
  release build always regenerates it in release mode. Deleting it is safe:
  the tool rewrites it before Gradle runs, and a build that somehow did not
  would fail loudly instead of shipping an app with no plugins registered.
- **Do not** "fix" this by moving `integration_test` out of `dev_dependencies`
  or by adding it to the release classpath — the first breaks the
  `integration_test/` smoke test, the second ships test code to users.

### A playlist created on one device never reached the other — fixed 2026-10-22
- **Symptom**: same account on two devices; a playlist created on one did not
  show on the other, although Spotify showed it.
- **Creation was never the problem.** `MetadataPluginPlaylistNotifier.create`
  → the plugin's `create` → `POST /playlist/v2/playlist` → `follow`
  (`addItemsToRootlist`) → `changePermission` → `getPlaylist`. The playlist was
  in the account's library rootlist.
- **The reading side never asked again.** `metadataPluginSavedPlaylistsProvider`
  is a plain `AsyncNotifierProvider`; `buildSavedList`'s stale-while-revalidate
  runs **only inside `build()`**, so the list was fetched once per app session.
  The always-mounted sidebar (`sidebarPlaylistIndexProvider` →
  `lib/provider/sidebar/sidebar_provider.dart:100`) builds it at startup, which
  froze the list at startup. The complete set of invalidations was:
  pull-to-refresh (`user_playlists.dart:181`), the error-box retry (`:174`),
  `delete()` (`playlists.dart:154`) and login/logout (`core/auth.dart:24`).
  **Nothing** invalidated it on app resume, connectivity restore, window focus,
  a timer, or the Playlists page being opened.
- **Three contributing defects, all fixed**:
  1. `persistSnapshot` refused to write a list that was still paging, so a
     library with more rows than fit on one page had **no snapshot at all**, and
     the optimistic insert after a create never reached the disk either.
  2. The cold path loads only page one (`fetch(0, 20)`), and Spotify *appends*
     a new playlist to the **end** of the library — so it sat on page 2+.
  3. `_revalidate`/`_revalidateAll` bail on `!identical(state.value, served)`,
     but the framework assigns `state` one microtask *after* `build()` returns:
     a revalidation resolving in the same microtask batch compared against a
     still-null `state.value` and threw its fresh result away, with no log.
- **Fix**: `SavedListCacheMixin.refresh()` + `SavedLibraryRefresher`
  (`lib/provider/metadata_plugin/library/library_refresh.dart`, 1-minute shared
  cooldown per list) wired to **app start**, app resume, window focus,
  connectivity restore, the Playlists page being opened and a 10-minute
  foreground heartbeat. All four saved lists are in it — playlists, liked
  tracks, saved albums, followed artists — each at the depth it needs: the
  playlists/albums/artists lists walk every page (they are small, and a new
  playlist is *appended* to the end of the library), the liked-tracks list is
  probed only (thousands of rows, and a new like lands at its head).
  A re-read costs **one request** in the common case: a page-one probe says
  whether the library moved, and only then are the rest of the pages read.
  Snapshots now carry a `complete` flag
  (`{"v":2,"complete":bool,"items":[…]}`, same column, no migration; a v1 bare
  array still reads as complete). Creation is verified against the library and
  repaired with `playlist.save(id)`; a repair that fails is reported to the
  user.
- **Also fixed on the way**: `AppLogger.reportError` threw a
  `LateInitializationError` when the logger had not been initialized — the
  error reporter hiding the error it was reporting.
- **Tests**: `test/saved_library_refresh_test.dart`,
  `test/saved_library_lists_sync_test.dart`,
  `test/playlist_library_membership_test.dart`. Full suite 1636 pass / 2 skip;
  analyzer clean.
- **Do not reinvestigate the symptom** without a new log excerpt: check whether
  the list is still stale after a refresh (the fix's own trigger). Every saved
  list the app has is in the sync now — there is no podcast/show list.

### "The update forgot my settings" is a package-name boundary, not a data bug — investigated 2026-10-21
- **Reported symptom**: after updating the app, automatic download and other
  preferences were back at their defaults ("everything resets").
- **No wipe exists in the data layer.** `UserPreferencesNotifier.loadPreferences()`
  inserts the default row only when `id=0` is absent; `setData` is a partial
  `update().write()`; the full-row `replace()` (which *would* reset everything)
  is reachable only from the user's own "Restore defaults" action. Nothing in the
  drift migrations or the startup path deletes `preferences_table`.
- **Proof of in-place survival**: on the AVD, `auto_download_quality=1`,
  `music_cache_limit_mb=512`, `skip_non_music=1` plus the four existing plugin
  rows were written, then `adb install -r -g` of a newer release/stable APK over
  the old one. Relaunch read back the identical values and rows. An Android
  same-signature, same-`applicationId` update does not touch
  `/data/data/oss.krtirtho.spotube`.
- **Actual cause**: `android/app/build.gradle` gives the flavors distinct
  application IDs — `stable` → `oss.krtirtho.spotube`, `nightly` →
  `.nightly`, `dev` → `.dev`. Each is a separate app with its own empty database.
  The published fork releases (e.g. `v5.1.2-fork.4`) ship
  `Spotube-<ver>-android-nightly-debug.apk` next to the stable per-ABI APKs, so
  installing that one — or alternating — looks exactly like "the update forgot
  everything". All build types sign with `signingConfigs.release`, so this is not
  a signature conflict and nothing needs uninstalling.
- **Fix belongs to the release process, not the app**: publish stable-flavor
  artifacts only. A debuggable build for logcat does not have to be the nightly
  flavor — `fvm flutter build apk --debug --flavor stable` keeps
  `oss.krtirtho.spotube` and the release key, so it updates in place and keeps
  the user's data.
- **Do not reinvestigate** the database/migration layer for this symptom; the
  boundary is the package name.

### Stats history windows and legacy rows — implemented 2026-10-21
- `historyWindowStart` now lives in `top.dart` and uses calendar boundaries:
  Monday for "this week", first of month/year, current + five previous months
  for "last 6 months", and last year + current for "last 2 years". Top tracks,
  top albums, top playlists and the image repair share it; top albums no longer
  computes a different week/month/year with `strftime`.
- Top albums filters legacy `external_urls` rows in both branches and drops
  track rows whose nested `$.album` is null. That matches `HistoryItemParse`
  and the top-tracks/top-playlists legacy rule.
- Top playlists' paginated `fetch` now drops unresolvable rows before grouping;
  the old `playlist!` threw on legacy rows even though the watch query filtered
  them.
- `fetchAll`'s 200-page cap now clears `hasMore`/`nextOffset` when it finalizes
  a partial list, so a rogue source cannot keep re-entering the capped walk.
- Removed `PlaybackHistoryActions.clear` (zero callers; it also did not await
  its delete).
- Tests: `history_window_test.dart` (calendar boundaries, playlist window,
  legacy playlist fetch, legacy album rows/week window), all six durations in
  `history_playlist_grouping_test.dart`, and the cap assertion in
  `perf_audit_bounds_test.dart`. Full suite 1579 pass / 2 skip; analyzer clean.

### Playlist auto-downloads, independent main order, card cover behavior — implemented 2026-10-20
- Schema v28 adds `playlist_download_mirror_table.auto_download` (default
  false) and nullable `preferences_table.main_playlist_order`. The migration
  seeds main order from `pinned_playlist_ids` only where the new column is
  NULL; an empty string is an intentional empty order and is never reseeded.
- `PlaylistMirrorService.syncAutoDownloadPlaylists()` walks opted-in playlists
  50 tracks at a time, enqueues per page, and writes header + full membership
  only after the last page. It runs after startup idle and on the
  `ConnectionCheckerService` offline→online edge, throttles successful runs,
  and retries immediately after failure plus bounded 30s/60s/120s backoff
  retries (production only; direct test instances default off). Liked Tracks
  is included: its synthetic `user-liked-tracks` id fetches `user.savedTracks`
  instead of `playlist.tracks`.
- A playlist deletion bumps a generation token; every playlist-scoped
  membership/header/status write and enqueue rechecks it, so a page fetched
  after deletion cannot recreate the mirror. Disabling auto-download and
  deleting a playlist never remove files or global download rows. The one
  exception is `forgetEverything` — the explicit "Delete local library" action,
  which bumps a global epoch so no in-flight walk can write anything back.
- Global `track_download_table` rows are reused across playlists. Missing/empty
  files mark `completed` rows `missing` and requeue; persisted `failed` and
  `interrupted` rows and in-memory failed tasks are retried on startup and on
  connectivity restoration, even when the failed attempt left a non-empty file.
  Retries use an id-suffixed destination so the leftover file is neither reused
  nor overwritten. Queued downloads wait for audio-source presets instead of
  being failed before the plugin loads. Validation remains existence +
  non-zero length, not audio integrity.
- Main playlist/album cover+name now open the collection; only the explicit Play
  button plays. Sidebar pins keep their cover-play/name-navigate split.
- Touch card taps (2026-10-21): the whole-cover play trap is gone for good —
  `onCoverPressed` was deleted from `PlaybuttonCard`/`PlaybuttonTile` (no caller
  after `a3eec4fc`), so a presentation can no longer map the entire artwork to
  playback; the compiler enforces it. Corner queue/play buttons stay shown on
  mobile (`hovered || kIsMobile`) — they are small descendants of `CardImage`'s
  Button and only win their own regions, so everywhere else the tap falls
  through to navigation. Sidebar pins keep their own cover-play tap
  (`sidebar_pin_tile.dart`), built locally, not via the presentations.
  `PlaybuttonTile` row `enabled` follows `onTap != null`, not `canPressPlay`, so
  resolving/preparing play no longer dead-taps the row on phone widths.
  `radio_station_tile.dart` still force-shows its overlay on mobile — same
  shape, but it never had the whole-cover mapping, so it is not a tap trap.
- Tests: `playlist_auto_download_test.dart` (paging, reuse, missing file, live
  failed retry, persisted failed/interrupted retry, canceled preservation,
  partial-failure retry, deletion race, disable preservation),
  `download_persistence_test.dart` (queued work waits for presets; retry path
  does not touch the failed file), `playlist_order_test.dart`,
  `playlist_interactions_test.dart`, and the v27→v28 data migration test. Full
  suite 1550 pass / 2 skip; analyzer clean.
- Live check (Linux release, 2026-10-20): restarting with 6 `failed`
  (three pairs of tracks colliding on one filename) and 4 `interrupted` rows
  retried all ten to id-suffixed destinations. All 544 rows ended `completed`;
  zero failed/interrupted remained.

### Android bottom chrome lost its frost and play/pause lied while resolving — fixed 2026-10-20
- Symptom: on Android the frosted bottom bar (mini player and nav bar) could
  go transparent/flat after play/pause or during scrolling. Separately, when a
  downloaded/local file started before source resolution finished, the
  transport kept spinning and disabled itself even though audio was audible.
- Cause: the pinned Flutter 3.35.2 Impeller engine still has the nested
  `BackdropFilter` pass bug (flutter/flutter#173622; fix `84f5d26` first ships
  in 3.38). Spotube made it visible by dropping the chrome's blur to zero
  during scroll (`chromeBlurFrozen`), which with a translucent theme removed
  the bar's only visible tint, and by rebuilding the collapsed card when
  source resolution settled. The play button also treated
  `queryingTrackInfoProvider == true` as "not ready" even when playback had
  already started from a downloaded/local copy.
- Fix: `PlayerPlayPauseButton` spins/disable only while
  `isFetchingActiveTrack && !playing`; the mini player's transport row is its
  own consumer so resolution cannot rebuild the frosted card. The collapsed
  card and nav bar keep `theme.surfaceBlur` through scrolls (the old freeze was
  not a measured CPU win). ~~Android release builds disable Impeller~~ — that
  escape hatch is gone: the project is on Flutter 3.38.10 and Impeller has been
  on for Android since `e025d55c`, so the manifest no longer opts out and the
  engine fix `84f5d26` is in the pinned SDK. Corrected 2026-10-21 against
  `android/app/src/main/AndroidManifest.xml` and `pubspec.yaml`.
- Tests: `test/player_play_pause_isolation_test.dart` now also proves
  playing+resolving shows an enabled pause button (no spinner), paused+
  resolving still spins/disables, and a frozen scroll leaves the card's
  `surfaceBlur` non-zero. Targeted player + scroll tests and
  `fvm flutter analyze` pass.

### Android play/pause ghosting under the floating player — fixed 2026-10-20
- Symptom: on Android (built-in theme, adaptive layout) pausing or playing a
  track made the wallpaper under/around the floating mini player flicker.
- Cause: known Impeller nested-`BackdropFilter` ghosting
  (flutter/flutter#173622). Even without a wallpaper theme the mini player's
  `SurfaceCard` filter and the nav bar's filter stack; on top of that
  `PlayerOverlayCollapsedSection` read `audioPlayer.playingStream` in its
  build, so every toggle rebuilt the whole blurred card. Engine fix `84f5d26`
  first ships in stable **3.38.0**; the pinned 3.35.2 (and every 3.35.x) still
  uses the buggy `kDontCare` inline-pass path — do not treat this as a
  Spotube state bug again.
- Fix: shared `PlayerPlayPauseButton` (`lib/modules/player/`) watches
  `audioPlayerProvider.select((s) => s.playing)` and wraps the button in a
  `RepaintBoundary`; both bottom-chrome call sites stopped reading
  `playingStream` at card level. `test/player_play_pause_isolation_test.dart`
  proves the icon follows app state and the card/controls widgets are not
  rebuilt on a toggle.
- Not the root fix: the engine bug remains on this SDK. If it reappears via
  another repaint (e.g. track changes, which must rebuild the card), either
  bump Flutter to ≥3.38 or set `surfaceBlur: 0` on Android chrome (the
  existing `chromeBlurFrozen`/`realTransparent` pattern). Upstream fix
  verified present in 3.38.0/3.41.0 and absent in 3.35.2–3.35.7.
  **Status 2026-10-21**: the bump happened (3.38.10), and the third option is
  now the one actually used for artwork surfaces — `FrostedArtwork`
  (`lib/components/image/frosted_artwork.dart`) bakes the blur into the image
  with `ImageFiltered` on Android so there is no backdrop to sample and no
  nested filter to ghost. See "Playlist header frost was flat until the first
  scroll".

### Playlist header frost was flat until the first scroll — fixed 2026-10-21 (device proof pending)
- Symptom (user report, Android): after opening a playlist the frosted panel
  over the cover art looked flat/transparent; scrolling a flick restored it.
- Cause: `_HeaderSurface` (`presentation_top.dart`) is a shadcn
  `OutlinedContainer`, whose `surfaceBlur` compiles to
  `Stack > ClipRRect > BackdropFilter`
  (`shadcn_flutter-0.0.47/lib/src/components/layout/outlined_container.dart:53-75`).
  A `BackdropFilter` blurs *what was already painted behind it* — here the same
  cover, drawn by a `CachedNetworkImageProvider` in the parent `DecoratedBox`.
  On the header's first painted frame that backdrop is still empty, and the
  image resolving later does not re-sample the filter; only the next scroll
  repaint does. Same class as the nested-`BackdropFilter` findings above.
- Fix: `FrostedArtwork` renders `ClipRRect > ImageFiltered(blur σ,
  tileMode: mirror) > DecoratedBox(cover)` and the panel above it takes
  `surfaceBlur: 0` plus its translucent tint. Gated to `kIsAndroid` via
  `artworkIsSelfFrosted`, so desktop/iOS keep the old `DecoratedBox` path
  unchanged. Used in `presentation_top.dart` (playlist, album and liked
  playlists share that header) and in the lyrics page, which had the same
  problem in a full-screen σ10 form. On Android the header also stops watching
  `scrollInFlightProvider` — with no backdrop there is nothing to freeze, so
  the frost no longer flickers off mid-scroll and the header stops rebuilding
  on scroll start/settle. `ImageFiltered` reuses the already-cached provider,
  so there is no second decode.
- Verification gap, stated plainly: the frost only exists where artwork exists,
  and this AVD cannot reach such a surface — Home, Search and the Playlists tab
  all render "You're not logged in", a Spotify playlist URL in search returns
  "Spotify rejected this login", Musicbrainz has no Spotify playlists, and the
  local fixture library cannot show it either because `LyricsPage.hasArtwork` is
  `activeTrack.album.images.isNotEmpty` (`lib/pages/lyrics/lyrics.dart:30-31`)
  and a scanned file has no `images`. So the before/after screenshot pair has to
  come from a signed-in device; `.ai/TODO.md` carries it as a P1 next to the
  removal check. What the AVD did prove: the no-artwork lyrics page, the Plain
  tab, the folder list and playback are pixel-for-pixel unchanged, and the
  release build shows no overflow or crash markers.
- Repo convention (see `test/yt_dlp_android_exec_test.dart`): `kIsAndroid` is a
  top-level final over `Platform.isAndroid`, so an Android-only branch is not
  inverted in host tests — it is verified on device. No host test covers the
  `ImageFiltered` branch; the tests do cover the non-Android path staying a
  plain `DecoratedBox`.

### "Remove song from playlist does nothing" — plugin assert + swallowed host failure, fixed 2026-10-21
- Two independent defects stacked, which is why the symptom was "not working
  properly" rather than an error:
  1. The bundled Spotify plugin's `removeTracks(playlistId, {uris})` asserted on
     `tracks != null && playlistId != null` — `tracks` is not a parameter of that
     function (`addTracks` above it uses `uris`), so every call tripped an
     undeclared-identifier assert before the DELETE was built. Fixed in the
     plugin repo at
     `/home/adamya/projects/spotube-plugin-spotify-audit/dependencies/hetu_spotify_gql_client/lib/assets/hetu/playlist.ht:359`,
     published as 0.2.10 (`src/segments/core.ht:48` also stopped polling
     `sonic-liberation`'s releases, which offered to replace Adamya's build with
     the upstream one).
  2. The host never looked at the result:
     `track_options_provider.dart:211-213` called
     `favoritePlaylistsNotifier.removeTracks(playlistId ?? "", [track.id])`
     un-awaited with no catch, so the engine error vanished and `""` was passed
     as a plausible-looking playlist id. Now awaited, guarded, and reported
     through the same `showToast` pattern the rest of that file uses.
- Third, quieter one: `removeTracks` wrote no local table, so a mirrored
  (offline/downloaded) playlist kept the row and the page's reload fallback
  (`mirroredPlaylistTracksProvider`) could re-paint the removed track. Added
  `detachTracksFromPlaylist` in `lib/services/downloads/download_store.dart`,
  which deletes only `playlistMembership` rows — never `track_download_table`,
  because the file is still on disk and other playlists may reference it.
  `mirroredPlaylistTracksProvider` is a drift `watch()` stream, so the deletion
  propagates without an extra invalidate.
- Tests: `test/playlist_track_removal_test.dart` (membership rows for the
  removed id go, other playlists' membership and the downloaded file rows stay,
  an empty `playlistId` makes no plugin call, a throwing plugin leaves local
  rows alone) and `test/bundled_plugins_seed_test.dart` now pins the bundled
  archive at 0.2.10 and checks its `repository` against the `checkUpdate`
  target, so a stale re-bundle fails the suite.
- Device evidence: the 0.2.10 archive re-seeded over the in-place update
  (`select … from plugins_table` → `Spotify | Adamya Bhatt | 0.2.10 |
  selected_for_metadata=1`) and its kernel loaded in 5ms with no Hetu error in
  logcat. The removal itself needs credentials, so it is a P1 for the phone.

### Lyrics page open cost — what the 1-2s stutter is not, and what is left
- **Corrected 2026-10-22 — the earlier "disproven" note below was wrong, and
  the guard test passed for the wrong reason.** `IndexedStack` does *not* mount
  only its selected child: Flutter wraps each child in
  `Visibility(visible: i == index, maintainSize: true, maintainState: true)`
  (`flutter/lib/src/widgets/basic.dart:4812-4821`), which keeps the hidden
  child **mounted and laid out** — only `paint` is skipped. The hidden
  `PlainLyrics` — one giant, non-lazy `SelectableText` — was therefore laid
  out on every open: measured with `skipOffstage: false` on the real page,
  `PlainLyrics` was present and its `SelectableText` render object was
  **28,800 px tall** for a 120-line lyric. The old guard
  (`find.byType(PlainLyrics)`) reported 0 because `find.byType` skips
  offstage elements by default — it could not see an offstage-but-mounted
  subtree. There is no "mounted but never laid out" primitive in Flutter
  (`Offstage` lays its child out with the *same* constraints), so the Plain
  tab is now simply **not in the tree until it has been asked for**
  (`plainRequested` latch in `lib/pages/lyrics/lyrics.dart` and
  `lib/pages/player/lyrics.dart`); it stays there afterwards, so switching
  tabs never re-pays the layout. The guard test now asserts
  `find.byType(PlainLyrics, skipOffstage: false)` is empty, and the
  lyrics-page first frame dropped from ~112 ms to ~50 ms at n=300 on this
  host's JIT.
- The O(n²) `elementAtOrNull(i+1)` join was already fixed (one `useMemoized`
  O(n) pass).
- Still worth fixing, and fixed: the join is now one `useMemoized` O(n) pass
  (byte-identical output at n=40/120/300/800; 45→17µs and 100→27µs measured on
  this host's JIT). Honest magnitude: that is microseconds, so it is not what
  the user felt, and it is not claimed as such.
- The two real rendering defects found while building the instrument, both
  Android-visible and both fixed:
  - `ShimmerLyrics` gave every row a fixed 471px `Bone.text` inside a `Center`
    in a phone-width page, so the loading state overflowed by 417px *per row*
    while the fetch cascade runs (up to 30s). Now viewport-derived row count
    and fractional widths; asserted in the instrument.
  - The lyrics header was `Row(Tabs, Spacer, Consumer(Text))` — a non-flexible
    attribution next to a `Spacer` overflowed by 33px at phone width and pushed
    the label off screen. Now `Expanded` + ellipsis.
- `scrollToIndex` no longer runs inside `itemBuilder` (`synced_lyrics.dart`);
  it is a post-frame effect keyed on `[currentTime, controller]` and guarded by
  `isIndexStateInLayoutRange`, which is exactly the old build-side condition, so
  a row the list never built is still ignored.
- What the stutter most likely *is*: the page-wide σ10 `BackdropFilter` over a
  cover that is still decoding, with an animated shimmer repainting behind it.
  That is the same backdrop-starvation class as the frost finding above, and it
  is what `FrostedArtwork` removes on Android. Its GPU cost is not measurable
  on this host — see the verification gap in the frost entry.
- Harness note, learned the hard way: a widget test that renders `LyricsPage`
  must not dispose its `ProviderContainer`. `themeBackdropUrlProvider` watches
  two `FutureProvider`s through `.select`, and riverpod 2.6.1 closes a
  `_SelectorSubscription` during element disposal by reading back through the
  container it has already marked disposed → "Bad state: Tried to read a
  provider from a ProviderContainer that was already disposed". Production's
  root container outlives the process, so this is harness-only.
- The instrument also needs `MediaKit.ensureInitialized()` (the lyrics page
  reaches the global audio player through `useSyncedLyrics`) and a 480px-wide
  logical viewport, because `kTitlebarVisible = kIsWindows || kIsLinux` reserves
  desktop window controls in a Linux test process.

### Linux release plugins failed with `Undefined identifier [Rb/lRa/OSa]` — fixed 2026-10-20
- Symptom: the installed Linux release printed repeated Hetu runtime errors at
  startup and playback — `auth.ht:33` / `core.ht:49` / `audio_source.ht:59`,
  with mangled identifiers (`Rb`, `lRa`, `OSa`) and stack traces ending in
  `MetadataPlugin.create` or `HTInstance.invoke`. Plugins still appeared
  installed, but auth/audio-source calls failed.
- Cause: `scripts/install-local.sh` built Linux with `--obfuscate`. Dart
  obfuscation renames `Object.runtimeType`/`Type.toString` (documented by
  `flutter build linux --help`). Hetu resolves external plugin classes through
  those runtime names in `HTInterpreter.toExternalValue`, so the obfuscated
  names no longer match the registered classes.
- Fix: build with `--split-debug-info` only; no `--obfuscate`. The non-obfuscated
  release loads the theme, YouTube audio and Spotify metadata plugins and runs
  auth without the undefined-identifier loop. Android APKs are unaffected
  because their build commands never enabled obfuscation.
- Do not re-enable `--obfuscate` for any target that loads Hetu plugins.

### Android restart skipped through the restored queue — fixed 2026-10-20
- Symptom: after an app restart, playback tried to start, failed track after
  track, and ended at the end of the playlist; pressing play then did nothing.
- Cause: `AudioPlayerNotifier.build` starts `syncSavedState` as soon as the app
  root watches the player (`sourcedTrackRetentionProvider`), which is before
  the post-splash `serverProvider` subscription binds the local playback
  server. `SpotubeMedia.uriFor` embeds `SpotubeMedia.serverPort` in every URI
  at construction time, so the restored queue was built as
  `http://127.0.0.1:0/stream/...`. mpv loads the selected paused entry
  immediately; every failed load advances `playlist-pos`, so it walked the
  whole queue and persisted the exhausted index.
- Fix: `syncSavedState` awaits `playbackServerPortProvider` before building
  media for a queue containing remote tracks. That provider waits for the
  initial preferences load (so a persisted custom `connectPort` is not
  missed) and then for the bind. Local-only queues skip the wait. A
  `[startup] queueRestore: ... (serverPort=...)` line records the bound port.
- Test: `test/server_port_rebind_test.dart` proves the waiter does not bind
  while preferences are loading and binds the persisted port afterwards.
- Not covered: a server rebind that moves the port while a queue is already
  loaded still leaves that queue's URIs stale (the open item in `TODO.md`).

### Idle CPU is ~22% and does not go lower without a rewrite — investigated 2026-10-19
- Measured: a **stock Flutter app on this machine uses 0.0-0.1% CPU at
  idle**; Spotube uses **~22%** (GTK main ~10%, raster ~6.5%, Dart UI
  ~5%). So the cost is Spotube-specific, not Flutter's.
- The app renders a **continuous 64 fps** while idle (347 frames in 40 s,
  median gap 15.4 ms). A Flutter app stops requesting frames when
  nothing is dirty, so something requests a frame every vsync.
- **The cause is live `Ticker`s, and they were found** (by patching
  `Ticker._tick` in the Flutter SDK to print its owner): 24 distinct
  always-running tickers, dominated by
  - `_OverflowMarqueeState` (934 ticks) — shadcn's `NavigationButton`
    defaults to `NavigationOverflow.marquee`, whose `OverflowMarquee`
    starts a ticker in `initState` and never stops it, calling
    `setState` every tick forever. The app has 4 such buttons in the
    always-mounted sidebar.
  - `_CircularProgressIndicatorState` (8 instances) — Flutter's
    indicator calls `_controller.repeat()`; with the Spotify API
    returning 401, the error paths keep spinners mounted.
  - plus `AnimatedValueBuilder`, `_AnimatedContainer`,
    `_AnimatedFadeOutFadeIn`, `AnimatedSwitcher` and the splash.
- **Fixing the spinners and the marquee did not move the number**
  (22.4% after, 21.6% before) — so the frame *scheduling* is not what
  the CPU is spent on. Both changes were **reverted**: a real spinner is
  better UX for a short wait, and the marquee→ellipsis swap changes how
  labels render for no measured gain.
- **Do not re-investigate the idle CPU** with the same approaches
  (spinner replacement, blur removal, `surfaceBlur: 0`, removing the
  nav bar / bottom player / theme background). Each was measured and
  each changed nothing. The remaining cost is the framework's own
  per-frame work plus the always-mounted animated widgets, and cutting
  it further means not rendering the UI — a rewrite, not an
  optimization.
- The measurement method (patching the SDK's `Ticker` to print its
  owner) is what actually names the culprit; the timeline's `Frame`
  events do not, and the app's own `BUILD`/`LAYOUT`/`PAINT` phases
  measure 0.000 ms.

### Android build failed with exit 127 ("dart: command not found") — fixed 2026-10-19
- Symptom: `flutter build apk` failed at
  `:flutter_discord_rpc:cargokitCargoBuildFlutter_discord_rpcDebug` with
  "finished with non-zero exit value 127", and the same for
  `metadata_god`. The build never reached any Dart or Kotlin compilation.
- Cause: `flutter_discord_rpc` and `metadata_god` build their native
  sides through cargokit, whose `run_build_tool.sh` runs
  `$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart` when FLUTTER_ROOT is set and
  plain `dart` otherwise. Neither was on the environment Gradle handed to
  that child process, so the script died at its own line 87.
- Fix: `android/gradlew` now reads `flutter.sdk` from `local.properties`
  and exports `FLUTTER_ROOT`, with the Flutter SDK's `dart-sdk/bin`
  prepended to PATH — **before** it execs Gradle. That script is the
  client that starts the Gradle daemon, and the daemon (and every
  process it spawns) inherits the environment it was started with.
  The fix could not live in a build script: `System.getenv()` is
  immutable, and Gradle's internal `ProcessEnvironment` is not on the
  build script's classloader (it lives in `gradle-native`, and its
  methods are instance methods on an interface with no accessor).
  `providers.environmentVariable` is not usable from an init script
  either.
- Verified: `flutter build apk --debug` and `--release` both succeed —
  291 MB debug / 147 MB release APKs for all three flavors
  (dev/nightly/stable), with `libspotube.so` carrying the
  `Java_oss_krtirtho_spotube_MemoryBacking_nativePrctl` symbol and
  `MemoryBacking` + `DeviceMemoryChannel` both surviving R8 in the
  release dex.
- Note: `flutter build apk` still prints "Gradle build failed to produce
  an .apk file" even on success — the APKs are in
  `build/app/outputs/flutter-apk/` under their flavor names. The
  message is a lookup quirk, not a build failure.
- 2026-10-21, same quirk fixed by always passing the flavor: `make apk-arm64`
  builds `--flavor stable` only and prints `✓ Built …` normally. Measured
  **80.4 s vs 386 s** for the flavor-less command, which ran R8 + resource
  shrinking + packaging serially for all three flavors.
  `android/gradle.properties` now also carries `org.gradle.parallel=true` and
  `org.gradle.caching=true`.
- **Do not attempt `android.enableJetifier=false`** without first removing
  `disable_battery_optimization`: `dependencyInsight` on
  `stableReleaseRuntimeClasspath` shows it pulls
  `com.afollestad.material-dialogs:0.9.6.0` → `com.android.support:appcompat-v7`
  /`support-compat:27.0.1`, and with jetifier off the build dies on duplicate
  `android.support.v4.os.ResultReceiver` vs `androidx.core:core:1.15.0`.
  The legacy `com.android.support:multidex` coordinate was already replaced with
  `androidx.multidex` (the app source always imported `androidx.multidex.MultiDex`).

### 227 MB of the "Dart heap" was transparent huge pages — fixed 2026-10-19
- The RAM plan's premise was that the Dart heap held ~365 MB and that
  image-cache and plugin-VM retention (items 1.2/1.4/1.5) were the
  problem. **The live Dart heap is 27.5 MB** (the VM's own
  `getMemoryUsage` via the VM service). The 365 MB was the *kernel*
  backing the VM's sparsely-touched 5.1 GB heap arena with 2 MB
  transparent huge pages: a few KB touched, 2 MB charged.
- Proof: `prctl(PR_SET_THP_DISABLE)` (a per-process setting) drops
  `AnonHugePages` from 250 MB to 0 and the process's RSS from **606 MB
  to 203 MB**, with the live heap unchanged at 27.5 MB.
- Smoothness cost, measured on the running app over 25 s windows, four
  runs each: minor faults/s 5,741/5,380/5,599/5,695 (THP on) vs
  5,801/5,998/5,476/5,554 (off); CPU 25.0/23.4/24.5/24.2% vs
  23.1/23.5/25.2/23.6%. **Overlapping — no consistent direction.** The
  hot paths (mpv/FFmpeg audio, Impeller raster) are native buffers.
- Fix: `prctl(PR_SET_THP_DISABLE)` in `linux/main.cc` (before the engine
  starts) and the equivalent on Android (`MemoryBacking.kt` +
  `cpp/memory_backing.cpp`). Per-process, so only Spotube is affected;
  harmless on a kernel without THP.
- Result: **PSS 548 → 315 MB**, **RSS 648 → 415 MB** (app process).
  The Flutter floor is 90 MB PSS.
- Do not re-investigate "the Dart heap is 365 MB" — it was never that.
  The number is in `.ai/MEMORY.md`.

### The command line was dead on Linux — fixed 2026-10-19
- Symptom: `spotube --version` printed nothing and exited 1. Every
  command-line flag was inert.
- Cause: the Linux runner's `local_command_line` returned `FALSE`
  ("not handled") while the application also declared
  `G_APPLICATION_HANDLES_COMMAND_LINE`. GLib then refused to run the
  default handler and exited 1, so the **Dart entrypoint never ran**.
  The Flutter template returns `TRUE` and does not set that flag.
- Fix: `local_command_line` returns `TRUE`; the flag is replaced with
  `G_APPLICATION_NON_UNIQUE` (the template's choice, which also lets a
  second launch reach Dart so `spotube --play ...` can forward to the
  running instance instead of GTK activating the existing window and
  discarding the arguments). `g_set_prgname` added, as the template does.
- The parser was also strict: an unknown switch (the engine's own
  `--vm-service-port`, for instance) was a fatal `FormatException`. It
  now reports and ignores unknown switches.
- The app's own log confirms the pre-existing breakage: the installed
  build (2026-10-06) had the same exit-1 behavior.

### Local control channel + CLI control + MCP server — added 2026-10-19
- A local-only control endpoint (Unix socket, or a loopback TCP port
  where there is no socket): `~/.local/state/spotube/control.sock`. It
  is a **separate** endpoint from the playback/connect server, so
  enabling Connect (which exposes the app to the LAN) does not expose
  this.
- `spotube --play/--search/--pause/--resume/--next/--previous/--status/
  --volume` drive the already-running instance. A second launch does not
  start a second app.
- `spotube --mcp` runs an MCP server (official dart-lang `dart_mcp`
  0.5.2) on stdio with four tools — `spotube_state`, `spotube_search`,
  `spotube_play`, `spotube_control` — over the same command vocabulary.
  It is a **separate process**, so it costs the running app no memory.
- stdout is a protocol channel, and the native media_kit plugin prints
  to stdout when it loads (before Dart even starts), so the Linux runner
  parks the real stdout on a dedicated descriptor and points fd 1 at
  stderr in a control-command mode. Two traps found the hard way:
  - the saved descriptor must be chosen by the kernel
    (`fcntl(F_DUPFD, 3)`), **not** a fixed number: the GPU driver has
    already claimed the low descriptors, so a fixed one silently fails
    and the redirect never happens.
  - the socket's *file* outlives the process that created it, so its
    presence says nothing about liveness. A second launch that deleted
    it unconditionally pulled the socket out from under the live
    instance ("address already in use"), breaking its channel. The
    server now probes by **connecting** before deciding the file is
    stale.

### Device-aware image budget — added 2026-10-19
- The three image caches shared no budget and each had a fixed ceiling:
  the platform image cache 64 MB, the decoded-artwork cache 24 MB, and
  the artwork-bytes memo 64 entries with **no byte cap** (a 640x640
  Spotify cover is ~150 KB, a small one ~5 KB, so a handful of large
  covers cost megabytes without bound).
- They now share one budget that follows the device: a quarter of the
  platform's per-app heap limit (Android's
  `ActivityManager.getMemoryClass()`, over a platform channel), bounded
  to 8–64 MB, with the device total from `/proc/meminfo` and a
  conservative 32 MB fallback. The memo is now bounded **by bytes**,
  with the entry count kept as a backstop.

### Playback crash on a null container preset — fixed 2026-10-19- Symptom: "Failed to open http://127.0.0.1:<port>/stream/<id>" and the
  player never started. Release log
  (`~/.local/state/spotube/.spotube_logs`) had 21 occurrences of
  `Null check operator used on a null value` at
  `ServerPlaybackRoutes._getTrackCacheFilePath`, each immediately followed
  by a failed stream open (265 in total). Most recent 2026-10-19 18:53.
- Cause: `SourcedTrack.qualityPreset` is **nullable by design** — the
  audio-source plugin publishes its presets asynchronously, so the list is
  empty until the plugin loads, and a persisted index can point past the
  end of a shrunken list. `playback.dart` force-unwrapped it with `!` in
  **four** places (the cache-path extension, two `Content-Type`
  interpolations, and the weba-metadata-skip check), so any of those states
  threw inside the shelf handler and took the whole stream request with it.
- Fix: `SourcedTrack.container` now resolves the container through the
  same fallback chain `url` already used (selected preset → first
  available preset → the container of the first resolved stream) and
  returns `null` only when there is genuinely nothing to serve. All four
  call sites use it. `SpotubeAudioSourceContainerPreset.fileExtensionForContainer`
  shares the mp4→m4a / webm→weba mapping between the preset and the bare
  container name. The persisted container index is now **clamped** on
  restore (`clampPresetIndex`), which is the root cause of a stale index
  and also fixes two direct-index `RangeError` sites (the download pump
  and the Settings → Playback quality tiles). `supportedPresets` is
  guarded against a throwing `memberGet` and against one unparseable
  preset hiding the rest.
- Tests: `test/source_quality_fallback_test.dart` (18 green) pins the
  container resolution, the extension mapping and the clamp. Full suite
  1401 green / 2 skipped. `flutter analyze` clean. Linux release build
  succeeded.
- Do not reinvestigate the "Failed to open" symptom without a new log
  excerpt — check whether the error is still the null-check at
  `playback.dart` (fixed) or a different failure.

### Expired Spotify token breaks search and browse — user action, not a code fix
- Symptom: search and the Home browse sections return nothing while
  login itself completes. The release log holds **346** `status code of
  401` errors against the plugin's GQL endpoints (`browse.sections`,
  `savedArtists`, `savedTracks`), most recently 2026-10-19 18:53.
- Cause: the metadata plugin's stored token is rejected. The credentials
  live in `shared_preferences.json` under
  `flutter.spotube_plugin.spotify.credentials`. The DB's
  `authentication_table` is **empty** and the host never reads it (only
  the schema references it) — authentication is entirely plugin-side, so
  no host-side change can fix this. The fix is re-authentication through
  Settings → Metadata plugins.
- Host-side improvement landed: `ErrorBox` now shows a **Login** button
  for credential errors, which routes to the metadata-plugin settings.
  Retrying the same request with the same dead token cannot help, so the
  error must point at the re-auth flow.
  Covered by `test/search_tab_scaffold_test.dart`.
- Note: this is the likely cause of the user's "cannot search song"
  report. The `isCredentialError` match already crossed the Hetu VM
  boundary correctly (`test/rate_limit_test.dart`).

### WebKit at idle is 7.4 MB — the RAM plan's item 1.1 is dropped
- The pasted RAM plan proposed "stop linking/loading WebKitGTK at idle"
  and estimated a large saving with no number attached. **Measured:
  7.4 MB** of 571 MB RSS (1.3%): `libwebkit2gtk-4.1` 5.6 MB,
  `libjavascriptcoregtk-4.1` 1.5 MB, `libsoup-3.0` 0.3 MB. See
  `.ai/MEMORY.md` for the full attribution.
- The libraries *are* linked and mapped at idle (`ldd` on the installed
  plugin confirms all three), but **no WebKit helper process exists at
  idle** — the network/UI processes only spawn when a webview is
  actually opened. Verified by enumerating the full descendant tree of a
  running instance.
- The plan's stated replacement — "the flow `auth.dart` already has for
  web" — **does not exist**. `auth.dart` has only
  `WebviewWindow.clearAll()`. The webview is not host code at all: it
  lives in the metadata plugin
  (`hetu_spotube_plugin/lib/webview/webview.dart` calls
  `WebviewWindow.create` on Linux) and is a declared
  `PluginApis.webview` capability, so removing it breaks plugin
  authentication.
- Do not re-propose item 1.1 without a measurement showing a cost above
  ~7 MB. The number is in `.ai/MEMORY.md`.

### RAM plan items dropped against measurement — see `.ai/MEMORY.md`
- **1.4** ("don't retain embedded picture bytes in the local-library
  model") was **already true**: `local_tracks_provider.dart:145-158`
  writes `picture.data` to a file and keeps only the path. No-op.
- **1.6** ("ship-size → resident-size") is a category error: ship size is
  not RSS. `country_flags` (3.3 MB) is a *transitive* dep of
  `shadcn_flutter` (216 lib files import it) and is referenced by zero
  Dart files, so dropping it means dropping shadcn_flutter.
  `uses-material-design: false` was already investigated and rejected
  (`.ai/AUDIT_STATE.md`, "not safe, do not propose").
- **The plan's PSS baseline of 348 MB is stale.** It comes from
  `OPTIMIZATION_PLAN.md:41` (2026-09-20) and was superseded by
  `PERFORMANCE.md:22` (2026-09-24, PSS 540→606 MB). The 2026-10-19
  measurement gives PSS 548 MB — consistent with the newer figure. A
  target of "348 → 230 MB" was measured against a baseline that was
  never real.

### yt-dlp cannot be bundled on Android — investigated 2026-10-20
- Question: "can we get yt-dlp on Android too?"
- Answer: **not as a bundled binary.** Four independent blockers, each
  sufficient on its own:
  1. **No official Android build.** yt-dlp publishes `yt-dlp_linux`
     (glibc 2.17+), `yt-dlp_musllinux`, `yt-dlp_macos`, `yt-dlp_windows`
     and a platform-independent `yt-dlp` **zipapp**. There is no
     `android`/`aarch64-android` artifact; the Linux ones are PyInstaller
     bundles linked against glibc, Android is bionic.
  2. **yt-dlp is a CPython program** (needs Python 3.10+) and Android
     ships no Python. The zipapp alone does nothing.
  3. **Licence.** The only Android CPython builds are Termux's `python`
     package, which is **GPL-3**. Spotube is **BSD-4-Clause**; bundling a
     GPL-3 interpreter would make the combined APK a GPL-3 work. It would
     also add ~45 MB to an APK that is already 92 MB for arm64 alone.
  4. **Building one is not a weekend project**: CPython for bionic needs
     an OpenSSL build too (Android exposes no TLS library) and yt-dlp
     cannot work without TLS.
- **Android is already at parity.** The Android default engine is
  **NewPipe** (a native binding to the NewPipeExtractor library). Its
  search rows carry `duration` and `isShortForm` — exactly what the
  wrong-length rule and the Short-form rejection need — so the fixes
  that yt-dlp rows also qualify for apply there. The cross-engine
  fallback cascade already exists
  (`SourceResolver.engineFallbackCandidates` + `resolveFirstAvailable`):
  Android is NewPipe → YouTubeExplode, desktop is yt-dlp → NewPipe →
  YouTubeExplode.
- **What changed**: the engine is now *offered* on Android
  (`isAvailableForPlatform` → `kIsDesktop || kIsAndroid`), searches
  `/data/local/tmp` and the app's own directory, checks the execute bit,
  and a missing binary is a **skip** in the cascade rather than a
  failure. So a user who can put a working yt-dlp on the device gets it.
- **Deliberately not implemented**: the Termux bridge (run yt-dlp inside
  Termux over `RunCommandService`). It needs six independent assumptions
  to hold (Termux installed, `RUN_COMMAND` permission granted, shared
  storage, the `am` background-service restriction, yt-dlp in Termux's
  PATH, Python in Termux) and **none of them can be verified without a
  device**. A half-working backend is worse than a clear "not
  installed". Revisit only with a device in hand.
- Full reasoning: `.ai/MEMORY.md`, "yt-dlp on Android".

### Real window transparency rendered black — fixed in runner (2026-10-06)
- Symptom: with Settings → Appearance → Transparent window ON (DB
  `transparent_window=1`, theme `background.transparent:true`, Hyprland/Wayland,
  blur enabled, app not in any `opaque` rule), the window ground rendered
  pure `#000000` instead of the desktop. Pixel-sampled, not eyeballed.
- Cause: `linux/my_application.cc` set the RGBA visual (alpha *allowed*) but
  never called `fl_view_set_background_color`, so FlView kept its default
  opaque-black clear color and every transparent Dart pixel composited over
  black inside the view — the compositor received an opaque frame. The current
  Flutter template (`flutter create`, same 3.35.2 engine) sets
  `fl_view_set_background_color(view, #000000)` explicitly and comments
  "e.g. #00000000 for transparent"; this repo's older runner template
  predates that call. Verified the symbol exists in the pinned engine
  (`fl_view.h:89`, `libflutter_linux_gtk.so` exports it).
- Proof chain: minimal probe app (`/tmp/opencode/transprobe`, transparent
  scaffold + RGBA visual + `#00000000` view background, no window_manager)
  shows the live desktop through the window on this machine — so the
  engine/compositor path works and the bug was ours alone.
- Fix: `fl_view_set_background_color(view, #00000000)` right after
  `fl_view_new` in `linux/my_application.cc` (unconditional — harmless while
  the app paints opaque, same rationale as the existing RGBA-visual comment).
  All Dart-side transparency code (`real_transparency.dart` and consumers)
  was already correct and needed no change.
- Verified: release rebuild → relaunch with switch ON → grim screenshot shows
  the live desktop (bright, Hyprland-blurred) through sidebar, settings and
  player; ground pixels no longer `#000000`. No Dart files touched, so the
  unit suite is unaffected by construction (not re-run). Do not reinvestigate
  the black-ground symptom — check the ON-state screenshot first.
- Rollout note: two stale system installs predate the feature
  (`/usr/local/share/spotube-custom`, `/usr/bin/spotube → /usr/share/spotube-bin`).
  The user-writable custom install was refreshed from the fixed bundle; the
  root-owned `/usr/share/spotube-bin` still needs a reinstall with sudo.
- Follow-up 2026-10-06: theme plugin updated to 1.3.0 per user request
  (`~/projects/spotube-theme`: `caelestia_theme_v130.ht`,
  `caelestia-plugin-v130.json`, `caelestia-shell-1.3.0.smplug`;
  surfaces.opacity 0.55 → 0.75, the only theme-side knob that matters in
  transparent mode since the host zeroes in-app blur and skips the veil
  there). Installed (extraction dir + `plugins_table` row, 1.2.0 deselected,
  cache re-keyed) and verified live with `transparent: true` intact. Note:
  live Caelestia glass overrides surfaces.opacity to 0.85 via
  `mergeShellPalette`, so 0.75 rules only when shell glass is absent.
- Follow-up 2026-10-06 (plugin-driven transparency): activation moved from
  host-switch-AND to plugin-request + user opt-out. Gate is now
  `linux && allow && loaded && theme.transparent == true` (strict: absent or
  null theme → opaque). `transparentWindow` column kept (no migration);
  fresh seeds write true, existing rows preserved; Settings relabeled to
  "Allow real transparency". Takeover audit: veil/blur skipping is physics
  (painting covers the desktop; BackdropFilter samples nothing), fixed the
  two real inconsistencies (bottom-player `surfaceBlur` now zeroed in real
  mode like the nav bar; track header gradient starts transparent in real
  mode). Base + Plain themes flagged (`transparent: true`, 1.1.0 artifacts
  rebuilt; 1.3.0 already flagged). Tests: `real_transparency_test.dart` is
  now the strict truth table (11 green), `caelestia_transparent_theme_test`
  pins all four artifacts (13 green). Verified live: absent-flag theme
  (Plain 1.0.0) + allow ON renders opaque stock — strict gate holds.
- Follow-up (real-mode veil): allowing real transparency used to drop the
  theme's background colour entirely (layer yielded to `SizedBox.shrink`).
  `ThemeBackgroundLayer` now paints the overlay veil in real mode (translucent
  `ColoredBox`, same parse+brightness-adapt path as fake mode) while the
  image/blur stay off — alpha composes, so the live desktop shows through
  tinted instead of fully clear; null veil stays clear. Pinned by
  `test/theme_background_veil_test.dart` (3 widget tests). Verified live by
  pixel elimination (ground `#101218` ≠ stock `#0c0e12`, no painted bright
  shapes from the lightning wallpaper ⇒ veiled-real, not opaque nor fake).
- Follow-up (theme/wallpaper switch black pop): the palette already fell back
  to the stale cache across reloads (`main.dart`), but the ground read
  live-only values that go null mid-reload — layer shrank, backdrop gate went
  false (opaque shadcn scaffold instead of wallpaper), gate blipped opaque;
  plus wallpaper swaps blanked the `Image` while decoding (`gaplessPlayback`
  defaults false). Fix: `themeBackdropUrlProvider` source, layer background
  select and gate flag all fall back to the cached theme while live loads
  (strict semantics kept: only explicit `true` activates, cold start with no
  cache stays opaque); layer `Image` gained `gaplessPlayback: true`. Note:
  watches are unconditional (same precedent as the palette fallback in main),
  so hermetic tests touching these providers must override
  `cachedThemeDefinitionProvider` explicitly — the real one needs
  SharedPreferences plus the initialized app logger. Pinned by new cases in
  `real_transparency_test` (cached flag/veto across reload), `backdrop_decode`
  (cached source across reload) and `theme_background_veil_test` (cached veil
  across reload, gapless assert); neighboring suites green.

### Backdrop does not track live wallpaper changes — not a Spotube defect, do not reinvestigate
- Symptom: changing wallpaper in Caelestia updates the desktop immediately but
  Spotube's `ThemeBackgroundLayer` only follows "when it applies".
- Cause is Caelestia's preview/apply split, not latency in our watch chain.
  Browsing the picker calls `Wallpapers.preview(path)`
  (`/etc/xdg/quickshell/caelestia/modules/launcher/WallpaperList.qml:61`), which
  only assigns QML properties (`services/Wallpapers.qml:19` —
  `current: showPreview ? previewPath : actualCurrent`, consumed by
  `modules/background/Wallpaper.qml:14`) and runs `caelestia wallpaper -p`,
  whose `get_colours_for_wall` prints JSON and writes nothing to the state dir.
  Only Enter → `setWallpaper` → `caelestia wallpaper -f` → `set_wallpaper()`
  writes `path.txt`, the `current` symlink, `thumbnail.jpg` and `scheme.json`.
  Spotube's sole signal is `Directory(state/wallpaper).watch()`
  (`lib/modules/theme_background/caelestia_shell_source.dart:140-150`), which is
  silent for the whole preview. There is no IPC either — the shell's
  `IpcHandler target: "wallpaper"` `get()` returns `actualCurrent`, not the
  preview. Closing the gap requires the shell to announce preview; nothing on
  our side can infer it.
- Residual apply-path cost, measured from the last real apply
  (`15:06:05.8707` path.txt+current, `.8711` thumbnail, `.9418` scheme.json —
  a 71ms burst): the backdrop used to trail this by the fixed
  `_themeEventWindow` of 300ms. **That is now removed for the wallpaper watch**
  — `watchBackground()` emits on a change of the resolved path rather than on a
  quiet window (`_distinctPathSignal`), because the burst contains four events
  and only one real change, so equality collapses it without costing time.
  `watchTheme` keeps the debounce: a palette recompute rebuilds the tree, and
  the four events there are not self-distinguishing. Verified by
  `test/shell_wallpaper_signal_test.dart` (4 cases, real inotify on a temp
  dir), which fails against the old debounced form at 302ms vs the 300ms bound.
  Remaining latency after apply is one `ResizeImage` decode, bounded and cheap
  here — window longest side 1038 logical px → `quantizeBackdropSide` → 1280,
  against a 1920x1080/208KB source.

### Liked Songs pin missing from sidebar offline — fixed (working tree)
- Symptom: pinned Liked Songs showed in Library but not the sidebar when
  offline. Root cause: the synthetic entry was gated on live
  `metadataPluginUserProvider` data (`me == null ? null`), and `user.me()`
  is a Hetu VM invoke with no snapshot fallback
  (`lib/services/metadata/endpoints/user.dart:13-19`), while the Library
  page gates on `isOnlineProvider` (defaulting true) — the two diverged.
- Fix: shared `resolveLikedTracksPlaylist`
  (`lib/modules/playlist/liked_playlist_synthetic.dart`) used by the
  sidebar, the sidebar order dialog and the Playlists page. While signed in
  (`metadataPluginAuthenticatedProvider`, local sync state, true offline) a
  null profile falls back to an anonymous owner instead of dropping the
  entry; logged out still hides it. Tracks come from the existing
  `savedTracks` snapshot (stale-while-revalidate), so no new DB mirror and
  no new network fetch from nav widgets. Also added the previously-missing
  `likedTracksPlaylist`/`showLikedOffline` memo deps in `UserPlaylistsPage`.
- Verified: `fvm flutter analyze lib` clean; new
  `test/liked_tracks_synthetic_test.dart` (5 cases); full suite
  1197 passed, 0 failed. Note: `test/` is gitignored, so the new test is
  local-only.
- Live-device offline run (airplane mode, seeded snapshot) still pending.

### Sidebar pin cover-tap plays the playlist — implemented (working tree)
- Pinned rows navigated only (`sidebar.dart` pin block). Cover click now
  plays via `SidebarPinTile`
  (`lib/modules/root/sidebar/sidebar_pin_tile.dart`, per-pin widget so hook
  order is stable as pin count changes); label still navigates. Rail mode
  included (cover plays, page reachable via overflow → Playlists).
- Shared `usePlaylistPlay` (`lib/modules/playlist/use_playlist_play.dart`,
  repo `useXxx(WidgetRef)` record pattern) extracted verbatim from
  `PlaylistCard` — pause/resume toggle, page-1 load + tail append, history,
  Connect remote branch — so card and pin share one path. Verified
  load-bearing details against source: single outer tap recognizer
  (shadcn `navigation_bar.dart:1607-1663` + `clickable.dart:785-787`), so the
  inner cover tap wins the arena and never double-fires navigation; the
  desktop drag overlay grabs on movement only, so taps still reach the cover.
- Offline: Liked serves the `savedTracks` snapshot; regular playlists fall
  back to `mirroredPlaylistTracksProvider` (same rule `PlaylistPage`
  renders). `.future` on that stream resolves on the first emission —
  proven in riverpod 2.6.1 source (`onData` completes the completer, then
  nulls it). Empty mirror rethrows the network error so the tap toasts
  (`you_are_offline` / `something_went_wrong`) instead of loading nothing —
  a deliberate micro-change that also covers the card's old unhandled throw.
- `SidebarReorderableItem.row` widened `NavigationButton` → `Widget`
  (pass-through only: opacity/drag children); `SideBarTiles` gained an
  optional backing `playlist`; `_pinCoverSide` moved to
  `sidebar_pin_cover.dart` as `sidebarPinCoverSide`. Overlay is a fixed-size
  Stack (no Expanded/LayoutBuilder), so the scaffold-footer intrinsic
  constraint still holds.
- Tests: `test/sidebar_pin_play_test.dart` (4 container tests: liked routing,
  network-wins, mirror fallback order, unmirrored throws). Test-only
  findings, both harness-side: StreamProvider `.future` needs no widget pump
  (fetch helpers take a `read` tear-off), and `AppLogger.initialize(false)`
  + prefs stub are required as in the download suites.
- Verified: `flutter analyze` clean; full suite 1201 passed, 0 failed
  (1197 prior + 4 new). `test/` is gitignored, so the new test is local-only.
- Manual check still pending: cover tap plays + pause toggle, rail mode,
  reorder-drag unaffected, offline mirrored pin plays downloaded subset.

### Optimization/cleanup audit execution (2026-09-27)
- Status: Implemented + tested (PRs 1–5 of the audit plan; uncommitted).
- 1189+ tests green, `flutter analyze` clean for lib/; the single pre-existing
  radio-test failure unchanged. Full detail in `.ai/CHANGELOG.md`
  ("Optimization/cleanup audit execution").
- Conclusion: UA-pin LRU (playing track's UA no longer re-randomized by the
  >16-entry bound clear), EncryptedKvStore silent-fallback diagnostics,
  quality_presets discarded-async-error fix, `_getSourcedTrack` orElse
  (live playback check pending), clearAll controller close, pagination engine
  deduplicated (dead non-autoDispose twin deleted), `trackFileStem` single
  source of truth, three layering moves, cascade/glance/theme-cache
  diagnostics, 19 dead icon constants + 1 dead dep (`win32_registry`) + 1
  one-call-site dep (`http`) + 4 dead assets removed, PERFORMANCE.md C4
  stale entry fixed.
- Not reproven by tests (RUNTIME VERIFICATION REQUIRED): the UA-pin 403 count
  on a long remote session (>17 distinct tracks, needs URL-bearing manifests)
  and the `_getSourcedTrack` 500→404 status change in a live playback.
- Corrections to the audit's own findings: `FakeData.album`/`.playlist` were
  not dead (same-file refs); `fluentui_system_icons` uses 4 constants, not 6;
  the scrobbler gate's real test blocker is the LastFM static (recorded in
  TODO.md).

### Roadmap PR 5 — startup deferral (R-01, R-02 landed; R-03 blocked, R-04 rejected)
- Status: Done, measured. Commits `e9e0eef4`, `dc4f46cc`, `6d7e6d8a`, `02fff4db`.
- Date: 2026-09-26
- The splash gate is now evaluated in `build` (was a 50 ms poll): app visible at
  ~50 ms instead of 189–209 ms from process start, on top of R-01's un-awaited
  `WindowManagerTools.initialize`. The eight keep-alive provider warm-ups are
  `listenManual` subscriptions in a post-frame effect behind that gate — measured
  as a ~0 ms change, kept for cold-start shape rather than a warm-start number.
- Constraint discovered: the gate opens on `cachedThemeDefinitionProvider`
  (SharedPreferences only). Do not gate anything the theme-resolution path itself
  needs behind the gate, or a cold start waits for the 6 s cap.
- Full before/after table: `.ai/PERFORMANCE.md` "Roadmap PR 5".

### "Too long to fetch data from Spotify and music" — 3 defects fixed
- Status: Investigated + fixed (Phases 1, 2-B host half, 3-D)
- Date: 2026-09-23
- Symptom reported as three things at once: music slow to start, library/search
  slow, everything sluggish. Read-only diagnosis first (session log at
  `~/.local/state/spotube/.spotube_logs`, DB opened `mode=ro`), then fixes.
- **A — the fallback cascade crashed in production.** `resolveFirstAvailable`'s
  `attempt` seam was `Function(SourceCandidate)?`, `resolve` is
  `(SourceCandidate, SpotubeFullTrackObject)`, so `final run = attempt ?? resolve`
  had static type **`Function`** (the LUB of unrelated function types) and
  `run(candidate)` was a legal *dynamic invocation*. 11× `NoSuchMethodError` in
  the log. `flutter analyze` cannot flag it: since Dart 2.13 function-typed
  variables are removed in null-safe code, a call on a `Function` receiver always
  compiles dynamically, and `avoid_dynamic_calls` fires on `dynamic` receivers
  only. Root cause of the class, not of the line: **every test passed `attempt`
  and production never did**, so the untested shape was the only one that ran.
  Fixed by a `SourceResolutionAttempt` typedef that both `attempt` and `resolve`
  are checked against, making the bug un-compilable; the new tests are written in
  the *production* shape (no `attempt`) and were proven to fail before the fix.
  Lesson for this repo: a `@visibleForTesting` parameter that production omits
  makes the production path the untested one — test that path too.
- **B — nothing bounded a metadata request.** `hetu_std`'s `HttpClient` passes
  Dio a **null `BaseOptions`** when constructed with no options, so
  connect/receive/send timeouts are all infinite, and the Spotify plugin builds
  both of its clients that way (`core.ht`, `auth.ht`). Metadata never touches
  `globalDio`, so its 15s/30s/15s is irrelevant here. A stalled-but-open Spotify
  connection therefore spun forever. Host fix: `runGated` now wraps every attempt
  in `.timeout(metadataRequestBudget)` (15 s), chosen as the choke point because
  both `fetchGated` and `fetchWithRateLimitRetry` already funnel through it —
  preferred over the planned 45-site `.invoke()` refactor. A timeout is
  deliberately **not** a gate strike (a stall is not a throttle, and closing the
  gate would suppress unrelated reads); it is not cooldown-retried either.
  Two honesty notes: `.timeout` **abandons the await, it does not cancel** the
  in-VM Dio call (Hetu is in-process), and non-gated paths (`scrobble`, `theme`,
  `core.checkUpdate`, `user.me`) stay uncapped — the plugin-side fix is what
  covers both. That plugin change (2 `HttpBaseOptions`s) compiles clean but is
  **not installed** — re-confirmed from the live registry, not from a guess:
  `plugins_table` in `~/.local/share/oss.krtirtho.spotube/db.sqlite` (the real DB
  path; the app's own `~/.local/share/spotube/` holds only webview state, and
  columns are snake_case) still reads `0.2.3-inline`, and a runtime error naming
  `spotube-plugin-spotify-audit/src/segments/core.ht` proves nothing, because
  Hetu bakes source paths into the pre-edited bytecode it shipped on 2026-09-22.
- **C — nothing bounded the source cascade, and it ran twice per failed track.**
  Engine and manifest calls were untimed (`Process.run` in `flutter_new_pipe_extractor`
  / `yt_dlp_dart`, an isolate reply in `youtube_explode_engine.dart`), and
  `playbackFallbackUrls` was walked by both the HEAD preflight and the stream GET
  for the same dead URL. Now: `sourceCandidateBudget` 20 s per candidate,
  `engineCallBudget` 15 s per engine crossing (with `_pendingCalls`/reply-port
  cleanup on the explode side), `fallbackCascadeBudget` 45 s returning a partial
  list, and a 5 s/16-entry `fallbackUrlsFor` memo keyed `track.id|primaryUrl`.
  A timeout is classified as an engine failure, never a `TrackNotFoundError`, so
  it cannot become a cached tombstone. What is *not* fixed: `.timeout` abandons
  the future but the CLI process runs on — bounding is not cancelling.
- **C-regression — that same refactor broke yt-dlp, and the suite did not.**
  Moving `extractInfo(...) as List` inside the new closure re-reads naturally as
  `as Future<List>`, which casts the *future*; generics are reified, so
  `Future<dynamic>` fails it at runtime. 9 times in one session log, on
  `getStreamManifest` — no manifest, so no playback. Neither `analyze` (a
  downcast from `Future<dynamic>` is legal) nor the suite (604 green) could see
  it, and `YtDlp.instance` is a singleton with no seam. Caught only by installing
  the release build and reading `~/.local/state/spotube/.spotube_logs`. Two
  standing consequences: cast the awaited value inside a `withinEngineCallBudget`
  closure — `test/engine_call_budget_test.dart` now bans `as Future<` under
  `lib/services/youtube_engine/` — and **engine call sites have no unit coverage,
  so any change there needs a live run before it is called done**.
- **D — the cascade re-resolved the candidate that just failed.** All three
  `SourcedTrack` rebuild paths dropped `sourceCandidateKey`, so
  `primaryKey == ''` matched nothing and the `continue` skip never fired; after
  any CDN-URL refresh the fallback walk re-searched and re-fetched the manifest
  for the candidate already playing. One line each at `copyWithSibling`,
  `swapWithSibling`, `refreshStream`; covered by
  `test/source_candidate_key_preserved_test.dart` (3 cases, all red before).
- Not a code fix, and the likeliest cause of "everything sluggish at once":
  recurring Spotify **401**s (10× in the log across sessions) on the Home browse
  path. `isRateLimitedError` matches 429 only, so nothing backs off and every
  provider sharing that auth state re-probes. Needs re-authentication in
  settings. Do **not** fold 401 into the rate-limit gate — a quota backoff cannot
  fix credentials and the gate would mask the real cause.
- **E — a warm saved list waited on the network before drawing.** `buildSavedList`
  awaited `fetchWithRateLimitRetry` inside `build()` and read
  `library_snapshot_table` only in the `catch`, so the rows that were already on
  disk appeared after the retry chain. Reordered to stale-while-revalidate;
  `SavedListCacheMixin.revalidation` is the test seam. A failed revalidation is
  now logged and not surfaced, and the patch is skipped unless the state is
  still the exact page that build served.
- **F — a 401 dumped a raw `DioException`.** `isCredentialError`
  (`rate_limit.dart`, next to `isRateLimitedError`) accepts the typed and the
  stringified VM form, and `ErrorBox` routes it to `spotify_login_expired`,
  which names the action instead of the status code. Kept out of the
  rate-limit gate on purpose: a quota backoff cannot fix credentials, and
  closing the gate would hide the cause behind a "slow" label. Covered by
  `test/rate_limit_test.dart` (classification + "a 401 is not retried and
  leaves the gate open").
- **G — nothing measured fetch latency**, which is why "sometimes slow" was only
  inferable from things that *throw*. `PerfCounters` now covers
  `metadata.request[.timeout]`, `source.resolve[.timeout]`, `engine.*[.timeout]`,
  `playback.fallbackCascade[.budget]`, `playback.fallbackUrlsReused` and
  `dio.<host>` (a `_TimingInterceptor` on `globalDio`, previously
  interceptor-free). Observation only — no behaviour sits behind a counter.
- Tests for the three ceiling layers: `test/source_engine_fallback_test.dart`
  (hang → next candidate; timeout never a miss),
  `test/playback_fallback_memo_test.dart` (one cascade per track start, re-signed
  URL misses, window expiry), `test/rate_limit_gate_rollout_test.dart`
  (metadata budget). The first two were proven red before the fix.

### "Available plugins" empty on Android — fixed 2026-09-22
- Symptom: a phone install showed only the two bundled plugins and no way to get
  the rest (notably `sonic-liberation/spotube-plugin-spotify`, which is not
  bundled — `assets/plugins/` has exactly two `.smplug` archives and
  `_loadDefaultPlugins` installs exactly those).
- Cause: `MetadataPluginRepositoriesNotifier.fetch` awaited GitHub *and*
  Codeberg in one `Future.wait`, so a single unreachable registry rejected the
  whole request, and the plugins screen reads
  `pluginReposSnapshot.asData?.value.items ?? []` — an `AsyncError` renders as an
  empty section with no message and no retry. Secondary: the old `_hasMore` write
  was keyed `response.requestOptions.uri.host` (`api.github.com`) while the read
  used `"github.com"`, so an exhausted GitHub source was re-queried on every
  page, and `.any()` short-circuited before the second host was recorded.
- Fix: each registry is queried into a `_IndexSource` (response **or** failure),
  one dead source degrades to a log line (`plugin index: <host> unavailable`) and
  still returns the other's items; only an all-failed load stays an error, which
  the screen now renders as `ErrorBox` with a retry that invalidates the
  provider. Payload parsing no longer assumes `topics` / `owner` / `html_url`
  exist, and URL-less entries are dropped rather than listed with a dead Install
  button. Proven by `test/plugin_index_partial_failure_test.dart` (6 cases
  against a fake `HttpClientAdapter` on `globalDio`).
- Live facts from the same pass: `topic:spotube-plugin` returns 7 repos,
  `codeberg.org/api/v1/repos/search` answers `{"ok":true,"data":[]}` (valid,
  empty), and the Spotify plugin's release 0.2.2 carries `plugin.smplug` — so
  pasting its repo URL into the plugins screen installs it without the index.
- Not the cause: `INTERNET` is in the manifest, `globalDio` is bare (no UA or
  proxy to differ per platform), and the rate-limit gate never touches this
  notifier.

### Tracks reported "not found" although they exist on YouTube
- Status: Investigated + fixed
- Date: 2026-09-21
- Evidence: repro case "Wassup" (Flawed, Slay™, SÎM; youtube `KENf509XTjI`), run
  through the app's own bundled `NewPipeCLI`:
  `--search "Wassup Flawed, Slay™, SÎM" --content-filters videos` → **0 results**
  (deterministic, alternating A/B runs), the same query *unfiltered* → 20 with the
  correct video at rank 0, and an ASCII variant + filter → 20 rank 0. A single ™
  or Î costs 19 of 20 results; both together → 0.
  Dropping `--content-filters` is *not* an option at the app boundary: NewPipe's
  unfiltered page mixes in CHANNEL rows whose `description` is a plain String, and
  `flutter_new_pipe_extractor`'s `_$ChannelSearchResultItem.fromJson`
  (models.g.dart:185) casts it to `Map<String, dynamic>`, so one channel row throws
  and the whole search fails ("Wassup Flawed" unfiltered → 5 such rows). Measured
  with the filter: 0 CHANNEL / 0 PLAYLIST rows.
  `source_match_table` meanwhile held 604 cached matches whose winners were wrong
  videos ("A$AP Rocky - Wassup", "Garhkumaon ft. … Flawed"), and 2 `'{}'` tombstones.
- Conclusion: recall, not availability. YouTube's type-filtered search treats a
  verbatim credit string as near-exact. `matches()` empty is *definitionally*
  "does not exist" to `fetchSiblings`, which wrote a 6h tombstone — one bad page
  became six hours of "not found". Independent second cause: `audio_source.ht`
  searches `track.isrc` before the text query (an ISRC is never in a video title,
  and a junk ISRC page suppresses the plugin's own empty-result fallback); third:
  `rankResults` compared `channelName.toLowerCase() == artist.name` — needle never
  lowered, so the channel-credit point was dead for any capitalized name and
  ranking collapsed onto title-substring noise.
- Fix: query-variant ladder instead of dropping the filter — the `videos` filter
  stays because it is the only thing keeping the third-party deserializer from
  crashing on channel rows.
  `SourcedTrack.matchWithQueryVariants` escalates the *track object* only on a
  clean-empty answer — variant 1 drops ISRC + credit symbols, variant 2 keeps the
  primary artist — and a thrown search still propagates, so blockage is never
  negative-cached. `rankResults` normalizes both sides, including NewPipe's
  "X and N more" channel suffix. Existing tombstones expire via the TTL; wrong
  cached matches were left alone (user data).
- Files: `lib/services/youtube_engine/newpipe_engine.dart`,
  `lib/services/sourced_track/sourced_track.dart`,
  `lib/services/sourced_track/source_resolver.dart`,
  `test/source_query_variants_test.dart`
- Verified in-app (debug build, filtered path): `source_match_table` gained
  `sKHv6S1y_j0` ("Wassup", official release — variant 1's only hit) and
  `KENf509XTjI` ("Wassup ft. Slay, SIM || Sounds Like Home" — the reporter's own
  link), plus `Smack`/`Balanced`/`WASSUP MY G`, on tracks that previously
  produced 0 results. NewPipe still hands back only muxed itag 18 for them.
- Not fixed / open: NewPipe stream extraction currently returns
  `audioStreams: []` for every video probed (only muxed itag 18, 360p) while
  `yt-dlp` on the same machine returns 5 audio-only formats for the same video —
  a PO-token-gated backend, i.e. an engine-choice problem, not a search one.
  Forking `spotube-plugin-youtube-audio` was evaluated and rejected: the query
  ladder, the filter and the ranking all live in Spotube, and a fork would fix
  only that one plugin.
  Upstream candidate bug (not filed): `flutter_new_pipe_extractor`
  `_$ChannelSearchResultItem.fromJson` hard-casts `description` to a Map although
  NewPipe returns a String for channel descriptions — any unfiltered search that
  contains a channel row is unparseable. The `videos` filter cannot be dropped for
  that reason; it is now the *fallback* tier rather than the only tier (see below),
  and both tiers were measured to return 0 channel rows.

### NewPipe search returned video versions and fan channels ahead of the recording
- Status: Investigated + fixed
- Date: 2026-09-22
- Evidence: run through the app's own bundled `NewPipeCLI` on
  `--search "Tum Hi Ho Arijit Singh"`. The `videos` category (what the engine used
  unconditionally) ranked a Hindi-title lyric recap from T-Series at 505M views
  *above* the studio recording, and carried a "Slowed + Reverb" edit at 60M views on
  the same page; `music_songs` returned the recording at rows 1–2. Confirmed on 5
  queries — `music_songs` answers the studio upload first every time, with 0 CHANNEL
  rows and no `duration: -1` rows. Android parity holds: `NewPipeDartImpl.kt:59-77`
  passes filter strings verbatim to `searchQHFactory`, the same upstream extractor.
  Two rules that look obvious and are wrong:
  **`uploaderVerified` is not the "original channel" signal.** Studio uploads sit on
  auto-generated Topic/label channels that report `verified: false` (measured: BTS,
  Ed Sheeran, Arijit Singh), while lyric channels such as 7clouds report `true`.
  Rewarding the badge demotes the correct answer, so the *category* carries the
  signal and the badge stays unused.
  **`officialMusicRegex` was rewarding lyric videos.** Its `lyric\svideo`
  alternative meant `(Official Lyric Video)` collected +1, then +2 for naming the
  track — 7 to a plain-titled recording's 4.
- Conclusion: quality, not recall — the right video was on the page but ordered
  behind edits. Ordering had to move *inside* the engine: the Hetu plugin reads only
  `id/title/authors/duration/thumbnail/externalUri`, so no added bridge field can
  express "this tier is better".
- Fix: `NewPipeEngine.searchVideos` queries `music_songs` first and returns it alone
  when its titles actually overlap the query (one request, the common case); it
  falls back to `videos` and merges the two tiers when they do not. Tier placement is
  decided by the same relevance test, so an irrelevant songs page goes *behind* the
  videos page rather than leading on category alone. Rows are demoted (live, Shorts,
  unknown length, channel not named in the query), never dropped.
  **The ISRC path is the trap and is exempted:** the plugin searches `track.isrc`
  before any text query, and YouTube treats an ISRC as prose — `music_songs` answers
  11–20 unrelated songs where `videos` correctly answers nothing. Only a clean empty
  answer lets the variant ladder reach the text query, so songs-first on an ISRC
  converts a miss into a confident wrong match. `_isIsrcQuery` routes those to
  `videos` alone.
  Shared `rankResults`: narrowed `officialMusicRegex`, added an altered-version
  penalty (slowed/reverb/sped up/8d/karaoke/cover/lyrics/unofficial, −4) and a
  duration-tolerance penalty vs `track.durationMs` (>15s, −2). Also removed the
  `onlyContainsEnglish` bypass in `fetchSiblings`, which skipped ranking entirely for
  Latin-script titles — i.e. for exactly the tracks above. `SourceResolver.resolve`
  already always ranked; the helper became dead and was deleted.
  Latent bug fixed in passing: NewPipe reports unknown duration as `-1` in a
  non-nullable `int`, so rows silently became "minus one second".
- Files: `lib/services/youtube_engine/{newpipe_engine,youtube_engine}.dart`,
  `lib/services/sourced_track/sourced_track.dart`, `lib/utils/service_utils.dart`,
  `test/newpipe_search_tiering_test.dart` (new), `test/source_query_variants_test.dart`
- Verified: `flutter analyze` clean; suite green at 548 tests, incl. 13 new tiering
  cases built from the measured pages. `NewPipeEngine` gained an injectable
  `NewPipeSearch` seam, which is why `searchVideos` has coverage at all for the first
  time.
- Not fixed: a cached wrong winner survives up to `kSourceMatchCacheTtl` (6h) or until
  `swapWithSibling`; no migration or tombstone purge, matching the earlier decision to
  leave cached matches as user data.

### yt-dlp / YouTubeExplode engines failing during the source cascade
- Status: Investigated + fixed
- Date: 2026-09-21
- Evidence: `SourceResolver._orderedEngines` + `playbackFallbackUrls` try every
  engine, so an engine that cannot search silently costs the whole cascade. Run
  through the engines' own `searchVideos` on the "Wassup" repro:
  yt-dlp returned **0 / 1 / THREW** for the verbatim query, variant 1 and variant 2
  — i.e. it died on exactly the page that contained the answer. Cause: flat
  search rows carry `channel_id: null` and `duration`/`view_count` possibly null,
  and `YtDlpEngine._parseInfo` built youtube_explode_dart's `Video`, whose
  `ChannelId` is required-and-validating and whose `Engagement.viewCount` is a
  non-null `int`. The row with the missing identity was `KENf509XTjI`, the correct
  music upload — the engine threw on its best candidate.
  YouTubeExplode: 0 / 1 / 20 (THREW `TransientFailureException` once on the
  verbatim query — a bot-check, correctly propagated rather than cached as empty).
- Conclusion: strict library models at a boundary whose input is legitimately
  partial. Recall, not availability, same shape as the search-query bug.
- Fix: `YouTubeEngine.searchVideos` now returns a Spotube-owned
  `YouTubeSearchResult` (id/title/author required, everything else nullable)
  instead of `Video`. yt-dlp gained a tolerant `parseSearchResult`; NewPipe's
  dropped the `Uri.parse(...)['v']!` crash (rows without a watch id are skipped,
  not fatal) and its inverted `isLive`; Explode maps through
  `YouTubeSearchResult.fromVideo`. `metadata.dart` passes the same map keys to the
  plugin VM, so the Hetu contract is unchanged (verified: the YouTube Audio
  plugin's bytecode reads only `id`, `title`, `authors`, `duration`, `thumbnail`,
  `externalUri` — never `viewCount`/`isLive`/`uploadDate`).
- Files: `lib/services/youtube_engine/{youtube_engine,newpipe_engine,yt_dlp_engine,youtube_explode_engine}.dart`,
  `lib/services/metadata/metadata.dart`, `test/youtube_engine_search_results_test.dart`
- Verified: post-fix engines return 0 / 1 / 10 (yt-dlp) and 0 / 1 / 20 (explode)
  for the same three queries — the variant ladder resolves on variant 1 for both,
  as it does for NewPipe. Suite 393 → 401 green.
- Not fixed: `YtDlpEngine._parseInfo` (the `getVideo` path) still parses
  `upload_date` as epoch seconds, so a full-video lookup yields a 1970 date. Left
  alone: it is data quality, not recall, and no installed plugin reads it.

### Playback "not found" never widened to the other engines
- Status: Investigated + fixed
- Date: 2026-09-21
- Evidence: the cascade existed in three places and the playback path used none of
  them. `SourcedTrack.fetchFromTrack` threw `TrackNotFoundError` straight out of
  the configured engine and wrote a `'{}'` tombstone, so the miss was cached for
  the TTL; `TrackNotFoundError` had no cascade handler anywhere;
  `resolveTrackWithFallback` (which did walk `candidates()`) was dead code; and
  `playbackFallbackUrls` can only reroute a URL that already exists, so it never
  ran for this case. Second defect on the same path: the fallback list compared
  `candidate.key` against a hand-built `slug:YoutubeClientEngine` string, which
  never matched the real `slug@version:NewPipeEngine` format — so it re-searched
  the engine that had just failed and burned one of its three slots.
  Only the download worker (`download_manager_provider.dart`) walked the cascade.
- Fix: `SourceResolver.primaryCandidate()` is now the single source of the
  "primary" key (used by both `_pluginFor` and `fetchFromTrack`);
  `engineFallbackCandidates()` builds the widening list — same plugin, every other
  available engine, in configured source-priority order;
  `resolveFirstAvailable()` walks it with a deliberate failure taxonomy:
  `TrackNotFoundError` = a miss (tombstone allowed after all of them), any other
  throw = blockage (rethrown, never cached as absence). Dead
  `resolveTrackWithFallback` deleted. `fetchFromTrack` wraps its own search the
  same way: an engine that cannot answer widens like a miss but rethrows the
  original error when nothing resolves, so a backend outage still cannot become
  a cached "not found".
  Plugin-crossing stays out of this path on purpose: the cache read in
  `fetchFromTrack` always streams the saved id through the *default* plugin, so a
  match from another source would be unplayable on replay. Engines are safe to
  mix because a source match is a YouTube video id.
- Files: `lib/services/sourced_track/{source_resolver,sourced_track}.dart`,
  `test/source_engine_fallback_test.dart`
- Verified: 9 unit tests (widening order, source-priority order, plugin absent →
  no candidates, first-hit-stops, throw ≠ miss, broken engine cannot tombstone,
  recovery after a break, all-empty = real miss). Suite 401 → 410 green,
  `flutter analyze` clean, debug build boots clean.
  Live probe of the same ladder against the real engines for the repro track
  (queries `Wassup Flawed Slay™ SÎM` → `Wassup Flawed Slay SÎM` →
  `Wassup Flawed`): yt-dlp and YouTubeExplode both answer 1 hit on a later
  variant and rank `sKHv6S1y_j0` first, and yt-dlp yields 7 audio-only streams
  for `KENf509XTjI` — i.e. the engines the user did not pick can resolve what
  the picked one cannot, which is the case this cascade now covers. NewPipe
  cannot be driven outside the app (`Not initialized` — its extractor is set up
  during Flutter startup), so the end-to-end "primary misses → another engine
  plays it" run still needs one playback in the app.

### Playback 403 infinite-loading loop
- Status: Investigated + fixed
- Date: 2026-09-20
- Evidence: Runtime log — every googlevideo stream URL (all itags/containers)
  returned 403; URLs carried `c=ANDROID` (YoutubeApiClient.android). Fresh
  refreshes also 403'd → not staleness; upstream client rejection.
- Conclusion: Two stacked bugs. (1) youtube_explode's ANDROID client streams
  are 403'd by YouTube (bot/PO-token enforcement), and the engine's manifest
  fallback never fired because Spotube passes `ytClients` explicitly (the
  lib's internal `ytClients == null → tv` retry was unreachable). (2) The
  `validStreams.isEmpty` fallback in `refreshStream` returned the *unvalidated*
  re-fetched list (the same 403 URLs), so a dead manifest kept refreshing
  forever instead of surfacing an error.
- Fix: Engine primary clients now `[ios, androidVr]` (android dropped) with a
  fallback to `[YoutubeApiClient.tv]` (auto watch-page signature decoding)
  when the primary manifest fails or yields no eligible audio streams; the
  refreshStream fallback re-validates the re-fetched manifest and throws
  `NoValidStreamError` when all URLs are still rejected.
- Files: `lib/services/youtube_engine/youtube_explode_engine.dart`,
  `lib/services/sourced_track/sourced_track.dart`,
  `lib/services/sourced_track/exceptions.dart`

### Hetu plugin VM churn
- Status: Investigated + fixed
- Date: 2026-09-19
- Evidence: Logs showed the same plugin module compiling at many distinct
  timestamps; RSS climbed. After fix: `to compile` flat, RSS plateaued.
- Conclusion: Fallback rebuilt VMs per stream request; fixed via lazy fallback +
  global `(config, engine)` VM cache + theme VM memoization.
- Files: `lib/services/sourced_track/source_resolver.dart`,
  `lib/provider/server/routes/playback.dart`

### Lyrics sync lag
- Status: Investigated + fixed
- Date: 2026-09-19
- Evidence: Exact-second map lookups desynced highlight from music.
- Conclusion: Switched to binary search / index-based active line.
- Files: `lib/modules/lyrics/use_synced_lyrics.dart`,
  `lib/pages/lyrics/synced_lyrics.dart`, `lib/provider/lyrics/synced.dart`

### Position-tick storm
- Status: Fixed (in git history)
- Evidence: Commit `b5a0933d` "perf: throttle position ticks, buffer early
  notifications, cache sponsor segments".
- Conclusion: Position ticks throttled; early notifications buffered.

### Local-library scan materialization
- Status: Fixed (in git history)
- Evidence: Commit `d29a8d22` "perf: bound local-tracks scan concurrency, hoist
  temp dir, cancel stale scans".
- Conclusion: Scan is streamed/bounded, not materialized.

### Queue mutation batching
- Status: Fixed (in git history)
- Evidence: Commit `1dd4b1b9` "perf: batch queue mutations to one sync per op".
- Conclusion: Queue writes batched.

### Migration hardening
- Status: Fixed (in git history)
- Evidence: Commit `d190c603` "harden migrations v7-v12, quarantine corrupt rows
  (schema v12)"; migration tests green.
- Conclusion: Migrations guarded per-step, verified per version pair.

### Player rebuild scoping
- Status: Fixed (in git history)
- Evidence: Commit `195623f3` "scope audioPlayerProvider watches to consumed slices".
- Conclusion: Hot player state uses scoped watches.

### Sourced-track / cache lifecycle
- Status: Fixed (in git history)
- Evidence: Commits `423b38b9` (bound sourcedTrack cache, close-before-rebind,
  pref diffing), `6e37a8c5` (stream cached audio, bounded download retry, source
  TTL, single-shot fetchAll).
- Conclusion: Retention bounded; server close-before-rebind; prefs diffed.

### Correctness remediation pass (16 audit items)
- Status: Implemented + tested
- Date: 2026-09-20
- Evidence: 283 tests green, `fvm flutter analyze` clean; new suites
  `playback_cache_mirror_test`, `plugin_lifecycle_test`, `download_cancel_test`,
  `source_quality_fallback_test`, `local_library_rescan_test`,
  `local_artwork_test`; extended `chunk_download_test`,
  `download_first_playback_test`, `stream_validation_test`,
  `position_throttle_test`. Full detail in `.ai/CHANGELOG.md`.
- Conclusion: cache mirroring, plugin VM lifetime, download cancel/retry, proxy
  headers, quality fallback, pref-driven rescan, history stats, prewarm storm,
  server rebind, connect pairing, global subscriptions, logging init, artwork
  degradation, downloaded-file lookup, sleep timer and one dead-code item all
  addressed.
- Not reproven by tests (source-verified only): server rebind chain, connect
  fail-closed/pruning, global subscription cancel, logging lazy path, sleep
  timer re-arm (its callback calls `exit(0)`, so a test would kill the runner).
- Sub-claim downgraded: "per-request download-dir walk is a bottleneck" —
  measured ~0.24 ms for 5,000 files on tmpfs; see `.ai/PERFORMANCE.md`.

### Playback mirror + bundled plugin update correctness — fixed 2026-10-20
- Status: Fixed + tested
- `playback_cache_mirror.dart`: attach failures release the reservation;
  finalization always closes the response and releases the slot; the slot is
  held through `.part` rename; cleanup deletes before releasing; a throwing
  `onComplete` cannot leave the stream open or invalidate the completed cache.
- `metadata_plugin_provider.dart`: bundled updates detect a plugin `version`
  bump (not just `pluginApiVersion`); plugin identity uses name+author, not
  slug; updates UPDATE the existing row in one transaction (id and all
  selected/default flags preserved) instead of remove-then-add; extraction
  writes to `.staging-*` and promotes via a `.backup` swap, restoring the old
  directory on failure and recovering an interrupted swap.
- Evidence: `test/playback_cache_mirror_test.dart`,
  `test/plugin_extraction_test.dart`, `test/plugin_update_test.dart`; mirror,
  plugin, radio and download suites green. See `.ai/CHANGELOG.md` (2026-10-20).
- Residual: a hard kill while writing a staging directory leaves an orphan
  `.staging-*` (never registered; harmless). A same-version archive rewrite
  updates the bytecode but not row metadata when the version is unchanged.

## Currently Investigating

- None. PR 8 (C4) was **measured and left unimplemented** — see the
  "Remote manifest resolution" entry in `.ai/PERFORMANCE.md` for the 1.4–1.8 s
  per-resolution number, why prewarm + bounded retention already cover the
  dominant path, and the re-entry condition (a session where manifests actually
  carry URLs, so an `expire`-derived TTL can be tested).

### Downloads / playlists optimization plan — Phase 0 landed, 1+ not started
- Status: Phase 0 (baseline commit + harness) complete on branch
  `opt/downloads-perf`. Phases 1–4 (the enumerated optimizations F1–F15) are
  **not** started. Do not run them until each is individually re-justified
  against a Phase 0 measurement — the plan the user pasted was accepted
  with the caveat "only execute these if you feel necessary", and Phase 0 is
  the only piece that obviously was.
- Two premises in the pasted plan that turned out wrong, so future sessions
  do not re-derive them: (a) `lib/services/playback_cache_mirror.dart` **does**
  exist, contrary to an early read of this file — Phase 2.3 is real work, not
  a stub chase; (b) Phase 1.5 proposes a third `@TableIndex` on
  `playlist_download(trackId)`, but the table already carries
  `unique_playlist_download(playlistId, trackId)` and
  `playlist_download_order(playlistId, position)`, and the join in
  `watchMirroredPlaylist` rides on `track_download.trackId UNIQUE` —
  re-measure before adding a migration.
- Phase 0 commit: `feat(downloads): baseline (pre-optimization)` on
  `opt/downloads-perf`, 56 files / +5864 / −1642. Includes playlist
  mirroring (schema v16), offline library + volume-control visibility
  (schema v17). Analyze clean, 666/666 tests pass.
- Phase 0 harness: two new tests in `test/download_playlist_dedup_test.dart`
  ("at scale" group) pin a 500-track membership rewrite and its `addedAt`
  preservation across a reorder+drop. Baseline 500-write cost on
  `NativeDatabase.memory()` is **36 ms** — see `.ai/PERFORMANCE.md`.
  `/test/` is gitignored in this fork, so harness files are local-only.

### Tab-switch "after image" — cause found, fix in tree, verification interrupted
- Symptom: switching sidebar tabs (Browse → Radio, and nearly every other pair)
  left the previous page visible for a beat. Playlist → playlist did not, but
  anything involving Liked Tracks did.
- Cause, measured not assumed: the shell owns the ground. `ThemeBackgroundLayer`
  paints behind the router slot and `ThemeBackgroundScope` installs
  `ScaffoldTheme(backgroundColor: transparent)`, so a route paints almost
  nothing itself — an in-app `RepaintBoundary.toImage` dump of the router slot
  measured **42% unpainted on Home, 80% on Radio**. auto_route's default
  `MaterialRouteType` transition keeps the *outgoing* route mounted and painting
  for its whole duration (`CustomRouteType` also defaults
  `durationInMilliseconds`/`reverseDurationInMilliseconds` to 300 even with
  `TransitionsBuilders.noTransition` — `noTransition` removes the fade, not the
  overlap window). Two transparent routes alive at once = the old page shows
  through the new one. Playlist → playlist is the same route, so no second route
  ever mounts and no ghost appears; `liked-tracks` is a distinct route, so it
  does. That matches the reported pattern exactly.
- Fix: `swapWithoutOverlap()` in `lib/collections/routes.dart` rewrites every
  route inside the shell (and `library`'s children) to
  `CustomRouteType(duration: 0, reverseDuration: 0)`. A crossfade is not
  recoverable here — there is no opaque ground to fade against — so the overlap
  window is removed instead. Routes outside the shell keep their `slideBottom`
  sheets, where the overlap is the point.
- Evidence collected (dump rig: `/tmp/spotube-probe`, `SPOTUBE_DUMP=1` arms a
  700 ms frame burst on navigation via a `NavigatorObserver` on the shell
  `AutoRouter`; `SPOTUBE_DEMO_NAV=1` adds a scripted tab cycle). Pre-fix,
  `Stats → UserPlaylists` kept the outgoing page >15% visible for
  **0.27–0.50 s** every cycle; post-fix the same rig reports **no lingering**
  on Home/Radio/Stats/Playlists/Artists/Albums switches, warm.
- NOT yet done: (1) the control re-run with `swapWithoutOverlap` neutered, on the
  current 10-route sequence that includes
  `PlaylistRoute → LikedPlaylistRoute → PlaylistRoute`; (2) confirming pop/back
  (governed by `reverseDurationInMilliseconds`, set to 0 by construction).
- Done since: (3) all three TEMP PROBEs removed — the `[palette-probe]` block in
  `palette_transition_scope.dart`, and `SPOTUBE_DEMO_NAV` / `SPOTUBE_DUMP` /
  `_FrameDumpObserver` / `routerDumpKey` in `root_app.dart` (which also dropped
  their now-unused `dart:async`, `dart:io`, `dart:ui`, `foundation`,
  `rendering` and `routes.gr` imports); (4) `fvm flutter test` → 1237 passed,
  2 skipped, 0 failed. Worth recording *why* the suite was red before that: the
  probes were the failure, not the route fix. The 50 ms palette sampler left a
  pending timer in every `testWidgets` body, and 11 tests in
  `theme_transition_test.dart` / `scaffold_fade_probe_test.dart` failed on the
  leak check until it was deleted.
- Probe trap, learned the hard way: a **shared** `NavigatorObserver` instance
  cannot be handed to more than one navigator — `NavigatorState.initState`
  asserts `observer.navigator == null`, and the failure surfaces in the app as
  "Something went wrong starting this view". `AutoRouter`'s `navigatorObservers`
  is a *builder* precisely so each nesting level gets its own instance.
- Screen capture (`grim`) is unusable for this: the Caelestia shell re-tiles the
  window continuously, so a fixed region films the desktop beside the window and
  silently produces plausible garbage. Dump frames from inside Flutter instead.

## Known defects found while optimizing (not fixed — behavior change)

- ~~**`SourcedTrack` rebuilds lose `sourceCandidateKey`.**~~ **Fixed 2026-09-23**,
  see "Spotify + music fetch latency" below. The description is kept because the
  mechanism is still what the regression test guards.
  The key is stored when a
  track resolves (`sourced_track.dart` ctor + `source_resolver.dart`) and
  `playbackFallbackUrls` reads `primary.sourceCandidateKey` to skip re-searching
  the candidate that already produced the playing URL. But `copyWithSibling`,
  `swapWithSibling` and `refreshStream` each constructed a new `SourcedTrack`
  without it, and `refreshStream` runs on every expired CDN URL
  (`services/player/backend/playback.dart`) and replaces provider state — so after
  the first refresh `primaryKey` is `''` and the fallback walk re-searches the
  primary, the exact work `primaryCandidate()` exists to avoid. Fix is one line at
  each of the three sites.
- **`AudioPlayerState.containsTracks` ignored the queue — FIXED 2026-09-21**
  (`state.dart:112`): the parameter shadowed the field, so
  `listContainsTracks(tracks, tracks)` reduced to `needles.isNotEmpty`. Every
  caller therefore believed its own tracks were the playing queue, and
  folder/playlist **Play**, **Shuffle play** and **Add to queue** short-circuited
  into the "already playing" branch and did nothing. Found while indexing the same
  predicate in PR 6, reported, then fixed on the user's instruction. The parameter
  is now `needles` so the field cannot be shadowed by accident. Proven by
  `test/player_membership_test.dart` (`group('AudioPlayerState.containsTracks')`)
  and in the release build: Downloads Play loaded the queue, Cache folder Play
  replaced it, and Downloads **Add to queue** appended 516 tracks ("Add (516) to
  Queue" toast, drawer header "548 tracks in queue") — all three were no-ops before.

## Startup error-log triage (2026-09-19 logs)

Investigated 2026-09-20 from a pasted error log; no code executed.

1. **429 on `user.savedArtists`** (`metadata_plugin/library/artists.dart`): upstream
   (Spotify) rate limit surfaced through the hetu plugin HTTP layer. Not an app
   bug; no 429/backoff handling existed anywhere in `lib/` (grep-verified).
   **Mitigated 2026-09-21**: shared saved-artist/album id-set providers stop the
   per-id `fetchAll()` fan-out (mirrors the existing tracks pattern);
   `fetchWithRateLimitRetry` in `MetadataPluginMixin` auto-retries 429s twice
   with a 30 s cooldown; `ErrorBox` shows a friendly rate-limit message;
   downloads now retry 429. True `Retry-After` honoring still needs a
   `hetu_spotube_plugin` change (out of repo).
   **Root-caused + fixed at source 2026-09-21**: the Hetu Spotify plugin's
   `savedAlbums`/`savedArtists` (`hetu_spotify_gql_client` user.ht) ran
   `libraryV3` GQL, **discarded** the complete inline `item["item"]["data"]`
   payloads and re-hydrated via REST `GET /v1/albums|artists?ids=…` — 2
   requests/page, and the REST half is what Spotify 429s (GQL quota is
   separate; that's why Home kept rendering the same artists/albums).
   Fixed in the plugin (standalone repo commit `deb5ecc`, branch
   `inline-library-hydration`; audit repo `2ba9a63`, plugin 0.2.3-inline):
   convert the GQL payload inline to REST-shaped JSON exactly like
   `savedTracks`/`savedPlaylists`/browse already did — 1 GQL request/page,
   zero REST. Live-verified: Artists + Albums render, 0 logged 429s,
   snapshots persisted. Upstream-PR candidate.
2. **Avahi `FormatException: int.parse("9-rc5")`**: upstream `bonsoir_linux`
   5.1.3 `_isModernAvahi` splits the avahi version on `.` and int-parses
   `9-rc5` (system avahi is `0.9-rc5`). Fixed upstream in `bonsoir_linux` 6.0.2
   ("remove -rc from string avahi versions"). Spotube pins `bonsoir: ^5.1.10`.
   Impact: `connectClientsProvider` AsyncError at startup → Connect page dead;
   also poisons `bonsoirProvider` (`selectAsync` rethrow). Fix: upgrade bonsoir
   to 6.x (breaking: `ready`→`initialize()`, rewrite) or guard `discovery.ready`
   in `lib/provider/connect/clients.dart:37`.
3. **`packages/hetu_std/assets/bytecode/std.out` not loadable**: NOT reproducible
   in the current tree. Asset declared (pubspec.yaml:293), present in the pinned
   hetu_std checkout (`401fde42`, `lib/assets/bytecode/std.out`), and present in
   every local build manifest (debug/release/profile + `build/flutter_assets`).
   The 429 error earlier in the same log proves a plugin VM worked minutes
   before; the asset failures came from a later run whose bundle lacked the
   asset → environmental/stale/foreign build. If it recurs after a clean
   `pub get` + full rebuild, reinvestigate.

4. **`A RenderFlex overflowed by 3.0 pixels on the bottom` (home page, 6× per
   startup)**: NOT unrelated noise — the artist card in a mixed browse row.
   `HorizontalPlaybuttonCardView` sized its row `isArtist ? 250 : 225` where
   `isArtist` meant *every* item, so one artist among albums got the 225 cell
   and its badge row clipped. Neither the row nor `ArtistCard`'s avatar/gap
   followed `context.theme.scaling`, while the name and badges inside it did, so
   any scaling above 1 overflowed the artist-only pages too
   (`mainAxisExtent: smAndDown ? 225 : 250`).
   Fixed 2026-09-21: one source of truth
   (`lib/components/playbutton_view/card_extent.dart`, scaled), used by the
   horizontal row + the four artist grids; a row reserves the artist extent if
   *any* item is an artist; `ArtistCard` scales its fixed numbers and lets the
   name absorb a squeeze (`Expanded`, replacing `Spacer` + fixed text) so a short
   cell shrinks the name instead of pushing the badge out.
   `test/artist_card_extent_test.dart` (3 tests: fits its own extent, fits at
   scaling 1.25/1.5/2, degrades without clipping at the album extent). Debug run
   at 908×1038: 0 overflow lines, was 6.

## Open Problems

- **Orphaned extracted artwork — FIXED 2026-09-21 (working tree).** Previously
  every embedded picture written to `<temp>/spotube/<basename>-<pathdigest>.<ext>`
  was never removed (1,093 files / 39 MB measured for a 516-track library, on
  tmpfs = RAM). Now `pruneOrphanedArt`
  (`lib/provider/local_tracks/local_tracks_provider.dart:104`) sweeps the art
  dir after each scan, keeping exactly the paths the scan referenced, and only
  runs when the scan was complete and uncancelled (`:287-293`) so an unmounted
  or failed location can never cause deletion of live covers. Test:
  `test/local_artwork_test.dart`.
- **Page bottom inset is a guess, not the measured footer height.**
  `lib/pages/root/root_app.dart:54-60` sets `MediaQuery.padding.bottom` to
  `100 * theme.scaling` for everything below `Sidebar`, which is the only thing
  pages reserve for the player — shadcn publishes nothing usable there (see
  "Anything placed in the scaffold footer…"), so on desktop the incoming padding is
  0 and this constant replaces it. A page's last row can still sit under a player
  that measures ~130px at scaling 1.
  Left deliberately: the sidebar fix landed without touching it because the value
  is consumed by every page's list padding, so changing it is an app-wide visual
  change rather than a correction. The override also has to stay conditional below
  820px, where `PlayerOverlay` floats in the overlay stack and measures 0 while
  still covering content. Note this line is already scaling-aware, which is what
  made the sidebar's unscaled `Gap(130)` an outlier rather than a pattern.
- Otherwise none confirmed. See `.ai/TODO.md` for hypotheses (not yet proven).

- NewPipeExtractor calls `URLEncoder.encode(String, Charset)` (API 33) and it is
  **not** desugared in the shipped APK: `org.schabi.newpipe.extractor.utils.Utils`
  holds a raw `Ljava/net/URLEncoder;.encode:(…Charset;)` invoke-static while
  `j$/time/` has 37k desugared refs — so `desugar_jdk_libs` works, it just does not
  cover `java.net`. Risk is Android 7–12 (minSdk 24), not a confirmed crash: no
  device run yet proving that path executes. Cannot be fixed by `desugar_jdk_libs_nio`
  (see "Do Not Reinvestigate").
- Android builds need local-only scaffolding that is not in the repo: `android/app/build.gradle`
  signs *debug* with `signingConfigs.release` (line 86) whose `storeFile` comes from
  gitignored `android/key.properties`, so a clean checkout cannot produce an APK at all;
  and the Rust in `flutter_discord_rpc`/`metadata_god` needs a rustup toolchain with the
  Android `std` (this box has all four targets) plus `ANDROID_NDK_HOME`. The cross-compile
  used to die with `E0463 can't find crate for core` because Gradle's child PATH starts at
  `/usr/bin`, and cargo then resolved `rustc` to Arch's package, whose sysroot
  (`/usr/lib/rustlib`) has only the host target — `rustup run stable` does not protect
  against this, since rustc is still found through PATH. Repaired by
  `~/.cargo/config.toml` `[build] rustc = "/home/adamya/.cargo/bin/rustc"` (the rustup
  proxy, so it survives toolchain updates). Neither the repo nor the system changed.

## Known False Positives

### Large virtual mapping = leak
- Status: Rejected without heap evidence.
- Conclusion: A large virtual mapping is not automatically a live leak; requires
  RSS/PSS/heap evidence. Do not report as a leak on virtual-memory size alone.

## Do Not Reinvestigate Without New Evidence

### `desugar_jdk_libs_nio` to fix the NewPipe `URLEncoder` gap
- Why: it is the artifact that backports `java.net`, and upstream PR #3131 looked
  like a template.
- What was found: it cannot dex on AGP 8.7. Per-module dexing runs
  `DexingNoClasspathTransform` (`needsClasspath=false, useFullClasspath=false`), which
  is not given an `android.jar` root, so R8 throws `IllegalStateException: …
  android.jar is located outside the root directory …` at `:app:mergeLibDexDevDebug`.
  A/B on identical warm state: nio FAILED, plain BUILD SUCCESSFUL in 5 s.
  `android.useFullClasspathForDexingTransform=true` is silently ignored by AGP 8.7
  (flags unchanged in the retry, no warning).
- New evidence that would justify revisiting: an AGP upgrade that honors a
  full-classpath dexing property, or a device-side `NoSuchMethodError` making it
  worth attacking from the other side (raise minSdk, or patch/pin
  `flutter_new_pipe_extractor`, which itself declares the plain artifact).

### mimalloc / large virtual reservation
- Why: RSS-growth concern was raised.
- What was found: Large mapping may be allocator reservation; not proven to be
  live retained application memory; recent RSS plateaued after VM churn fix.
- Evidence: `.ai/PERFORMANCE.md` baseline table.
- Why further investigation is unnecessary: No heap/PSS evidence of a real leak.
- New evidence that would justify revisiting: rising RSS/PSS under a stable
  workload with VM churn already fixed.

### Top-albums / top-playlists history aggregation
- Why: PR 2 (C1) listed them as siblings of the top-tracks query.
- What was found: 27 ms and 6 ms per history write at 5k mixed rows vs 21–33 ms for
  the already-optimized tracks path — no bottleneck, so they were left alone.
- New evidence that would justify revisiting: a measurement showing either one
  dominating a scrobble (they both still `watch()` an unbounded query and parse
  every row of their own kind).

### Theme VM recreation
- Why: repeated theme recompute created fresh VMs.
- What was found: Theme plugin VMs are memoized; not recreated per recompute.
- Why further investigation is unnecessary: already memoized.
- New evidence: new per-recompute VM creation observed in logs.

### Already-fixed queue rebuild / library materialization / position tick storm
- Why: performance regressions reported.
- What was found: Each was fixed (see Completed); behavior verified by tests and
  commits.
- Why further investigation is unnecessary: fixes are in place and tested.
- New evidence: reproducible regression under current code.

### PR 5 (R-04) overlapping the deferred-init batch — rejected after measuring
- Why: the roadmap claimed the sequential `await` chain in
  `_initDeferredServices` cost the sum of eight step latencies.
- What was found: `NewPipeExtractor.init` is ~200 ms of a ~365 ms total and the
  other seven finish inside its window. Running all eight concurrently left the
  total unchanged (363 ms mean vs 368 ms sequential) and inflated
  `NewPipeExtractor` to ~315 ms under contention. Awaiting it first and
  overlapping the rest measured 335–397 ms — a shift on a phase that is already
  post-paint and on no interaction path. Code reverted.
- New evidence that would justify revisiting: a machine/profile where the seven
  tail steps dominate (slow disk for the mirror sweep, nmcli missing for the VPN
  probe), or a requirement that they finish before something user-visible.

### PR 5 (R-03) deferring the home library snapshot — not attempted
- Why: the roadmap planned to move `readLibrarySnapshot(ref)` off the home
  first-paint path.
- What was found: its only call site is
  `lib/modules/home/home_search_bar.dart`, an untracked work-in-progress file of
  the user's search redesign. Editing it, or committing it, would absorb that
  work into a performance commit.
- New evidence that would justify revisiting: that file becoming committed, or
  a measurement attributing first-paint cost to the snapshot specifically.

### PR 6 candidates measured and rejected
- Why: C6/C8 listed four more suspects alongside the two that landed.
- What was found: **theme-background resize** — the 1828×1029 wallpaper decodes
  identically when requested at 1920×1080 with `fit` + `allowUpscaling: false`,
  so nothing is reclaimable without changing which URL is fetched; the album-art
  backdrop deliberately picks the *largest* Spotify rendition (640×640 = 1.6 MB).
  **`directorySize` single pass** — 68/45 ms vs 70/48 ms on a 2000-file tree; the
  cost is the stat syscalls, not the intermediate list. **`presentation_list`
  `selectedTracks.any(...)`** — runs only over the ~15 visible tiles against a
  single-digit selection. **`isDownloaded` in `player_actions.dart`** — real
  O(n) (~1.5–2 ms per active-track change at 5,000 files) but the correct fix is
  deduping its match logic with `track_options_provider`, i.e. a refactor.
- New evidence that would justify revisiting: a bigger library, a wallpaper
  materially larger than the viewport, a slow/removable filesystem, or a
  user-visible selection of >100 tracks.

### PR 7 (C9) persistent local-metadata cache — rejected after measuring
- Why: the roadmap listed "local-library metadata rescan" as item 7 on the
  assumption that re-reading every file's tags through the bridge dominates a
  rescan.
- What was found: a full warm rescan is **38 ms at 516 real files, 152 ms at
  2,000, 510 ms at 8,000**; the provider is keepAlive so that happens once per
  process (plus explicit refresh / local-track delete), asynchronously, off the
  track-start path. A simulated perfect cache reaches only 17/67/234 ms because
  `stat()` + art-existence checks are an irreducible floor. 2.2× of a
  background sub-second task, for the only schema migration in the roadmap.
- New evidence that would justify revisiting: attribution of user-visible
  latency to the scan (slow/spinning disk, huge library), or a change that makes
  invalidation frequent (e.g. per-download invalidate).
- Full table: `.ai/PERFORMANCE.md` "Local-metadata rescan".

### Build-size pass 2026-10-06 — landed (config-only, uncommitted)
- What was done: Linux `--obfuscate --split-debug-info` in
  `scripts/install-local.sh` (bundle 98.8M → 95.4M, libapp.so 18M → 15M,
  symbols to `build/app/outputs/symbols`, measured); Android R8 +
  `shrinkResources` wired to the dormant `proguard-rules.pro` (config only —
  no licensed Android toolchain on this host, CI must verify); Makefile
  `apk` target fixed (stale `apk/release/` path, universal-only) to collect
  per-ABI outputs.
- No Dart changed, so `flutter analyze` is unaffected by construction
  (8 pre-existing issues, none in touched files); `git diff --check` clean;
  `test/local_artwork_test.dart` 11 green via `safe-test.sh -c 2`.
- Full table: `.ai/PERFORMANCE.md` "Build-size pass 2026-10-06".

### `uses-material-design: false` — not safe, do not propose
- Why: removing the 1.6M MaterialIcons font looks like free size.
- What was found 2026-10-06: `Icons.` is used in 43 places
  (`spotube_icons.dart` centralizes most, plus 5 call sites) — removal is a
  visual-behavior change, and release builds already tree-shake icons.
- New evidence that would justify revisiting: a migration of all call sites
  off Material icons (its own signed-off change).

### Stripping `integration_test` from the release registrant — disproven
- Why: it was reported as shipping in the release registrant.
- What was found 2026-10-06: no such entry in the current
  `GeneratedPluginRegistrant.java`; the file regenerates at build time.
- New evidence that would justify revisiting: the entry reappearing in a
  fresh release build.

### Deferring `MediaKit.ensureInitialized()` — re-confirmed keep
- Why: it sits on the pre-`runApp` path.
- What was found 2026-10-06: the queue-restore provider can reach the
  backend on first frame (`main.dart:306-317` comment); deferring it needs
  queue-restore to await init — a behavior-touching change. PR9 verdict
  stands; pre-runApp measured 42–48 ms.
- New evidence that would justify revisiting: a profile attributing
  first-frame cost to mpv page-in specifically.

### Music-cache LRU quota — deferred, needs sign-off
- Why: 360 MB / 34 files with no quota looks unbounded.
- What was found 2026-10-06: existing sweeps already remove staging/mirror
  orphans (`sweepStaleMusicCacheMirrors`, ~32 ms at startup); a quota that
  evicts complete tracks changes offline availability = behavior change.
- New evidence that would justify revisiting: user sign-off on an opt-in
  (default-off) quota setting plus Settings UI.

### Anything placed in the scaffold footer must support intrinsic dimensions
- Why: a change that moved the seek bar into `bottom_player.dart` made the whole
  window paint black on launch.
- What was found: shadcn's `_RenderScaffoldFlex.performLayout` measures the footer
  with `footer.getMaxIntrinsicHeight(double.infinity)`
  (`shadcn_flutter-0.0.47/lib/src/components/layout/scaffold.dart:945`) and uses
  that both to position the footer and to publish `MediaQuery.padding.bottom` to
  the body (`:371-389`). A `Row` containing an `Expanded` whose descendant has a
  `LayoutBuilder` (shadcn's `Slider` does) cannot answer an intrinsic-width query,
  so the measurement throws `LayoutBuilder does not support returning intrinsic
  dimensions` inside `performLayout` and nothing renders.
- Consequence, and the reason this is settled rather than merely a bug report: a
  widget in `Scaffold.footers` is measured twice, speculatively, before it lays
  out. `Expanded`/`LayoutBuilder` in that subtree is not a style preference, it is
  a hard failure.
- **The measured height is not readable from the body.** `:371-389` adds
  `constraints.footerHeight` to the body's `MediaQuery.padding.bottom`, but only
  when its `LayoutBuilder` hands back a `ScaffoldBoxConstraints`. Under Flutter
  3.35 that builder receives a plain `BoxConstraints` (`constraints.runtimeType`
  measured in a test shell), so the branch never runs and
  `MediaQuery.paddingOf(context).bottom` is 0 inside a `Scaffold` body — verified
  for footers of 130, 195, a `Text` and an empty box. `ScaffoldFooterPadding` is
  the other published route and it is broken too: its `_RenderScaffoldPadding`
  uses `ContainerRenderObjectMixin` without `RenderObjectWithChildMixin`, so
  attaching a child throws `type '_RenderScaffoldPadding' is not a subtype of type
  'RenderObjectWithChildMixin<RenderObject>'`. `_ScaffoldRenderFlex._footerSize` is
  a private `ValueNotifier` with no accessor. Settled: the sidebar cannot read the
  player's real height, so `sidebarBottomClearanceOf`
  (`lib/modules/root/sidebar/sidebar.dart`) scales the scaling-1 measurement
  instead, and must not be "fixed" by reading `MediaQuery` again.
- New evidence that would justify revisiting: shadcn stops measuring the footer
  intrinsically, or a footer child that provably implements intrinsics.

### Theme animation is not configurable from `ShadcnApp` — only overridable below `builder:`
- Why: the request was an optional palette-switch fade whose length the user could
  set. The two obvious answers do not exist in this app, and a third exists but does
  nothing, so settle this here rather than re-deriving it.
- What was found (shadcn_flutter **0.0.47**, `pubspec.yaml:107`, no
  `dependency_override`):
  - There is no `MaterialApp`; the root is `ShadcnApp.router` (`lib/main.dart`).
    `themeAnimationDuration` / `themeAnimationCurve` are therefore unavailable, not
    merely unset.
  - A palette change **already animates**: `ShadcnLayer.build` wraps the app in
    `ShadcnAnimatedTheme(duration: kDefaultDuration, …)`
    (`src/shadcn_app.dart:659-661`), `kDefaultDuration` is 150 ms (`src/util.dart:16`)
    and the curve defaults to `Curves.linear` (`shadcn_app.dart:735`). Neither is
    reachable from outside.
  - `enableThemeAnimation` (`:273`, `:436`, `:614`, `:632`) is accepted, stored and
    **never read** — dead code in this version. Do not build on it.
  - `lib/` contains zero `ThemeExtension`s, so nothing can "snap mid-tween" the way a
    Material app's would; `ThemeData.lerp` (`src/theme/theme.dart:315-330`) covers
    every field the app reads, and `ThemeData.operator ==` is value-based (`:333`), so
    a fresh-but-equal theme cannot retarget a running tween.
  - `ShadcnAnimatedTheme` collapses `duration == Duration.zero` to a plain `Theme`
    (`shadcn_app.dart:740-747`) — that is the only "off" switch the package offers.
  - The only hook is a nested `Theme` **below** `ShadcnApp.builder`: `builder:` runs
    under the package's own `AnimatedTheme` and above `AppLayout` →
    `ScrollMotionScope` → `ThemeBackgroundScope` → `ThemeSurfacesScope`, so a theme
    installed there wins for the whole app content, dialogs and menus included.
- Consequence, and why it is settled rather than a bug report: the feature had to be
  built as `PaletteTransitionScope`
  (`lib/modules/theme_background/palette_transition_scope.dart`), which must also
  re-declare `DefaultTextStyle`/`IconTheme` from its *own* animated theme —
  `ShadcnLayer` computes those two merges from its 150 ms clock above the seam
  (`shadcn_app.dart:668-675`), so without the re-declaration "off" would still leave a
  text/icon crossfade. Verified by mutation: dropping the merges fails
  `inherited text follows this clock`; hardcoding the duration fails five tests.
- Known leak, not fixable without forking:
  `ShadcnSkeletonizerConfigLayer(theme: theme)` (`:666-667`) bakes the package's 150 ms
  theme above the seam, so skeleton shimmer colours stay on the package clock.
- If the package is ever bumped: re-read `ShadcnLayer.build` for new consumers of the
  outer theme, and re-check whether `enableThemeAnimation` got wired up, before
  trusting the override.
- New evidence that would justify revisiting: a shadcn release that reads
  `enableThemeAnimation` or exposes a duration/curve, or the app gaining a
  `ThemeExtension`.

## Recently Changed

- 2026-09-25: **Search panel hide-during-build crash — fixed (working tree,
  uncommitted).** Session log showed `HomeSearchBar` throwing
  `_OverlayPortalState.hide`'s `persistentCallbacks` assertion
  (`home_search_bar.dart:167`) whenever a *visible* panel was dismissed by a
  state change rather than a tap (e.g. Tab out of the field). Root cause:
  keyed `useEffect`s re-run synchronously inside build on key change
  (flutter_hooks `framework.dart:473-483` → `initHook` → `scheduleEffect`),
  and the earlier rework had deferred only `show()` — `hide()` carries the
  identical assert (Flutter `overlay.dart:1966-1979`, SDK 3.35.2). Fix is one
  unified effect: both branches defer a post-frame callback and re-check
  `showRef` (focus may have moved on *or back*). Tap dismissal is untouched
  (gestures hide synchronously, still immediate); the X button can never be
  the repro — the modal barrier covers the field, so an X tap lands on the
  barrier first (verified by a vacuous-green test attempt). Proven by
  `test/home_search_live_test.dart` "focus loss with the panel open hides
  without crashing": red before (exact assertion via `takeException`), green
  after. Analyze clean, full suite **998 green**, linux debug rebuilt +
  relaunched with 0 crash lines.

- 2026-09-25: **Search surface rework (items 1,2,3,5,6,7,8), working tree,
  uncommitted.** Review-driven pass over `HomeSearchBar` / suggestions /
  results, all verified: `analyze` clean, full suite **997 green** (was 981),
  linux debug rebuilt + 45 s run with 0 layout/exception lines.
  - (1+7) `buildSearchSuggestions` takes `text` (raw, recents-only) +
    `libraryQueryText` (debounced, fuzzy) and returns a `SearchSuggestions`
    record (recents/live/library) built per loop site — no flat list, no
    `RecentSearchSuggestion() => SizedBox.shrink()` dead branch. Blank text
    force-clears library/live (clear-path guard). `LiveTrackSearchSuggestion
    : TrackSearchSuggestion` inheritance pinned by a no-leak test.
    Item 4 (constant wiring) was already done — no diff.
  - (3) Recents are a `recentSearchesProvider` (`Notifier<List<String>>`,
    new `lib/modules/search/recent_searches.dart`) over the sync
    `SharedPreferences` getter; `refreshTick`/`useMemoized`/free helpers
    deleted. 20-cap + drop-oldest preserved from `KVStoreService`.
  - (5) Barrier `translucent` → `opaque` (the old barrier already passed
    taps through — the regression pre-existed, TapRegion would only have
    kept it) + explicit `hideAndUnfocus` on barrier and every row, 150 ms
    timer deleted. Panel stays modal; widget test taps a target below the
    360px panel and asserts close + background silent.
  - (2+8) Chips: `ref.listen` resets only when the selection leaves the
    list; `SearchChip` enum maps plugin strings at the boundary, unknown
    chips render unselected and fall back to All.
  - (6) `SearchTabScaffold` (`lib/modules/search/search_tab_scaffold.dart`)
    owns no-default/error/placeholder from the watched `AsyncValue` — takes
    a value, not a provider, so the Future vs paginated-`fetchMore` shapes
    stay in the five thin tabs.
  - Test note: `home_search_chips_test.dart` calls
    `MediaKit.ensureInitialized()` in `setUpAll` — empty sections render 5
    skeleton `AlbumCard`s and `AlbumCard.build:45` reads the global player
    service (`useStream(audioPlayer.playingStream)`), untestable otherwise.
    Host libmpv exists; revisit if CI lacks it. Same wart covers
    `PlaylistCard:48`; `TrackTile`/`ArtistCard` are provider-only.

- 2026-09-25: **Live songs in the search dropdown, working tree,
  uncommitted.** The panel's Songs group now serves live Spotify matches:
  `HomeSearchBar` debounces the field (`useDebounce`, 500 ms) and watches
  `metadataPluginSearchAllProvider` only while focused and the term is ≥ 2
  chars — one gated call per pause, `autoDispose.family` caching repeats,
  only the current term's instance rendered. New `LiveTrackSearchSuggestion`
  subtype (same row, separate group, cap 4) ahead of library rows; spinner
  row while loading, silent on error (results page still owns errors).
  - **Two real bugs found by the widget test, both fixed.** (1) The first
    refresh path was a same-text controller poke — a complete no-op, because
    `ValueNotifier` drops equal values *and* `RawAutocomplete` discards
    recomputed options when the text is unchanged. Live results could never
    reach the panel in production either. Replaced `RawAutocomplete` with a
    directly-driven `OverlayPortal` + `CompositedTransformFollower` (options
    computed fresh in build scope; full-screen translucent barrier
    dismisses); row taps survive via a 150 ms delayed hide. (2) The test
    also caught `OverlayPortalController.show()` during build
    (persistentCallbacks assertion) — now deferred post-frame, which
    production would have hit as soon as any load started.
  Tests: `test/home_search_live_test.dart` (4 widget tests: one debounced
  call + cover row, rapid-typing coalescing, min-length gate, recent-tap
  submit; image HTTP faked with a 1x1 PNG) + 3 pure builder cases (15 in
  `search_suggestions_test.dart`). Analyze clean, full suite 981 green,
  debug rebuilt + launched with zero layout errors.
  New `TrackSearchSuggestion` (`SpotubeFullTrackObject`, matched on name +
  artist names) leading the panel's library group: cover art in front
  (`track.album.images`, same 200→300 rendition rule), bolded title match,
  artist subtitle, muted duration trailing. Tap opens `TrackRoute`
  (navigates like library rows — no surprise playback). Snapshot reads
  `metadataPluginSavedTracksProvider`; tests +1 (songs-lead case, 12 in
  file). Analyze clean, full suite 974 green, debug rebuilt + launched
  (only the pre-existing Discord null-checks in log).
  Replaced shadcn `AutoComplete` (plain `String` rows, no row builder) with
  `RawAutocomplete<HomeSearchSuggestion>` in `HomeSearchBar`, so anchoring /
  focus-loss / outside-tap come from the framework. New
  `lib/modules/home/home_search_suggestions.dart`: sealed suggestion types
  (recent / playlist / album / artist), pure `topMatches` (best-field fuzzy
  rank, `> 50` cutoff, 3-per-group cap) + `filterRecentSearches` (old
  semantics), and `HomeSearchSuggestionsPanel` — recents group (history icon,
  match highlight, per-row remove, Clear-all footer) above cover-art rows
  (`UniversalImage`, round artist covers, title + kind/artist subtitle).
  Local data only: recents + already-loaded saved playlists/albums/artists
  (note: saved artists are `SpotubeFullArtistObject`); logged-out/loading
  reads as empty, never an error. Recents tap submits; library rows navigate
  to their page + unfocus. Enter prefers a highlighted row, raw submit is
  idempotent. Two new `app_en.arb` keys (`recent_searches`,
  `from_your_library`; `clear_all` reused), `gen-l10n` regen is +188
  mechanical lines, other locales fall back. Tests:
  `test/search_suggestions_test.dart` (11 cases). Analyze clean, full suite
  973 green, debug rebuilt + launched (log shows only the pre-existing
  Discord-RPC null-checks and Spotify 401s).

- 2026-09-25: **Search merged into Browse, Search page deleted, working tree,
  uncommitted.** `HomePage` mounts `HomeSearchBar`
  (`lib/modules/home/home_search_bar.dart`: autocomplete, recents, submit →
  `searchTermStateProvider` + history, extracted from `search.dart:108-182`,
  no autofocus) as a sliver above the sections; a non-blank term swaps the 4
  browse slivers for `HomeSearchResults`
  (`lib/modules/home/home_search_results.dart`: chips row + tab switch +
  error states, extracted from `search.dart:183-231`) in a
  `SliverFillRemaining`, so result tabs keep their own scroll. Clearing (X
  also resets the provider now) restores Browse with no navigation.
  `searchTermStateProvider` moved to `lib/modules/search/search_term.dart`
  (10 importers repointed; single source, no dup) alongside the new
  `homeSearchFocusRequestProvider` counter. Deleted `pages/search/search.dart`
  (its PopScope-to-Home guard with it), dropped `/search` from `routes.dart`,
  regenerated `routes.gr.dart` (49→48 route classes; diff is only import-alias
  renumbering + the SearchRoute block, verified). Sidebar is Browse/Stats,
  mobile nav Browse/Library/Stats. `Ctrl+Shift+2` (`HomeTabs.search` kept,
  `main.dart` passes `ref`) navigates home + bumps the counter; the bar
  `ensureVisible`s + focuses post-frame, re-firing on repeat. Result tabs,
  chips provider and all search providers untouched. Analyze clean, full suite
  962 green, debug rebuilt + launched (no layout errors; only the known
  Spotify 401s).

- 2026-09-25: **Lyrics moved from sidebar to bottom player bar, working tree,
  uncommitted.** The Lyrics row is gone from `getSidebarTileList`
  (`lib/collections/side_bar_tiles.dart`: top nav is now Browse/Search/Stats);
  a lyrics `IconButton` (`SpotubeIcons.lyrics`, tooltip `l10n.lyrics`) joins
  `BottomPlayer`'s `extraActions` — disabled with no active track, navigates
  to `LyricsRoute` otherwise. Bar-only placement is deliberate: the bar is
  desktop-only (`bottomPlayerVisibleOf`) and `PlayerActions` is shared with
  the mobile expanded player, which already has its own Lyrics button
  (`player.dart:229-237`). Route, `HomeTabs.lyrics` shortcut, `PlayerLyrics`
  and mini-lyrics paths untouched; footer-intrinsics safe (same
  Tooltip+IconButton shape already in that subtree); no test referenced the
  tile list. Analyze clean, full suite 962 green, debug rebuilt + launched
  (no render/intrinsic errors in log).

- 2026-09-25: **Pinned playlists sort to the top of the Playlists page,
  working tree, uncommitted.** On compact/mobile `Sidebar` early-returns
  (`sidebar.dart:159-162`), so pins never rendered, and `UserPlaylistsPage`
  ignored `pinnedPlaylistIds` — pinning was a desktop-only no-op on Android.
  Fix: pure `pinnedFirstPlaylists` (`sidebar_provider.dart`, same pattern as
  `moveSidebarPin`: pin-order first, unknown ids skipped, input never mutated,
  empty pins = equal copy) applied in the page's empty-query fast path only;
  search ranking untouched, pagination/offline merge flows through it. Page
  watches `pinnedPlaylistIds` so pin/unpin/reorder re-sort live. Tests:
  `test/sidebar_order_test.dart` +6 cases (subset order, unknown ids,
  liked-tracks synthetic, all-pinned, no-mutate). Full suite 962 green,
  analyze clean, linux debug rebuilt + launched (PID 14777, no sidebar/pins
  errors in log).

- 2026-09-24: **Bottom-player dock variants (schema v19 → v20), working tree,
  uncommitted.** New `PlayerDock` enum (`fullWidth` default / `docked`) as a
  `preferences_table` text-enum column — full width is the historic floating
  scaffold footer, docked lays `BottomPlayer` out under the content only (via
  a new `Sidebar.contentFooter` slot) so the sidebar runs full height.
  `sidebarBottomClearanceOf` gained `dock` (docked → 12*scaling pad; pure
  `sidebarClearance` extracted for unit tests), `root_app.dart` switches
  scaffold footers + the 100px content bottom pad (12px when docked) off it,
  Settings → Playback has the A/B selector. Inert on compact/mobile
  (`PlayerOverlay` path). `test/sidebar_footer_clearance_test.dart` extended
  (docked widget case + pure matrix); full suite 835 green, analyze clean.

- 2026-09-24: **Sidebar pinned playlists + library reorder (schema v18 → v19),
  working tree, uncommitted.** Two new `preferences_table` text columns with
  `StringListConverter` (same pattern as `sourcePriority`), both default `[]`
  so upgrades keep the literal tile order and no pins:
  `sidebar_library_order` (stable tile ids) and `pinned_playlist_ids` (ordered
  playlist ids, append-on-pin). Resolution is pure
  (`resolveSidebarLibraryOrder` in `lib/provider/sidebar/sidebar_provider.dart`:
  stored ids first with unknowns dropped, missing defaults appended);
  `sidebarPlaylistIndexProvider` merges saved + mirrored playlists by id (same
  merge as `UserPlaylistsPage`, no liked synthetic — the sidebar builds that
  in UI where `l10n` is reachable). `Sidebar` renders pins as `NavigationButton`
  rows (28px `SidebarPinCover` in the icon slot, package-fixed 200*scaling
  width untouched; panel scrolls natively via shadcn `CustomScrollView`, rail
  capped at 8 + overflow tile). Pins join `tileList` so `onSelected` indices
  stay correct. Entry points: playlist header pin toggle
  (`presentation_top.dart`, playlist collections only), card hover top-left
  (`playbutton_card.dart`, desktop-hover only — mobile shows it solely when
  pinned so no invisible tap trap), tile trailing row, shared
  `SidebarOrderDialog` (drag + arrows, persist-on-move) opened from the new
  Settings → Sidebar section. Tests: `test/sidebar_order_test.dart` (6 cases);
  migration pairs incl. 18→19 green; full suite 813 green, analyze clean.
  `togglePinnedPlaylist` on `UserPreferencesNotifier` is the single pin writer.

- 2026-09-23: **Desktop volume-control visibility mode (schema v16 → v17), in the
  working tree, uncommitted.** `VolumeControlMode` (`always` / `hover` / `hidden`)
  is a new `preferences_table` text column, default **`always`** so the feature
  does not silently change existing behavior on upgrade — only the wide layouts
  draw the bottom bar, so it is inert on touch/compact. `VolumeSlider` gained
  `revealOnHover`: on desktop it collapses the track to a 0-width
  `ClipRect`+`AnimatedSize` until a `MouseRegion` reports the pointer over it; the
  `Listener`/`Slider` itself is unchanged, and `always` keeps the pre-existing
  `Expanded(child: Slider)` branch verbatim. `BottomPlayer` extracted
  `BottomPlayerVolume` so the preference watch and the `volumeProvider` watch stay
  off `BottomPlayer`'s rebuild path (`hidden` renders `SizedBox.shrink()`).
  The Settings control is an `AdaptiveSelectTile<VolumeControlMode>` in
  **Settings → Desktop** beside `close_behavior` (four new `app_en.arb` keys;
  other locales fall back via `untranslated-messages-file`).
  - Layout risk settled by test, not assumption: the hover path routes the slider
    through `AnimatedSize` **without** its `Expanded` wrapper, which is exactly the
    shape that black-screened the app before (see the footer-intrinsics entry) — a
    bare shadcn `Slider` refuses an intrinsic-width query and unbounded
    constraints. `test/volume_control_footer_test.dart` (3 cases) drives the real
    `VolumeSlider` in a real `floatingFooter` Scaffold across all three modes and
    the frame the pointer is actually over it; the reveal answers
    `getMaxIntrinsicHeight` with a finite value and throws nothing.
  - Migration verified in-suite: `test/drift/app_db/migration_test.dart` now runs
    `16 → 17` (guarded by a `_tableColumns` check like every step since v12), and
    `drift_schema_v17.json` was regenerated after the default was changed to
    `always`. 159 drift+player tests green; `flutter analyze` clean on the touched
    files. Note this fork's `.gitignore` excludes `/test/`, so the footer and
    migration test halves are local-only and cannot be committed with the source.
  - Not yet observed in a running build (needs a rebuild); the widget test covers
    the one failure mode this change could plausibly hit.

- 2026-09-23: **Playlist download state + Spotify playlist mirroring (schema
  v15 → v16), in the working tree, uncommitted.** Three tables —
  `track_download_table` (one row per owned file, keyed by Spotify track id,
  `track_data` carrying the full track JSON), `playlist_download_table`
  (membership: playlist id, track id, position) and
  `playlist_download_mirror_table` (one header per explicitly mirrored playlist).
  Splitting file identity from playlist membership is what makes "never download
  twice" structural: a track in three playlists is three membership rows and one
  download row. `DownloadManagerNotifier` got one enqueue path (`_enqueue`, which
  closes the `addAllToQueue` hole where a batch re-queued whatever was already in
  flight), `_setStatus` remains the only writer and now persists its transition
  winner unawaited, and `reconcilePersisted()` at startup turns
  `queued|downloading` into `interrupted` and a vanished `completed` file into
  `missing`. Per-row state (`downloadStateOfProvider`) replaced both name-matching
  scans (`player_actions.dart`'s O(all-local) title+album+artists match and the
  menu's in-session queue walk), so "is this downloaded" survives a restart.
  `PlaylistMirrorService.mirror/reconcile` is gated on a mirror row existing —
  browsing never mirrors, and a sync only ever offers tracks that have no row at
  all, so it never re-downloads `completed`, retries `failed` or overrules
  `canceled`. No code path deletes an audio file **except the one sanctioned
  bulk wipe** (2026-10-21): the Local Library page's "Delete local library" →
  `PlaylistMirrorService.forgetEverything()` + `selectFilesToDelete`. That path
  deletes only files resolving inside the download root or the music-cache leaf,
  and subtracts anything under a user-added library location, so per-playlist
  `forget()` / `deletePlaylistMirror` still never touch a file.
  - **Plan deviation, disproven, do not re-plan:** adopting pre-existing files by
    scanning the download directory cannot work. `SpotubeTrackObject.toMetadata`
    (`lib/models/metadata/track.dart:92-118`) writes no Spotify id or ISRC into the
    file, so a downloaded file holds nothing that maps back to a `trackId`.
    Adoption is lazy instead: the first enqueue of a track whose file already exists
    completes it via the existing-file check (`test/download_playlist_dedup_test.dart`
    asserts exactly that, including that the file is not rewritten).
  - Known pre-existing wart, deliberately not touched: `_prefilterAndStart` groups
    queued tasks by sanitized destination, so two *different* tracks that sanitize
    to one name (two "Intro" tracks by one artist) leave the second marked
    `completed` against the first's file. Rows stay distinct (the key is the track
    id — asserted in `download_playlist_dedup_test.dart`); the collision policy is
    older than this feature and fixing it means changing the file-naming scheme.
  - Migration verified on a **copy of the real 2 MB `db.sqlite`** (`sqlite3 .backup`
    into `/tmp/v16_check`, opened only through `AppDatabase.forTesting`):
    `user_version` 16, both `@TableIndex` entities present (drift's
    `Migrator.createTable` does not make them), and all twelve pre-existing tables
    at their exact prior counts — 617 `source_match_table`, 71 `history_table`, 23
    `lyrics_table`, 8 `plugins_table`, 4 `library_snapshot_table`, 1 each of
    preferences/audio-player-state. The user's own file is untouched and still at v15.
  - Not yet verified in-app (needs a rebuild + a Spotify login): kill mid-download →
    *interrupted*, and airplane-mode render of a mirrored playlist. Both are covered
    at unit level, neither has been observed in the running UI.

- 2026-09-23: **Everything this doc called "uncommitted" is now published.** The 143-path
  working tree landed as 10 subsystem commits (`c15c31b4` gate → `317b730f` fork identity)
  and `origin/master` matches; ordering is dependency-driven, not narrative — the layout
  foundation precedes the perf commit because the grid cards import it, and the commit that
  deletes `ServiceUtils.onlyContainsEnglish` follows the one that removed its last caller.
  Installed as `5.1.2+4501` via `scripts/install-local.sh`; the installed `libapp.so` is
  byte-identical to the fresh bundle and no source file post-dates it. Migration v14 → v15
  was then driven on a **copy** of the real 2 MB DB (`XDG_DATA_HOME` isolation +
  `dbus-run-session`, as always): `user_version` 15, both columns with their declared
  defaults, and all 11 tables at the same row counts as a pre-migration `.backup` — only
  `source_match_table` grew, from the session doing lookups. Zero Dart errors in the log.
  Do not read the "dormant" or "in the working tree" wording in the entries below as current.
- 2026-09-23: **Optional palette-transition fade added (schema v14 → v15).** Two
  drift columns — `preferencesTable.themeTransition` (bool, default **false**) and
  `themeTransitionMs` (int, default **250**) — drive
  `PaletteTransitionScope` (`lib/modules/theme_background/palette_transition_scope.dart`),
  a nested `ShadcnAnimatedTheme` installed at the `ShadcnApp.builder` seam with
  `Curves.easeOutCubic`. Off is `Duration.zero`, which the package collapses to a plain
  `Theme`, so a disabled transition costs nothing; `resolveThemeTransition` clamps the
  stored length to 50–2000 ms. Controls live in Settings → Appearance: a switch plus an
  `AdaptiveSelectTile<int>` of 0.1/0.15/0.25/0.4/0.6/1 s, the latter rendered only while
  the switch is on (the app has no stepper anywhere in Settings, so a discrete select is
  the convention, not a shortcut). Covers every palette change — light/dark/system,
  plugin switch and Caelestia shell sync — because all three arrive as one `ThemeData`
  through `themeDefinitionProvider`. See "Theme animation is not configurable from
  `ShadcnApp`" above for why it had to be built this way. `from14To15` is guarded by
  `_tableColumns` checks like every step since v12, not a bare `addColumn`: drift moves
  `user_version` only after the strategy returns, so a kill between the two `ALTER`s
  re-enters with a column already present. Mutation-verified — dropping the guards makes
  `re-running v14 -> v15 on columns that already exist is a no-op` fail with
  `duplicate column name: theme_transition`.
- 2026-09-22: **NewPipe search now tries `music_songs` before `videos`.** This
  supersedes the 2026-09-21 note below saying `searchVideos` "deliberately keeps
  `contentFilters: [videos]`" — that was the *only* tier then, and the reason it
  could not be dropped (the plugin reads nothing but list order) still holds; a
  songs tier was added *ahead* of it, not instead of it. `videos` is now the
  fallback tier and the sole path for ISRC-shaped queries, where `music_songs`
  measurably returns 11–20 irrelevant rows that would be cached as a confident
  match. See "NewPipe search returned video versions and fan channels ahead of
  the recording" above. Shared `rankResults` also changed, so desktop engines
  rank differently than before: lyric videos no longer score, altered versions
  (slowed/reverb/cover/karaoke) are penalized, and a duration more than 15s off
  the Spotify length costs 2.
- 2026-09-22: **Android smoothness pass — four per-frame costs removed, one
  repaint policy added.** The report was "the android app is not working as
  smoothly as it should", characterized by the user as all of: scrolling jank,
  player-sheet stutter, stutter during playback, general heaviness. **There is no
  device, AVD or adb on this machine** (`fvm flutter devices` lists linux + web),
  so every claim below is counted in Dart — channel calls, provider notifications,
  widget-tree shape — not measured in frames. GPU wins are mechanism-verified only
  and `.ai/PERFORMANCE.md` still carries no Android numbers.
  - *Glance home-widget storm (Android-only, the one clear bug).* `glanceProvider`
    wrote `HomeWidget.saveWidgetData` + `updateWidget()` for every playing/duration
    event *and every 1 Hz position tick*, for the whole session, foreground or
    not — a platform-channel round trip plus a widget redraw per second on the
    device that also has to render the list. Now `ForegroundCoalescer`
    (`lib/utils/foreground_coalescer.dart`) folds everything a foreground session
    generates and pushes **once** on the way out of foreground (`onInactive` /
    `onHide` / `onPause`; `WidgetsBinding` publishes the new lifecycle state
    before notifying, so the foreground check inside those callbacks is already
    accurate). Measured: 60 requests in foreground → 0 pushes, 1 on exit, and a
    failed push is not remembered as delivered. `test/glance_push_coalescing_test.dart`
  - *Nav bar rebuilt on every frame of a sheet drag.* `PlayerOverlay.onPanelSlide`
    writes `navigationPanelHeight` per frame and the bar watched the raw double to
    compute one threshold. Added `navigationPanelCoversBar`
    (`lib/modules/root/spotube_navigation_bar.dart:25`) and switched the bar to an
    `AnimatedContainer` collapsing to height 0, so it stays mounted across the
    threshold instead of swapping subtrees. Measured over the exact 31 values a
    drag writes: raw 30 notifications vs derived 1.
    `test/navigation_bar_panel_lift_test.dart`
  - *Every track row scanned the whole blacklist.* `TrackTile` used an
    `autoDispose.family` provider per row whose body watched the table and did
    `entries.any(...)` per artist; a screenful over a large table re-ran a
    table-length scan per row on any change. Now `blacklistedIdsProvider` builds
    one `Set<String>` per table change and rows ask `BlackListNotifier.matches`
    (`lib/provider/blacklist_provider.dart`); the family is gone, and so is the
    per-row `AnimatedCrossFade` (its two states were constant, and it kept the
    checkbox and the index label mounted simultaneously). Gate: 5,000 entries ×
    200 rows × 5 rounds, indexed must beat the old scan by >5x; measured 35-38x.
    The old implementation is kept in the test as a `_naive` oracle and
    cross-checked on 200 random pools. `test/blacklist_row_membership_test.dart`
  - *Four dead implicit animations per grid card.* `PlaybuttonCard` wrapped each
    overlay button in `AnimatedScale` + `AnimatedOpacity`, but on touch the target
    is a constant (`kIsMobile` forces it), so the controllers only existed to be
    mounted and disposed as the grid recycled cards. `hoverReveal()`
    (`lib/components/playbutton_view/playbutton_card.dart:20`) renders the button
    plain and holds the hidden one at `Opacity(0)` so the slot — and the play
    button's position while loading — is unchanged. The pointer branch is
    untouched and asserted at its old values.
    `test/playbutton_card_hover_reveal_test.dart`
  - *Blur only at rest (the user's explicit choice: "keep blur, repaint-cache
    it").* `main.dart:490` defaults `surfaceBlur: 10`, which shadcn's `SurfaceBlur`
    turns into a real `BackdropFilter` whenever it is `> 0` — so the nav bar and
    the collapsed player re-blurred whatever scrolled past them, every frame.
    `ScrollMotionScope` (`lib/components/scroll_motion_scope.dart`, installed in
    `main.dart`'s router builder) counts nothing: it restarts a 400 ms countdown on
    any scroll *motion* notification (metrics changes are layout, not movement, and
    are filtered out) and `scrollInFlightProvider`
    (`lib/provider/scroll_motion.dart`) flips false when the countdown runs out —
    so a scrollable destroyed mid-fling cannot leave the chrome permanently
    unblurred. `chromeBlurFrozen` ORs in the sheet's in-flight state
    (`navigationPanelHeight != 50`) and the two pinned mobile surfaces read it as
    `frozen ? 0 : theme.surfaceBlur`. Measured: 30 frames of a one-finger drag →
    1 state change up, 1 down after the fling settles, 0 on a non-mobile host.
    `test/scroll_blur_freeze_test.dart`. The same pattern is *available* but not
    applied to `TrackPresentationTopSection`'s header panel — it now has its own
    `_HeaderSurface` (`lib/components/track_presentation/presentation_top.dart`)
    so the freeze redraws the surface rather than the header subtree; other
    `surfaceBlur` readers (`bottom_player.dart`, lyrics, connect) stay as they
    were, being either desktop-only or not over moving content.
  - *Deliberately not changed:* `TrackTile`'s per-row `LayoutBuilder` (behavior
    risk in narrow containers, no evidence it is hot), and `RepaintBoundary`s
    anywhere (the app has none, but adding them without a profile is a guess).
  - Also recalibrated `test/player_membership_test.dart`: its 2x budget at
    100×100 measures 1.6–2.4x on an *idle* machine, so the small case now only
    asserts "never slower" and the 2x claim rests on 1000×1000 (measured 17x).
    Do not tighten the small case back.

- 2026-09-22: **Report "playlist page opens, then throws me to Home/Browse" —
  two defects of that family fixed, the report itself still unreproduced.**
  - *Defect 1 (real, latent):* three RootApp-level pages guard themselves with
    `PopScope(canPop: false, onPopInvokedWithResult: ...)` that pushed Home
    **whatever** `didPop` said — `lib/pages/library/library.dart:44`,
    `lib/pages/search/search.dart:76`, `lib/pages/stats/stats.dart:19`. A page
    deleted from a pages-based `Navigator` reports `didPop == true`
    (`test/pop_scope_page_removal_test.dart`), and auto_route 9.3 collapses a
    stack by *deleting* pages: `_popUntilOrPushAll`
    (`routing_controller.dart:1237-1263`) removes down to and including the
    anchor, then re-pushes. So whenever the anchor is a parent-level route below
    one of those pages (clicking Browse from a deep stack), the page is deleted,
    its handler fires, and Home is pushed a second time on top of the Home the
    router just re-pushed. Fixed with `if (didPop) return;`; a *blocked* pop (the
    system back — the case the guard exists for) still goes Home.
  - *Defect 2 (real, proven in isolation):* the shell changes the depth at which
    `AutoRouter` mounts — `ThemeBackgroundScope` returns bare `child` until a
    background image exists, `ThemeSurfacesScope` until a tint does, `Sidebar`
    collapses at ≤640 px (`Breakpoints.sm`), and `RootAppPage` wraps everything
    in an inset-chrome panel. An unkeyed widget that moves depth is unmounted,
    `AutoRouterState.dispose()` drops its `RoutingController`, and the remount
    re-pushes the level's `initial: true` route — Home, as a jump-cut with no
    transition. The flip is not hypothetical: in
    `test/shell_rebuild_navigation_test.dart` the unkeyed slot mounts **twice**
    before anything is touched, because the theme resolves a frame after first
    paint. Fixed by one `GlobalKey` (`appRouterSlotKey`) on the `MediaQuery`
    owning the slot in `lib/pages/root/root_app.dart` — all four sites at once,
    no layout or paint change.
    The candidate that ties the jump to the reporter's rate-limit correlation:
    `themeDefinitionProvider` catches every failure and returns `null`
    (`provider/metadata_plugin/metadata_plugin_provider.dart:872-875`), which
    unwraps *both* scopes at once — a mid-session re-resolve is a depth change
    with a page open. The key makes that a move instead of a teardown, whatever
    the trigger.
  - *Live check (release build driven with ydotool+grim on this machine):* the
    reported jump did **not** appear for the sequences tried, on a build with
    defect 1 reverted: Browse → Playlists → open a playlist → Playlists again
    (the anchor resolves inside the library's own level, so the guarded page is
    never deleted), and opening a playlist / pressing Play (no shell flip — the
    background image was already non-null). Flips that were *not* exercised:
    window resize across the 640 px breakpoint (Hyprland's `resizewindowpixel`
    dispatch was unusable in this session), compact layout mode, an
    inset-chrome theme, and a background image going null.
  - *Ruled out:* a theme recompute hollowing out `asData` (a reload arrives as
    `AsyncData(isLoading: true, value: previous)` — pinned by the same test);
    the sidebar `selectedIndex`/`onSelected` pair; `PlaylistRoute`'s
    `AutoRouteGuard.redirect` (only remaps `user-liked-tracks`); the `home`
    route's auth guard (`!KVStoreService.doneGettingStarted` is false once
    onboarding is done); `AppPopScope`'s unconditional callback (player only,
    and it closes a panel).
  - **Still open**: needs the exact click sequence from the reporter, or an
    instrumented build that logs `AutoRouterState` disposal.
- 2026-09-22: **B3 (stable `ValueKey`s on list tiles) examined and skipped — no
  code changed.** The audit row pointed at
  `lib/components/track_presentation/presentation_list.dart:101` and
  `lib/modules/player/player_queue.dart:304` and expected a key change to "let
  the element tree rebind instead of rebuilding on insert/reorder". Neither holds:
  - The queue item is wrapped in `AutoScrollTag(key: ValueKey<int>(i), index: i)`
    (`player_queue.dart:322`). That key is *positional by contract* — `index:` is
    the same `i`, and `scroll_to_index` resolves a tag by index. Re-keying the
    wrapper by track id would break `scrollToIndex` for the active track, so the
    only correct key there is already present.
  - `TrackTile` is stateless apart from the `Checkbox`/selection values passed in,
    so rebinding is not a correctness problem; a key cannot remove a rebuild that
    is caused by `itemBuilder` being called with a new `track` object per row.
  - Identity keys are **unsafe** at this layer: duplicate track ids are legal in a
    queue (add-the-same-track-twice, and `onReorder` of a duplicated entry), and a
    `SliverReorderableList`/`ListView` with two equal keys throws `Duplicate keys`
    at build — turning a cosmetic no-op into a red screen.
  Verdict: cost is real (a new failure mode), benefit is not (no state to rebind,
  and the one key that matters is already index-keyed). Revisit only if a track
  row grows real local state (a text field, an expandable panel).
- 2026-09-22: **PR-13 (queue-persistence churn) investigated and closed as
  already covered by PR-3 — no code changed.** `onBackendPlaylist`
  (`lib/provider/audio_player/audio_player.dart`) short-circuits on
  `_sameMedias(_lastSyncedMedias, playlist.medias)` and passes
  `Value.absent()` for the `tracks` column when the queue is unchanged, so a
  track-metadata change inside an unchanged queue writes no JSON. Measured in
  `test/queue_persistence_test.dart`: 2000-track queue, two track changes —
  before **103 ms / 2 `tracks`-column writes / 4 encodes / 4109.4 KB**, now
  **1 ms / 0 writes / 0 encodes / 0.0 KB**; a 600-track load still persists
  exactly once (14 ms, 616.4 KB). Nothing left to debounce.
  The remaining PR-13 item — routing the C2 metadata/audio-source/theme plugin
  VM lookups through `PluginVmCache` (`provider/metadata_plugin/
  metadata_plugin_provider.dart`, three `firstWhere`-style role resolves) — was
  **declined**: a shared VM only helps when one plugin fills more than one role,
  and the only instrument that could show that (`PerfCounters`) is compiled out
  of release (`kPerfCountersEnabled = !kReleaseMode`), which is the user's build.
  Refactoring a VM lifetime on an unmeasurable hypothesis risks the plugin/auth
  behavior the audit told us to preserve. `source_resolver.dart:164` already uses
  `PluginVmCache.getOrCreate`.
- 2026-09-22: **PR-12 / C5 (local-delete invalidation storms) investigated and
  disproven — no code changed.** Three `ref.invalidate(localTracksProvider)`
  calls in one event-loop turn already cost **one** directory walk, not three
  (`test/local_tracks_rescan_coalescing_test.dart` counts provider executions);
  Riverpod marks the element dirty and flushes once per turn, so an app-level
  coalescer would duplicate the framework. One walk per deliberate delete is the
  intended behavior and a warm walk is 38 ms at 516 files. No bulk-delete UI for
  local files exists, and the only other invalidation sites are pull-to-refresh,
  the refresh button and Android/iOS permission grants. Do not re-propose
  invalidation coalescing here without new evidence (e.g. a per-download
  invalidation, which does not exist today).
  - 2026-10-21 update: a bulk-delete UI now exists — "Delete local library" on
    the Local Library page. It invalidates `localTracksProvider` **once** per
    wipe, so the coalescing finding above still holds; file removal itself runs
    in waves of 32 (`_deleteInWaves`) because a whole library is one syscall per
    file and would otherwise block the UI isolate.
- 2026-09-22: the session `RateLimitGate` now covers **interactive metadata
  reads**, not just saved-list builds. `runGated` (`provider/metadata_plugin/
  utils/rate_limit_gate.dart`) holds the gate logic and takes its retry budget;
  `MetadataPluginMixin.fetchGated` (0 retries) wraps the 15 provider `build()`s
  that navigation rebuilds — browse sections/items, all four search families +
  search-all, artist/albums/top-tracks/related, album releases, album +
  playlist tracks, playlist, track — and `fetchWithRateLimitRetry` is the same
  helper with `maxRetries: maxRateLimitAutoRetries`, so the saved-list ladder is
  unchanged. Interactive reads wait out nothing: a 429 strikes the gate and
  surfaces at once, `ErrorBox` renders the friendly message, and its
  invalidate-on-retry re-probes only after the cooldown. Deliberately **not**
  gated: `fetchMore`/`fetchAll` paging (scroll-driven, one call per page),
  mutations (`playlist.create/modify`, scrobble, radio), and
  `metadataPluginUserProvider` — one `/me` per session that the sidebar reads to
  decide whether the account looks signed in, so an unrelated 429 must not be
  able to make the profile look logged out. Measured in
  `test/rate_limit_gate_rollout_test.dart`: a screen burst of 16 gated reads
  after one 429 issues **1** plugin call (was 16); 483 tests green.

- 2026-09-21: yt-dlp "is not installed" on a correctly configured machine was
  an environment assumption, not a missing binary. `YtDlpEngine.isInstalled()`
  delegated to `yt_dlp_dart`'s `checkAvailableInPath()`, a pure `$PATH` scan,
  and a desktop session hands GUI apps a PATH without `~/.local/bin` — where
  pip --user / `uv tool install` / pipx put it. `lib/main.dart` then set the
  binary location from the same bare `"yt-dlp"`, so the engine threw
  `FileSystemException` at startup and every yt-dlp resolution failed, not
  just the dialog. Fixed by `YtDlpEngine.resolveBinaryPath()`
  (`lib/services/youtube_engine/yt_dlp_engine.dart`): PATH first, then
  `commonInstallDirs()` (`~/.local/bin`, `~/bin`, `~/.cargo/bin`,
  `/usr/local/bin`, `/opt/homebrew/bin`, `/opt/local/bin`, `/snap/bin`,
  `/usr/bin`; WinGet Links + scoop shims on Windows), and `main.dart` passes
  the absolute result to `setBinaryLocation`. A stored custom path still wins.
  Covered by `test/yt_dlp_binary_resolution_test.dart`; verified against the
  live PATH of a running instance (`/home/adamya/.local/bin/yt-dlp` resolved
  where the old scan found nothing).
- 2026-09-22: The same dialog returned **without a code regression**. The
  instance in use was `/usr/local/bin/spotube` →
  `/usr/local/share/spotube-custom/`, deployed Sep 14, i.e. predating
  `resolveBinaryPath()`; the freshly built bundle carrying the fix was never
  copied there. Before re-diagnosing a "fixed" engine-detection bug, compare
  the mtime of the running `libapp.so` against the source fix, and grep it for
  a fallback-dir string (`/snap/bin`) — absent means a stale deploy, not a
  code bug. Redeploy with `sudo cp -a build/linux/x64/release/bundle/.
  /usr/local/share/spotube-custom/` (root-owned; no Makefile target for it).
- 2026-09-21: The artist page's album column ("unknown" on every row) is a
  **plugin-side** gap, not a host bug — `queryArtistOverview` is a persisted
  GraphQL operation whose `albumOfTrack` selection carries `uri` + `coverArt`
  but no title, so the client cannot ask for the name. Fixed in
  `hetu_spotify_gql_client/lib/assets/hetu/artist.ht` `topTracks`: the
  placeholder is now `""` and titles come from the **same response's**
  `discography.{albums,singles,compilations}.items[].releases` (free, covers
  the page in the common case), then a session-bounded `albumNames` map, and
  only a genuinely leftover id triggers `GET /v1/albums?ids=…` (deduped, ≤90
  ids). A batch that returns nothing usable puts the Web API on a 5-minute
  plugin-side cooldown, because `RateLimitGate` only governs host→plugin calls
  and cannot see a request made inside the Hetu VM. `RequestOptions(validateStatus:)`
  is permissive on purpose because Hetu 0.4.2 cannot catch a rejected future in
  script — verified live that a 401/429 *resolves* with `statusCode` readable
  and `data` a native `Map`, so a rate-limited batch degrades the column
  instead of the section. An unconditional batch was tried first and observed
  live as `st=429`: same failure class as entry 1 above (REST re-hydration on
  the bucket Spotify actually throttles), so do not add per-row REST back.
  **Nothing in this repo changed**; `lib/` and `test/` are untouched. Do not
  re-diagnose the album column from the host side.
- 2026-09-22: Playlist rows showing `0:00` for **every** track is another
  **plugin-side** gap, not a host bug, and the key name is now **verified
  against a live response** (a temporary `print` in the installed bytecode
  logged `duration=null trackDuration=224452` for every row of a Hindi rap
  playlist before it was removed): Spotify's persisted `fetchPlaylist`
  operation (`bb67e0af…`) selects the track length as `trackDuration
  { totalMilliseconds }`, while the other overview operations
  (`albumUnion`, `search`, `getTrack`, the saved-tracks ladder) select it as
  `duration`. `hetu_spotify_gql_client/lib/assets/hetu/playlist.ht` read only
  `item["duration"]?["totalMilliseconds"]`, so every playlist page got `null`,
  and the plugin converter's `?? 0` (`src/converter/converter.ht`) turned that
  into a silent `0:00` — which is why album/artist/search/liked looked fine and
  every playlist (incl. the home-page radio playlists) did not. Fixed with a
  `?? trackDuration ?? duration_ms` fallback chain in `tracks()`, the only
  duration site in that file — the same chain `lavende-core`'s extractor uses
  for these objects. `test/playlist_null_fix_test.dart` pins all three
  spellings plus the null case. Nothing in this repo changed; no re-hydration
  was added — the field is already in the response the page fetches. Playlist
  *track* pages are not snapshot-cached (only the four saved lists are), so new
  bytecode applies on the next fetch. Installed as a like-for-like
  `plugin.out` swap (version string unchanged, so the session token, which is
  keyed by plugin **name**, survived); previous build kept as
  `plugin.out.bak` beside it.
- 2026-09-22: Lyrics "not fetching" was four separate defects, all in the
  answer-acceptance path, not in the network. (1) `LRCLibLyricsProvider` sent
  only `track.artists.first.name` to `/api/get`, which is an **exact-match**
  endpoint — LRCLib stores `"Hardbone boy,SINASH"` where Spotify says
  `"Hardbone boy, SINASH"`, so every multi-artist track 404s. Fixed by falling
  back to `/api/search` (fuzzy; returns ~20 ranked entries) and picking with
  `selectLrclibEntry`: timed beats plain, album agreement breaks ties, an
  entry >30 s off the track length is dropped. (2) Dio threw on 404/503, so the
  `statusCode != 200` branches in both providers were dead; both now pass
  `validateStatus: (_) => true` and report a miss as an empty answer.
  (3) `SyncedLyricsNotifier` accepted any non-empty list as a hit — an empty
  `plainLyrics` splits to `[""]`, which is non-empty, so a blank answer was
  shown *and cached forever*, and a plain answer blocked a later synced one.
  `SubtitleSimple.hasContent` / `.isSynced` are now the predicates, and an
  unsynced answer is held while the remaining providers get a chance.
  (4) `lyricsTable.trackId` has **no unique index** (the primary key is an
  autoincrement `id`), so `insert(mode: replace)` can leave two rows per track
  while the read was `getSingleOrNull()` → `Bad state: Too many elements`,
  permanently breaking that track. The read now takes every row, keeps the best
  (content, then timestamps, then newest), and the write deletes before
  inserting. No migration: bad rows heal on the next read.
  `BetterLyricsLyricsProvider` is a dead fallback for new lookups — the public
  endpoint answers `401 {"error":"API key required"}` for uncached queries
  (verified live); it still serves whatever it happens to have cached, so it is
  kept last in the registry. Reference implementation for comparison: the
  Caelestia shell (`/usr/lib/qt6/qml/Caelestia/lib/libcaelestia-services.so`)
  does search → `/get/{id}`, rejects answers with no `syncedLyrics`, offers the
  user `lyricCandidates`, and pins its picks in
  `~/.local/state/caelestia/lyrics/lyrics_map.json`.
  Tests: `test/lyrics_provider_registry_test.dart` (cache + priority rules),
  `test/lrclib_entry_selection_test.dart` (ranking).
- 2026-09-21: Theme shell switches (phase 2 of the UI-extension plan), **dormant
  by default**. `ThemeLayout` (`lib/models/metadata/theme.dart`) carries three
  enums — `chrome: inset|fill`, `nav: rail|bar`, `progress: above|below` — and
  the host reads them through `AppLayoutX.insetChrome` / `.iconOnlyNav` /
  `.progressBelow`. Consumers: `pages/root/root_app.dart` (content floats in a
  rounded panel over a `chromeInkColor` backdrop), `modules/root/sidebar/sidebar.dart`
  (`NavigationRail` instead of the labeled sidebar; `showLabels` also drives
  `SidebarFooter(compact:)`), and `modules/root/bottom_player.dart` +
  `modules/player/player_progress.dart` (seek row spans the player beneath the
  transport instead of docking above it). Unknown or absent values fall back to
  the pre-existing Spotube shape per field, so the default look is unchanged
  with no plugin installed. `sidebarBottomClearanceOf` still *reserves* the
  player's height regardless of the nav switch — see the footer-intrinsics entry
  above for why it cannot read it. Verified live on a throwaway profile with
  `spotify-shell-1.0.0.smplug` (source in `~/projects/spotube-theme/`): the
  cached `ThemeDefinition` holds all three switches and the rail renders, with
  zero intrinsic/layout errors in the run log. Payload path is pinned by
  `test/spotify_theme_payload_test.dart`, which evaluates the built `.smplug`
  through the real Hetu endpoint. The user chose to keep the original look, so
  the plugin is **not installed** in their profile.

- 2026-09-21: Dead-code pass over the uncommitted theme-shell and
  source-resolution batches — **no behavior change** (analyze clean, 451 green
  before and after). `YouTubeEngine` lost `static isAvailableForPlatform`,
  `static isInstalled()`, `getVideoWithStreamInfo` and `void dispose()`: Dart
  statics are not inherited, every real caller uses a concrete class, and the
  Hetu path already calls `getVideo` + `getStreamManifest` separately
  (`lib/services/metadata/metadata.dart`). **Do not re-add them** — the interface
  is now `getVideo` / `getStreamManifest` / `searchVideos` only.
  `YouTubeExplodeEngine.dispose` stays (releases a live isolate), the empty
  `NewPipeEngine`/`YtDlpEngine` overrides did not. Also gone:
  `classifyCachedSourceMatch`'s unused `ttl` parameter,
  `IsolatedYoutubeExplode.search`'s discarded `filter` (and the worker's
  `arguments.elementAtOrNull(1)` read), `SourcedTrack.swapWithSiblingOfIndex`,
  `PluginVmCache.evict`, `AppLayout.maybeOf`, the unreachable `mdAndDown` half of
  `ConnectDeviceButton`'s sidebar branch, `SidebarFooter implements
  NavigationBarItem`, the redundant opacity re-clamp in
  `theme_background_layer.dart`, and the `getVideoWithStreamInfo` plumbing in
  both engines. `resolveFirstAvailable`'s `attempt` and `buildSavedList`'s
  `cooldown` are test seams, now marked / left public on purpose.
  `sourceCandidateKey` was still listed there as open; the three `SourcedTrack`
  rebuild paths were fixed on 2026-09-23 (see the fetch-latency entry).

- 2026-09-21: Theme plugins can resize the UI (phases 0-1 of the UI-extension
  plan). `ThemeDefinition.tokens` (`cardWidth`/`cardHeight`/`artistCardWidth`/
  `artistCardHeight`/`gutter`/`fontFamily`) added; `sanitizeThemeDefinition`
  moved to `lib/services/metadata/theme_sanitizer.dart` (no Hetu import) with
  render ranges for every number, and is now applied on **all** three paths that
  can produce a theme — plugin endpoint, `mergeShellPalette`, and the warm-start
  cache read — where before only the endpoint path was clamped. `density` is
  rendered by riding `AdaptiveScaling.only(sizeScaling/textScaling)` in
  `main.dart`, so every existing `* scale` site honors it for free; the full
  radius scale reaches Spotube-drawn surfaces (`radius.small` → card covers,
  replacing shadcn's `borderRadiusMd`, which is 6px at the default multiplier).
  `AppLayout` + `AppLayoutX` (`lib/modules/app_layout/app_layout.dart`) is the
  single source for card geometry; `card_extent.dart` folded into it. Migrated:
  `PlaybuttonCard`, `ArtistCard`, `HorizontalPlaybuttonCardView`, the
  `PlaybuttonView` grid and the artists/search/section grids — all of which
  carried their own 150/180/200/225/250/8/10/12 literals. Grid gutters are one
  token now, so the three artist grids moved from 8-10px to the 12px default.
  Cells can never be shorter than their content (min-height guards in the
  getters), which is what keeps a hostile theme from re-creating the 3px
  overflow. New `test/theme_layout_tokens_test.dart` (9) and 3 more cases in
  `test/artist_card_extent_test.dart`, including a negative control that proves
  a literal 120px artist cell really does overflow by 229px. Suite 413 → 427
  green, analyze clean, debug build relaunched: 0 overflow lines, home page
  screenshot identical to before at default tokens.
  Not done (phase 2+): slot descriptors, page templates, manifest validation.

- 2026-09-21: Playback "not found" now widens across YouTube engines instead of
  ending the resolution (see "Playback \"not found\" never widened to the other
  engines" above). `primaryCandidate` / `engineFallbackCandidates` /
  `resolveFirstAvailable` added to `SourceResolver`, dead
  `resolveTrackWithFallback` removed, `fetchFromTrack` distinguishes an answered
  miss from a backend that could not answer.
  New `test/source_engine_fallback_test.dart` (9 tests). Suite 401 → 410 green.

- 2026-09-21: YouTube engine search decoupled from `youtube_explode_dart`'s
  `Video` (see "yt-dlp / YouTubeExplode engines failing" above). New
  `test/youtube_engine_search_results_test.dart` (8 tests) pins real flat-playlist
  rows — including the `channel_id: null` music upload that used to abort the
  page. Suite 393 → 401 green, analyze clean.

- 2026-09-21: Source-recall fix (see "Tracks reported not found" above).
  New `test/source_query_variants_test.dart` (9 tests) pins the variant ladder
  and the ranking normalization; both proven to fail with the fix reverted
  (rank case picked the imposter video on the old comparison). Suite 384 → 393
  green, analyze clean. `searchVideos` deliberately keeps
  `contentFilters: [videos]` — an earlier attempt to drop it broke every search
  (third-party channel-row deserialization crash) and was reverted.
- 2026-09-21: Full test-suite usefulness audit (44 files, 389 tests → 384) +
  fixes. Weak tests: `lyrics_provider_registry_test.dart` rewritten to drive
  the real `SyncedLyricsNotifier` + in-memory DB via the global `lyricsProviders`
  seam (was testing a copy of the production loop); `widget_test.dart` deleted
  (asserted nothing); drift template "v1→v2 data" replaced by a real v4→v14
  data-integrity test (pins the Blue→Slate accent rewrite; `piped_instance`
  correctly gone by v14); membership scaling tests got a genuine nested-scan
  oracle (old `_naive` delegated to production = tautology) + threshold gates;
  retry-schedule test pins its exponential contract; delegation-equality test
  deleted from `player_active_track_select_test.dart`. Duplication: redundant
  v9 quarantine case dropped from `source_match_migration_proof_test.dart`
  (superset lives in `quarantine_migration_test.dart`), verbatim mirror-policy
  test dropped from `playback_cache_mirror_test.dart`; `image_decode_size`
  "duplicate" verified distinct (fractional-dim rounding) and kept. Flake:
  ~30 fixed wall-clock sleeps (50–800 ms) across 10 files replaced with the
  `drain()` (zero-yield event-loop pumping, negative proofs) / `eventually()`
  (bounded polling, positive waits) convention; absolute-ms gates in
  `history_scaling`/`queue_persistence` converted to generous relative
  factors. Remaining real sleeps are intentional (fake-server latency in
  `download_cancel`/`local_tracks_scan`/`stream_validation`, poll ticks).
  Use this convention for new timing tests. 384 green + analyze clean.

- 2026-09-21: Playlists↔Local-library transition jitter fixed —
  `UserLocalLibraryPage` and `LocalFolderItem` called
  `useFuture(UserPreferencesNotifier.getMusicCacheDir())` inline; flutter_hooks
  0.20.5 re-subscribes whenever the Future *instance* changes, so a fresh
  future per build produced an infinite rebuild loop while the page was open
  (debug CPU 25-60%, repeated RenderFlex-overflow repaint spam). Both sites now
  `useMemoized` the future. Regression test
  `test/local_library_rebuild_storm_test.dart` (bounded pump loop fails on the
  old pattern, settles on the new; 388 tests green). Same latent pattern still
  exists in `lib/modules/connect/local_devices.dart:14,16`
  (`useFuture(audioPlayer.devices)` getter) — left unfixed, different page.

- 2026-09-21: 429 defense-in-depth landed (commits `b425b8ee`, `c2a21b4d`,
  `c8b9adb9`) — session-wide `RateLimitGate` (escalating backoff, 10 min cap,
  fail-fast with `RateLimitedUntilException`), persisted library snapshots
  (Drift v14 `library_snapshot_table`; written on completed `fetchAll`/
  single-page builds, served as stale fallback when the gate is closed or
  retries exhaust; cleared on login/logout). 387 tests green. Superseded as
  the *primary* fix by the plugin-side inline hydration below, but stays as
  the quota-exhaustion safety net.
- 2026-09-21: 429 rate-limit hardening landed (commits `23e8d6c6`, `be5ac860`,
  `11d2eb1d`) — shared saved-artist/album id-set providers (kills per-id
  `fetchAll` fan-out), `fetchWithRateLimitRetry` (2 retries × 30 s) in all four
  saved-list builds, friendly `ErrorBox` message, 429 now retryable in
  downloads. Verified live: Albums auto-retried twice, then showed the friendly
  card. 362 tests green. `Retry-After` honoring still needs a plugin-repo change.
- 2026-09-20: PR 7 (C9) **measured and rejected** — no code changed. The real
  metadata_god bridge was benchmarked against the 516-file library and synthetic
  2k/8k fixtures; a persistent metadata cache saves only ~2.2× of a 38–510 ms
  once-per-process background scan. Side finding recorded under Open Problems
  (orphaned temp artwork). Throwaway benchmark files deleted.
- 2026-09-20: PR 6 (C6 + C8) landed in the working tree — `UniversalImage`
  `FileImage` branch honours requested dimensions via `ResizeImage`;
  `AudioPlayerState.listContainsTracks` set-indexed with a ≤256-pair scan
  fallback. Two suites added (`universal_image_source_test.dart`,
  `player_membership_test.dart`); four further candidates measured and rejected.
- 2026-09-20: PR 5 (C3 + C11) landed — position ticks share one 1 Hz ticker and
  a single `playerStreamPositions` provider; stream subscriptions are drained
  with a completion event instead of `asFuture()`.
- 2026-09-20: PR 4 (C5) landed — playback proxy caches the HEAD content-type
  probe per `track id|url` for 5 s; music-cache root resolved once per process.
- 2026-09-20: PR 3 (C2) landed — queue persisted on playlist mutations rather
  than on every position tick, debounced.
- 2026-09-20: PR 2 (C1) landed in the working tree — playback-history top tracks
  aggregated in SQL, one parse per group, Stats families autoDispose; equivalence,
  repair-semantics and scaling tests added (307 tests green).
- 2026-09-20: Correctness remediation pass (16 audit items) landed in the
  working tree — see the Completed entry above and `.ai/CHANGELOG.md`.
- 2026-09-20: Playback 403 loop fixed — engine manifest falls back to the TV
  client; refreshStream fallback re-validates or throws (NoValidStreamError).
- 2026-09-19: Lyrics sync rewrite (binary search) + Better Lyrics provider added.
- 2026-09-19: Hetu plugin VM caching + lazy playback fallback verified (RSS
  plateaus, compile count flat).

## Verification Status

- `fvm flutter analyze`: pass (no issues) — 2026-09-23 (after the volume-control
  mode feature; previously the same day for the download/mirror wiring).
- Volume-control mode (v17): `fvm flutter test test/drift/app_db/migration_test.dart`
  + player suites and `test/volume_control_footer_test.dart` green (162 tests across
  the run), analyze clean — 2026-09-23. Not yet seen in a running build.
- `fvm flutter analyze`: pass (no issues) — 2026-09-23 (after the download/mirror
  wiring; previously the same day for the palette-transition fade).
- `fvm flutter test`: **647 tests pass** — 2026-09-23 (baseline was 283; +24 from
  the PR 1/PR 2 history and perf suites, +5 queue persistence, +8 playback proxy,
  +16 position tick / queue-payload suite after PR 5 rewrote it, +14 from the PR 6
  artwork-decode and membership suites, +6 membership regression tests for
  `AudioPlayerState.containsTracks`, then the source-resolution, library-snapshot,
  rate-limit, local-library, theme-shell/layout and theme-payload suites up to 451,
  then the NewPipe tiering, Caelestia shell and `theme_transition_test.dart` suites up
  to 581 — part of that 451→581 span landed without a doc update, so it is not all one
  change). +27 of the 647 are the download/mirror suites: `download_persistence_test.dart`
  (9), `playlist_reconcile_test.dart` (11), `download_playlist_dedup_test.dart` (6) and one
  new case in `track_options_select_test.dart`, where the `downloadTask` watch is now keyed
  by the row's own track instead of whatever is playing.
- Linux release build: passes — 2026-09-23 (rebuilt for the palette-transition work;
  previously 2026-09-21 after the dead-code pass).
- Palette-transition fade verified in-app, 2026-09-23, on that release bundle driven
  with `grim` + `ydotool` (ydotoold on a private socket; its absolute axis spans half
  the 1920x1080 output, so compositor pixels are 2× the units it accepts). **Run
  against a copy of the real data dir** (`XDG_DATA_HOME=/tmp/…`), because the user's
  own `/usr/local/bin/spotube` was live and shares `~/.local/share/oss.krtirtho.spotube`;
  the shipped database is still at v14. A second instance also needs its own session
  bus (`dbus-run-session`) — `MyApplication` sets a fixed application id, so a plain
  second launch is silently swallowed by GApplication's single-instance handoff
  (exit 0, no window).
  - Migration on the real 2 MB database: v14 → v15 added `theme_transition`
    (`INTEGER NOT NULL DEFAULT 0`) and `theme_transition_ms`
    (`INTEGER NOT NULL DEFAULT 250`), and the existing row kept its data.
  - Mean-colour trace of a fixed 400×400 patch at ~23 ms/frame. **Off**: one frame
    step, 34.3/25.3/27.4 → 248.3/246.5/246.8, no intermediate value. **On at 1 s**:
    ~40 distinct monotonic values across ~950 ms, settling exactly on the light
    palette. **On at 0.1 s**: three intermediate frames, ~90 ms. So the stored length
    demonstrably sets the pace and a disabled transition is a true snap.
  - Shell path: rewriting `~/.local/state/caelestia/scheme.json` (temp+rename, as
    Caelestia itself does) produced **one** fade starting +0.29–0.46 s after the write
    — the 300 ms trailing debounce — and the file restore produced a matching fade
    back onto the original palette. Six writes at 120 ms intervals produced no fade at
    all until ~290 ms after the last one, i.e. the coalescing is real.
  - Settings UI: the switch and the 0.1/0.15/0.25/0.4/0.6/1.0 s select render, the
    duration row appears only while the switch is on, and both survive a restart
    (1/100 read back from drift after relaunch, library intact).
  - Smoothness caveat: the ≥40 distinct values per second of fade is a
    compositor-side lower bound from screenshot sampling, **not** a timeline trace —
    no `--profile` run was taken, and `.ai/PERFORMANCE.md` still carries no Android
    numbers (no device, AVD or adb here).
- In-app verification on that release bundle, 2026-09-20 (fresh process, real
  session, `wpctl` + `grim` + synthetic pointer):
  - Queue restore: `audio_player_state_table` had 1 row / 494 KB `tracks` /
    `current_index=5`; after restart the player bar showed that track at its
    stored duration and the queue advanced 5 → 6 → 7 on natural track end.
  - Track start: mpv output stream `[active]` on the speaker sink, position
    advancing in real time.
  - Progress label: 40 samples at 300 ms → 12 distinct values, each held
    0.94–1.03 s. Exactly 1 Hz (was 5 Hz before the shared ticker).
  - Stats page renders (87 min / 26 songs / $0.10 / 40 artists / 3 albums /
    5 playlists + Top Tracks play counts) — PR 1/PR 2 history aggregation.
  - Local Library folder grid renders with embedded artwork; no folder
    highlighted while a non-local track plays (negative case).
  - Log after all of the above: no Dart errors or exceptions.
- PR 6 re-verified in-app on the rebuilt release bundle (same session, synthetic
  pointer + `grim`): Browse renders all remote artwork; queue restored again
  ("PPP | 06.02.2022", 02:17) with its cover in the player bar; Local Library
  folder grid renders both folder cards with their 4-tile artwork collages;
  opening **Downloads** shows the local track rows with embedded sidecar artwork
  at 80×80 — sharp, correctly aspect-preserved, no stretching or placeholder. The
  playing row is indicated by the per-row icon (`activeTrackId == track.id`),
  which is the `TrackTile` path the `ResizeImage` change touches.
- Folder "playing" **highlight** positive case — CLOSED 2026-09-21 on a release
  bundle rebuilt after the `containsTracks` fix (same synthetic-pointer method):
  with a local track playing, the Downloads folder header flips to the stop icon
  and Shuffle / Add-to-queue go disabled, i.e. `listContainsTracks` returned a
  correct **positive**; switching to Cache folder returned a correct **negative**
  (Play icon, load proceeded). The active row is highlighted in the track list.
  Queue state after the run: playback stopped, queue cleared; nothing else touched.
## Fetch-efficiency pass (2026-09-24, working tree, uncommitted)

Six verified over-fetch fixes, implemented alongside (not overlapping) the
parallel downloads/metadata agent's work. Deliberately untouched: everything
under download/mirror providers, `download_manager_provider.dart`,
`paginated.dart`, playlist/library pages, tile callbacks.

1. **Lyrics** (`services/lyrics/*`, `provider/lyrics/synced.dart`): process-wide
   UA memo (was 2 platform-channel reads/track), 10s receive timeout on LRCLib
   (was 30s global), 24h bounded in-memory miss cache (misses refetched every
   visit before), `compute()` parse for docs >16KiB, single-flight per track
   id. Tests: `lyrics_fetch_efficiency_test.dart` (7). Caught by its own
   tests: `whenComplete` teardown rethrew failures as unhandled zone errors —
   fixed with non-rethrowing `then` handlers.
2. **Artwork bytes memo** (`utils/service_utils.dart:artworkBytes`, bounded 64
   URLs, failures not retained, concurrent callers share one future):
   download worker, playback-cache finalize (`playback.dart:627`) and palette
   hook now share one fetch per URL. Palette also cancels superseded fetches
   and samples at 50px. `download_manager_provider.dart` intentionally *not*
   touched (other agent's file). Tests: `artwork_bytes_memo_test.dart` (2).
3. **Wikipedia** (`artist/wikipedia.dart`): family keyed by `(id, name)` with
   7-day `cacheFor` (was object-keyed, no cache, up-to-2 HTTP per view).
   Callers updated (`footer.dart`, `artist.dart` refresh). Tests:
   `artist_wikipedia_test.dart` (3).
4. **Update checks** (schema v17→v18, `preferences.last_update_check_ms`):
   app + 2 plugin checks gated to one burst/24h via `isUpdateCheckDue`,
   stamp-on-attempt. Snapshots regenerated (`drift_schema_v18.json`,
   untracked like v16/v17; migration-test half is local-only per `.gitignore`
   on `/test/`). Tests: `update_check_interval_test.dart` (5), 17→18
   migration green.
5. **Endless radio** (`hooks/configurators/use_endless_playback.dart`):
   `EndlessRadioGate` (claim/serve/release) stops the mount-at-end +
   stream + resubscribe triple-fetch; served tails never refetch (would only
   re-append dupes). Tests: `endless_radio_gate_test.dart` (6).
6. **Provider lifecycles** (track, browse sections/items, releases, artist
   albums/related): non-autoDispose → autoDispose + 5-min `cacheFor`, and
   AsyncValue watches → `.future` watches (the loading emission was rebuilding
   and refetching page 1 twice per mount — proven red pre-fix for both
   shapes). Logout/plugin-switch invalidation preserved. Tests:
   `provider_lifecycle_test.dart` (6). Same coarse-watch shape confirmed (not
   fixed, out of scope) in: search/*, tracks/album|playlist, artist/artist,
   top_tracks, scrobble.

## Metadata over-fetch pass (Fix 1, committed 2026-09-24)

Fix plan (pivoted after downloads Phase 1): "metadata over-fetching, modeled
on how the official clients do it." Fix 1 = **IsSaved via batch contains**.

- Before: every `metadataPluginIsSaved{Track,Album,Artist}Provider(id)` family
  instance awaited a `metadataPluginSaved{Track,Album,Artist}IdsProvider`,
  which ran `fetchAll()` — a full paginated walk — whenever `hasMore` was
  still true. On a 5,000-track library, one home-page render fired ~50
  sequential listing requests per kind, and the same walk was re-entered
  whenever an optimistic add/remove toggled state. `metadataPluginIsSaved-
  PlaylistProvider` walked the whole saved-playlists list per id too, even
  though `isSavedPlaylist(id)` already exists at `endpoints/user.dart:101`.
- After: an `IsSavedBatcher` coalesces per-id requests made in the same
  event-loop tick into one `plugin.user.isSaved*(ids)` call, chunked at 50
  ids to match Spotify's `contains` limit. Family surface preserved:
  `ref.watch(metadataPluginIsSavedTrackProvider(track.id))` still returns
  `AsyncValue<bool>`. `addFavorite`/`removeFavorite` now invalidate the
  family for each toggled id — the optimistic list state is unchanged, but
  the per-id answer refreshes from the plugin on next read.
- Playlists get a lighter version: `metadataPluginIsSavedPlaylistProvider`
  awaits `savedPlaylistLookupProvider` which calls `isSavedPlaylist(id)`
  directly. No batcher (no bulk endpoint exists).
- `metadataPluginSaved{Track,Album,Artist}IdsProvider` removed. Full
  `fetchAll()` walks remain only where the *entire* list is genuinely needed:
  Liked Songs page, offline snapshot persistence, `playlist_card.dart`'s
  total-track count.
- Batcher lives in `lib/provider/metadata_plugin/library/is_saved_batcher.dart`
  and is exposed via three `Provider<IsSavedBatcher>` seams
  (`savedTrackBatcherProvider`, `savedAlbumBatcherProvider`,
  `savedArtistBatcherProvider`) plus a `savedPlaylistLookupProvider`
  (`Future<bool> Function(String)`), so tests never need a live plugin VM.
- Files touched: `library/{tracks,albums,artists,playlists}.dart`, new
  `library/is_saved_batcher.dart`.
- Tests: new `test/is_saved_batch_test.dart` (8 unit cases — batching,
  dedup, 50/51 chunking, walk-equivalence, error propagation,
  length-mismatch, mid-flush re-entry, custom max), rewritten
  `test/saved_id_sets_test.dart` (5 family-provider integration cases
  including the 51-id burst → [50, 1] plugin-call fan-out and the
  `isSavedPlaylist` single-flight no-false-negative case). All 734 tests
  green; `fvm flutter analyze` clean.
- Commit `45fb04fb` on `opt/downloads-perf`.
- Not done in Fix 1, deferred to Fix 2..5 in the user's plan (play page-1,
  SWR merge, dialog pagination, subscription dedupe).

### Fixes 2..5 landed (2026-09-24, `opt/downloads-perf`)

- **Fix 2** (commit `6d99151c`): taps start playback from the already-loaded
  page and append the walked tail in the background via
  `appendCollectionTail` (`components/track_presentation/append_playback_tail.dart`),
  used by tile-tap / play / shuffle and the playlist/album cards. Guarded so a
  collection replaced mid-walk is left alone.
- **Fix 3** (commit `88dde7ef`): `_revalidate` in
  `provider/metadata_plugin/utils/paginated.dart` now merges the page-1 probe
  into the served snapshot (`_mergeRevalidation`) instead of replacing state
  wholesale — a page-1 probe no longer shrinks a fully-walked list back to 20
  items. When the probe reports no further page it still replaces outright, so
  genuinely unsaved items are not resurrected. `test/library_snapshot_test.dart`
  gains a merge group.
- **Fix 4** (commit `d7e0949d`): the add-to-playlist dialog paginates (page 1
  at once, `fetchMore` on scroll + auto-fill) instead of a full `fetchAll()`
  walk. Album and playlist pull-to-refresh no longer invalidate the whole
  saved-albums / saved-playlists library (they observe the per-id heart from
  Fix 1, not the list).
- **Fix 5** (commit this): subscription dedupe, no behavior change.
  - `isUserPlaylistProvider` (`library/playlists.dart`) is the single derived
    boolean replacing the `useIsUserPlaylist` hook that three widgets
    (page header, `presentation_top`, `presentation_list`) each backed with a
    full `ref.watch(metadataPluginSavedPlaylistsProvider)`. The page resolves
    it once and passes it through `TrackPresentationOptions.isUserPlaylist`;
    `use_is_user_playlist.dart` deleted. Test: `is_user_playlist_provider_test.dart`.
  - `PlaylistPage` watches `mirroredPlaylistTracksProvider` only while the
    network view is absent (was: unconditionally, rebuilding the page on every
    download-progress tick while online). The notifier keeps its own mirror
    listener — removing it would change offline live-update behavior, so Fix 5
    did NOT collapse that side.
- All 744 tests green; `fvm flutter analyze` clean.


## Provider coarse-watch fix, remaining 7 (2026-09-24, working tree)

Follow-up to the 6-file lifecycle sweep: the same `ref.watch(plugin
AsyncValue)` loading-echo shape in `tracks/playlist.dart`,
`tracks/album.dart`, `artist/top_tracks.dart` (correction: top_tracks was
*not* already good — it had `cacheFor` but still the echo),
`search/tracks|albums|artists|playlists.dart`. One-line change each to
`await ref.watch(metadataPluginProvider.future)`; AutoDispose, cacheFor,
APIs, fetch bodies, first-data timing and plugin-switch invalidation all
preserved. `provider_lifecycle_test.dart` extended with 7 endpoint-count
cases (stub plugin): red-proven on `tracks/playlist.dart` (revert → 2 calls,
restore → 1), 13/13 green ×4 runs, full suite 742/742, analyze clean.
`core/scrobble.dart` intentionally untouched (single controller, no double
fire — churn-only). `search/all.dart` out of scope (separate retention
question). Validation note: the other agent's `is_saved_batcher.dart`
broke tree compilation mid-session (`Timer.run` void misuse, since fixed on
their side); a later transient `unused_import` in their
`presentation_list.dart` refactor also settled on their side. No cross-lane
file edits in either direction.

## Landing A — backdrop decode + blur freeze (2026-09-24, working tree)

One landing, four separable pieces. No visual change by construction:
sigmas, overlays, gradients and sizes at rest are identical; only decode
sizes and mid-scroll blur work changed. Mobile-only freeze; 400ms settle,
desktop signal and `scroll_motion.dart` untouched.

- **A1 theme background**: `themeBackgroundImageProvider` is now a family
  keyed by quantized side (`quantizeBackdropSide`, lyrics 256-step rule);
  layer + scope share one cached instance/decode. Layer freezes its blur via
  the existing `chromeBlurFrozen` (sigma 0 while frozen).
- **A2 track page**: backdrop decodes at the quantized band; sigma-10 filter
  frozen on `scrollInFlightProvider`. Chose sigma ternaries over
  widget-removal after the collection-if form reindented a 170-line subtree
  (same convention as the nav-bar frost).
- **A3 freeze holes**: lyrics `SurfaceCard` frozen on scroll; carousel
  reports motion through a nested `ScrollMotionScope` below its scrollbar
  swallow (scrollbar behavior unchanged). Connect drawer deliberately
  deferred: shadcn bakes `surfaceBlur` into the overlay entry at open time
  (`drawer.dart:193,203,228`), so no parent-side freeze can reach an open
  drawer without package support.
- **A4 key hygiene**: `PlaybuttonTile` is a `HookWidget` with a memoized,
  whole-px provider; artist footer falls back to the quantized band when
  Wikipedia omits thumbnail dims (was silent full-res); connect art capped
  at its 350px box.
- Tests: `backdrop_decode_test.dart` (4); `shell_rebuild_navigation_test`
  override updated to family form (shape only). Full suite 748/748, analyze
  clean. GPU-side wins (fewer decodes, no per-frame re-blur) are
  not runtime-verified — needs a DevTools scroll timeline on device.

## Test-suite hygiene pass (2026-09-24, working tree)

84 files / 521 `test()` cases / ~25s full run: count is a hygiene question,
not a speed problem. Audited every file for overlap; nearly all of it is
intentional unit-vs-integration layering, not duplication.

- **Merged (1 test removed):** `download_media_test.dart`'s
  `cachedFileStreamResponse` group duplicated `download_first_playback_test`'s
  6-case `response builders` group. Folded its one unique assertion
  (`isNot(isA<Uint8List>())`, the no-buffering rule) into the surviving test
  and deleted the group plus its now-unused imports.
- **Deliberately kept:** `source_resolver` vs `source_quality_fallback`
  (different methods/rules, not duplicates despite the theme);
  `is_saved_batch` vs `saved_id_sets`, `lyrics registry` vs `lyrics
  efficiency`, `queue_batch` vs `queue_persistence`, history/local/playback
  families (unit/integration layering); the five tiny helper files
  (`update_check_interval`, `endless_radio_gate`, `stream_url_expiry`,
  `backdrop_decode`, `engine_call_budget`) stay separate — 1:1 file-to-unit
  mapping beats saving 4 files.
- No assertions weakened; suite green after the merge.

## Test-harness dedup (2026-09-24, working tree, test/ only)

`test/support/common_fakes.dart` holds the five byte-identical doubles found
copied across files: `FakePathProvider` (7 files, superset of all method
variants incl. `getApplicationCachePath`), `StubPrefsNotifier`,
`EmptyMetadataPluginNotifier`, `FixedPresetsNotifier`,
`NeverResolvesSourcedTrackNotifier`, plus `newMemoryDatabase()`. Migrated 11
files to it (incl. `playback_fallback_memo_test.dart`, found in a second
grep sweep). Deliberately not unified: per-test stub plugins (divergent
scripted endpoints), track factories (assertions depend on payloads),
`cache_port_prefs` prefs stub (has a `setPort` mutator),
`source_candidate_key` prefs stub (different shape), and the two
`_AlwaysAuthenticated` variants (sync vs async-loading — the async one
exists to exercise the provider loading echo). Net: ~200 lines of
boilerplate removed, zero assertions changed. Suite 747/747, analyze clean.

## Landing A-part-2 — search debounce + queue membership (2026-09-24, branch perf/ui-responsiveness)

- **Search debounce:** reused the existing zero-user `useDebounce` hook at
  200ms (the `presentation_state` filter precedent) in local_folder,
  user_playlists, user_albums, user_artists and blacklist. Memo keys use the
  debounced value plus an emptiness flag so clearing stays instant. Results
  identical; only scheduling changed. Tests: `use_debounce_test.dart` (3).
- **Queue membership:** new `queueMembershipProvider` (`{ids, remoteIds,
  paths}` rebuilt once per queue revision) plus `trackMembershipOfProvider`
  per-row bool family; `track_options_provider` subscribes to the bool.
  Three sets (not one) because the predicate is domain-separated — a single
  merged set would let a local path collide with a remote id; the equivalence
  suite pins the id-fallback branches and both cross-domain negatives.
  `track.dart` deliberately excluded (id-only `containsBy`, different
  predicate). Tests: `queue_membership_test.dart` (11 equivalence + 2
  isolation). Existing track-options/player suites green unmodified.
- Full suite 763/763, analyze clean.

## Landings B (tap-to-audio), C (queue+startup), E (hygiene) — 2026-09-24, branch perf/ui-responsiveness (uncommitted)

- **B0/B4 manifest cache**: `manifestMinExpireSeconds` (unknown poisons) +
  `ManifestCache` LRU-32 keyed track|slug|match, strict-expiry lookup. Wired
  into the `fetchFromTrack` cache-hit path only; failures propagate as before
  and never populate. Proven by `manifest_cache_test` (8 unit + 2
  fetchFromTrack integrations with a counting stub plugin).
- **B1**: DB read + `primaryCandidate` overlapped; plugin/config kept
  sequential deliberately (a missing plugin must throw before plugin-list
  work — overlapping it broke `cache_port_prefs_test` via a real DB build,
  caught and reverted to the safe shape).
- **B2**: `primaryCandidate` memoized per `SourceResolver` instance.
- **B3**: routes-level single-refresh guard (`_refreshStreamingUrlOnce`,
  non-rethrowing teardown so failures never become zone errors); head-probe
  window 5s → 30s (safe: key is the immutable signed URL).
- **B6**: retention window current..+1 → -1..+2; lifecycle test re-tuned to a
  6-track queue (eviction proven on both edges).
- **Deferred with reasons**: validate-selected-first (would change barrier
  semantics); downloaded/resolve overlap (speculation would waste Hetu work
  on every downloaded play); GET-without-HEAD (m3u8 detection needs it).
- **C1**: `uniqueByKey` O(n) for queue `load` dedupe (equivalence-tested),
  `jumpToTrack` clone dropped.
- **C2**: tz + MetadataGod moved post-paint; display/preventClose/SMTC
  fire-and-forget. Kept pre-frame with documented reasons: MediaKit
  (provider-build restore can reach the backend), EncryptedKvStore (first
  DB read decrypts), migrateMacOs (precedes DB construction). Launch itself
  is not unit-testable — needs a manual boot check.
- **D download-worker: deferred.** Lane active (commits 0956e406, 013af346
  implement the prefilter/trackData items). Revisit when stable.
- **E hygiene**: six settings sections watch named-record slices;
  recentSearches capped at 20 in the setter; logs viewer reads an explicit
  256KB tail on line boundaries (previously the page showed whichever final
  decoder chunk the stream ended on). Tests: `logs_tail_test` (4),
  `recent_searches_cap_test` (2).
- Full suite 789/789, analyze clean.

## In-sidebar drag reorder for library tiles + pinned playlists (working tree, uncommitted)

- Scope: everything the Settings → Sidebar dialog could reorder (Library group
  + pinned playlists) is now directly reorderable in the sidebar; the top nav
  stays fixed. Settings dialog kept as the keyboard/accessible fallback, now
  calling the same helpers.
- Interaction (no reorder mode): hover reveals a drag handle for immediate
  click-drag (desktop); long-press-and-drag anywhere on the row (touch);
  short tap still navigates. Hybrid devices get both; handle never shows
  without hover, so touch is unaffected.
- Files: new `lib/modules/root/sidebar/sidebar_reorderable_item.dart`
  (`SidebarReorderableItem implements NavigationBarItem`, non-selectable);
  `sidebar.dart` wraps library/pin rows with it (explicit ghost/secondary
  style + centerStart alignment for labelled rows, untouched rail path);
  `sidebar_provider.dart` gained pure `moveSidebarEntry`/`moveSidebarPin`
  (visible-indexed, hidden ids sink, out-of-range is a no-op copy);
  `sidebar_order_dialog.dart` refactored onto them, no behavior change.
- Two shadcn constraints discovered by failing tests, now pinned by them:
  (1) `NavigationSidebar` children must render **slivers** (each wrapped in
  `SliverPadding`), while `NavigationRail` takes boxes — the wrapper returns
  `SliverToBoxAdapter` only in a sidebar container; (2) a `NavigationButton`
  under a sidebar container renders a sliver itself, so nesting one inside
  the drag boxes fails protocol — the wrapper re-scopes the inherited
  `NavigationControlData` to a bar container for its subtree (all other
  fields copied through, so labels/spacing/padding compute identically).
  Do not "simplify" either branch without re-running the widget tests.
- Persistence reuses `setSidebarLibraryOrder`/`setPinnedPlaylistIds`; no
  schema change. Rail cap (8 + overflow) keeps dialog semantics: beyond-cap
  pins sink below visible ones on reorder.
- Tests: `test/sidebar_order_test.dart` +8 pure cases;
  `test/sidebar_reorderable_item_test.dart` (7 widget: hover handle, tap,
  handle-drag reports (dragged,target), cross-group reject, long-press data,
  sliver-in-sidebar, box-in-rail). Full `flutter analyze` clean. Local-only:
  `/test/` is gitignored in this fork.
- Not yet observed in a running build (needs rebuild + eyeball pass on
  hover/drag feel and drop-indicator styling).

## In-sidebar reorder follow-up: whole-row drag + directional drops (working tree, uncommitted)

- Dropped the hover drag-handle icons: the whole row now grabs on desktop
  (transparent overlay `Draggable`, grab/grabbing cursors as the only cue).
  Taps, tooltips and button hover visuals still work through the translucent
  overlay.
- Fixed "can't move a playlist to the bottom" with directional drops: each
  row's top half inserts before it, bottom half after it, with a live
  top/bottom insertion line — plus the slim trailing drop zone after each
  group as a second way down. New pure `resolveSidebarDrop` maps
  (dragged, target, after) to visible indexes with adjacent no-ops → null.
- Framework trap worth recording: `DragTargetDetails.offset` is NOT the
  pointer position — it is `_lastOffset = globalPosition - dragStartPoint`
  (the feedback's origin). The target recovers the pointer via a shared
  `_dragAnchor` recorded on press (down events are always freshly
  hit-tested; move/up reuse the down path via `_pendingHitTestResults`, so
  per-row move listeners can never track across rows). Related traps hit on
  the way: the state's composite context resolves past the row (use a
  `GlobalKey` on the `DragTarget`), and `tester.drag` is touch-kind — drive
  desktop drags with one shared mouse pointer (hover, press, move, release).
- Tests: directional widget cases (before/after/last-row-to-end), trailing
  zone, cross-group/already-last rejects; pure `resolveSidebarDrop` cases.

## "Dropdown opens the wrong song" — root cause and fix (2026-09-25, working tree)

The complaint was that clicking a dropdown entry played/opened a different song.
Two surfaces were involved; only one of them was actually broken.

- **The search panel looked exonerated by the first harness and was not.**
  `test/home_search_dropdown_nav_test.dart` drives the real `HomeSearchBar` over
  a real `RootStackRouter` (probe route registered under the *name*
  `TrackRoute`, args captured instead of rendering `TrackPage`). Every
  single-frame case passes — `openLibrarySuggestion` does bind each row to the
  track it renders — and that is exactly why `tester.tap` cannot see the bug:
  it delivers pointer-down and pointer-up inside one frame. See the next
  section for what the panel actually gets wrong.
  The `search-trace:` TEMP-TRACE probes left by the earlier dead-dropdown
  investigation are now removed from `home_search_bar.dart` and
  `home_search_suggestions.dart` (with the `_traceFuture` helper).
- **The defect was the sort/filter dropdown on a playlist or album page.**
  Rows render `PresentationState.presentationTracks`; the queue loads
  `TrackPresentationOptions.tracks`, i.e. the collection in its own order (which
  `appendCollectionTail` also assumes, via `all.sublist(alreadyLoaded.length)`).
  `PresentationListSection` passed the *display* row number to
  `useTrackTilePlayCallback`, which forwarded it as `initialIndex`, so once the
  list was reordered `AudioPlayerNotifier.load` clamped/started on whatever sat
  at that position in the collection: tap row 1 of a Z→A list, hear row 1 of the
  playlist. Fixed by resolving the tapped track inside the loaded list by id
  (`use_track_tile_play_callback.dart`), in both the local and the remote
  (`WebSocketLoadEventData`) branch, and by dropping the now-unused `index`
  parameter so no caller can pass a display position again.
  `test/track_tile_play_target_test.dart` (3 cases: reversed, filtered,
  unsorted) is red against the old code — it plays `alpha` instead of the tapped
  `charlie`/`bravo` — and green after.
- **Why it looked random:** `ServiceUtils.sortTracks` implements no comparator
  for `SortBy.newest` / `SortBy.oldest` (they return `0`), so picking those
  leaves the order to Dart's *unstable* `List.sort` — an arbitrary permutation
  on long playlists. The index fix makes playback correct whatever the order,
  but those two options still do not sort by date. Left alone deliberately:
  implementing them is a behavior change, not a bug fix.
- **Fragility found while writing the harness** (not fixed): the panel's
  `readLibrarySnapshot` uses `ref.read` on autoDispose providers, so it renders
  library songs only while something else keeps `metadataPluginSavedTracksProvider`
  alive; the test fake had to copy production's `ref.cacheFor()` for the rows to
  appear at all. Worth revisiting if "search finds nothing from my library" ever
  comes back.

## Search dropdown: a live-song click opened a saved song (2026-09-25, working tree)

"Still opening the wrong song for live song", then "instead of the live song it
opens an already existing one". That is a second, different panel defect and it
is real: the previous section's single-frame tests could not see it.

- **Cause.** `liveQuery` in `home_search_bar.dart` was gated on `focused.value`.
  On a desktop, pressing a panel row moves primary focus off the `TextField` at
  *pointer-down*, and down/up arrive in different frames. Focus loss nulls
  `liveQuery` → the live snapshot goes away → the "Songs" group is deleted while
  the press is in flight → the library rows slide up into the pressed element
  (Column children are unkeyed, same `_TrackRow`/`_SuggestionRow` type, so
  Flutter rebinds the element instead of removing it) → pointer-up fires the
  *library* row's callback. The user sees the live row they clicked open a song
  that already exists in their library. `panelPointerDown` already pinned the
  panel itself through the gesture; nothing pinned which rows exist.
- **Fix.** One derived boolean: `panelVisible = focused.value ||
  panelPointerDown.value`, used for `liveQuery` and `showPanel`. Rows can no
  longer disappear under an in-flight press.
- **Test:** `test/home_search_dropdown_nav_test.dart`
  ("a two-frame press on a live row still opens the live song") presses with
  `tester.startGesture`, unfocuses through the real `FocusManager`, then
  `gesture.up()`. Red before (opened `lib-2` when `live-2` was pressed), green
  after. With the gate restored but row keys removed it fails differently
  (`null` — the press is lost), which is how the two halves were told apart.
- **Tried and dropped:** `ValueKey`s on every panel row, plus a case where a
  live result vanishes mid-press. The case passes with and without the keys —
  Flutter replaces rather than rebinds elements whose slot type changes, and
  Flutter re-hit-tests at pointer-up — so it proved nothing and was removed.
  Do not re-add row keys on the strength of this bug; the gate is the fix.
- **General rule for this panel:** any state that decides *which rows exist*
  must key off `panelVisible`, never `focused`. A single-frame `tester.tap`
  cannot catch a violation; drive presses with `startGesture`/`up`.

## Search panel keyboard navigation (2026-09-25, working tree)

- The panel is navigable without a mouse: arrows move `activeIndex`, Enter
  activates it, Escape dismisses. Keys are handled by a non-focusable `Focus`
  ancestor of the field (`canRequestFocus: false, skipTraversal: true`) —
  `EditableText` leaves ArrowUp/ArrowDown/Escape alone on a single-line field,
  so they reach the ancestor. Enter is *not* seen there: the field consumes it
  and `onSubmitted` reads `activeIndex` from `rowsRef` instead.
- Mouse and keyboard activation converge on `activateSuggestion`. The panel
  takes one `onActivate` plus `seeAllTerm`/`activeIndex`; it no longer takes
  per-group callbacks, which is what let a row and its callback disagree before.
- `suggestionRowsInPaintOrder` (recents, live, library, footer) is the only
  definition of row numbering; the panel's `nextSelected()` counter must stay
  in step with it. Adding a group without updating both silently shifts every
  arrow-key target.
- `test/home_search_dropdown_nav_test.dart` drives keys with
  `tester.sendKeyEvent` and submits with `tester.testTextInput.receiveAction(
  TextInputAction.search)` — a physical Enter does not drive `onSubmitted` in a
  headless test, so asserting on `receiveAction` is the honest proxy.


## Search panel row affordances (2026-09-26, working tree)

- Each row owns two play targets that do *different* things. `_RowActions` draws
  an always-visible play button *in front of* the duration, wired to `onPlay`:
  it plays **and** opens the item's page. `_CoverArt` is wired to `onPlayOnly`:
  it plays and navigates nowhere, so the listener stays in Browse.
- The cover's badge is revealed on hover, which was previously banned here: the
  old `_HoverPlayOverlay` kept per-cover `_hovering` state that survived panel
  rebuilds, so every cover stayed lit after one hover. That failure needs a
  rebuild that swaps the artwork under a still-set flag, so `_CoverArtState`
  clears `_hovering` in `didUpdateWidget` whenever `imageUrl` changes. Keep that
  guard if this widget is ever refactored — a flag with no reset path is the
  bug, not the hover itself.
- One width for field and panel: `panelWidth` (`min(520, viewport - 24)`) caps
  both, so the dropdown reads as the field's shadow. The field needs the `Align`
  above its `ConstrainedBox` — `Expanded` hands down a *tight* width and
  `BoxConstraints.enforce` cannot loosen it, so a bare `ConstrainedBox` is a
  silent no-op there. `test/home_search_live_test.dart` ("field width") pins the
  pairing by measuring field and panel against each other.
- Panel chrome: `SurfaceCard(clipBehavior: Clip.antiAlias)` (rows used to paint
  square over the card's own rounded corners), a 6px gutter so durations and
  "Clear all" are off the border, and a 4px row inset with a rounded *tint* of
  accent for the keyboard cursor — the solid accent fill put white text on
  lavender and the highlighted row stopped being readable. Covers and plain
  icons share `_leadingSlot` (34), or groups that mix them start their titles
  in different columns.
- Subtitle names are routes. `_SubtitleLink` underlines and wires the artist
  and album halves of a song row, and the artist of an album row. Song and
  album credits carry `SpotubeSimpleArtistObject`, not the `SpotubeFullArtistObject`
  a search hit produces, so they cannot go through `openLibrarySuggestion`;
  `openCreditedArtist` is the second, narrower door to the same `ArtistRoute`.
  A credit lists several artists but a row has one target, so the first wins.
- The panel now takes `onPlay`, `onOpenAlbum` and `onOpenArtist`; all three are
  nullable and null means "render plain text / draw no button" (how the tests
  opt out). `onPlay` in `home_search_bar.dart` plays *and* opens: playback gets
  `rootNavigatorKey.currentContext!` because this bar's own context is about to
  be left behind by the route push.
- `test/home_search_suggestion_rows_test.dart` pumps the panel directly with
  recording callbacks — it pins which row each play target belongs to, that a
  cover's badge only exists while a `PointerEnterEvent` is inside it, and that a
  cover press hits `onPlayOnly` alone (no `onActivate`, no `onPlay`), plus
  subtitle routing — all without a router or a player. Navigation from row
  activation stays covered by `home_search_dropdown_nav_test.dart`.
- **Unverified by tooling:** synthetic pointer input does not reach Spotube in
  this session. `ydotool click 0xC001` moves the pointer and hovers, but no
  widget ever reacts — confirmed against the recent-search X, which cannot be a
  panel bug — and `ydotool mousemove` produces no observable hover on a cover or
  a sidebar row. `grim` does not capture the hardware cursor under Hyprland, so
  the pointer's position cannot even be read back from a screenshot. Keyboard
  injection works. Anything whose only trigger is a mouse press or a hover has
  to be checked by hand here; do not read "nothing happened" from a scripted
  pointer event as a bug, and do not trust a screenshot to say where the cursor
  is.
## Roadmap PR 1 — hygiene bundle (2026-09-26, committed)

Six independent fixes, one commit. Suite: **1032 green**, including the new
cases in the four test files below; analyze clean, `git diff --check` clean.

- **R-10** `download_manager_provider.dart`: `_downloadTrack` re-stated
  `downloading` after `_claimNextQueuedTask` already flipped it — a second
  identical DB write per task that could also revert a cancel arriving while
  the lease was pending. The call is deleted; the claim is now the sole
  `downloading` writer. Proven by `test/download_status_write_dedup_test.dart`
  (drift `QueryInterceptor` counting `runInsert`/`runUpdate` whose status
  argument is `'downloading'`). Caveat found while writing it: a completed
  write's argument list contains the whole enum-name list (`queued, downloading,
  …`) from the WHERE clause, so `args.contains('downloading')` false-positives;
  the status argument position must be checked.
- **R-19** `server.dart`: random-port rebind no longer trusts one `serve()`
  attempt. Deviation from plan: "re-derive port on rebuild" became
  **retained-port-first + up-to 4 random retries**, because Riverpod 2.x runs
  `ref.onDispose` before *every* rebuild — a rebuild cannot be told apart from
  a true fresh bind at that point, so a live-socket gate never fired. Old
  production continuity (rebind to the remembered port) is preserved; a port
  that cannot bind is abandoned instead of failing the provider.
  `test/server_port_rebind_test.dart` pins fixed port, random window
  5000–22499, rebuild keeps port, stale-occupied port is skipped, and the
  server answers.
- **R-07** release-log guards: three per-request `.i()` logs in
  `server/routes/playback.dart` (HEAD, GET, response-headers dump) wrapped in
  `if (kDebugMode)` — release level is `Level.info`, so they fired per request
  and interpolated at the call site. In `sourced_track.dart` the candidate
  dump's `StringBuffer` is now `kDebugMode ? StringBuffer() : null` with only a
  `.d()` consumer.
- **R-06** `connectivity_adapter.dart`: the 30 s reconnect-probe timer now
  skips `paused` **and** `hidden` (`probeSkipsState`, `@visibleForTesting`).
  `test/connectivity_probe_lifecycle_test.dart`.
- **R-20** `local_devices.dart`: `useFuture(useMemoized(() => audioPlayer.devices))`
  (+ `selectedDevice`) — the async-getter minted a new Future per build and
  `useFuture` re-subscribed on each. `test/device_future_memoization_test.dart`
  pins the hook shape with an in-test churn oracle (the real page reads the
  process-global `audioPlayer`, so it is not pumpable).
- **R-15d** deleted six zero-importer files (`gradients.dart`,
  `initializers.dart`, `button_variance.dart`, `use_breakpoint_value.dart`,
  `use_custom_status_bar_color.dart`, `use_brightness_value.dart`) and stripped
  the commented-out parameter blocks from `form/text_form_field.dart`.
## Roadmap PR 3 — mDNS discovery gate (R-05) (2026-09-26, committed)

`connectClientsProvider` never checked `enableConnect` (the broadcast side in
`bonsoir.dart` always did), so multicast browsing of `_spotube._tcp` ran the
entire session with Connect off. `build()` now watches the preference and
short-circuits **before constructing `BonsoirDiscovery`** — off means
`state.discovery == null`, services empty; toggling on rebuilds and starts a
fresh browser, toggling off stops the live one via the previous build's
`ref.onDispose` (Riverpod runs onDispose before every rebuild).
`ConnectClientsState.discovery` became nullable; only `resolveService` needed
a guard (no external `.discovery` consumers).

Behavior note for future agents: outbound control (discovering and driving
*another* Spotube) now requires `enableConnect` on this device too — the
preference is the feature's master switch in both directions.

Tests: `test/connect_clients_gate_test.dart` (3 cases) — seam is
`BonsoirPlatformInterface.instance` (fake platform counts create/initialize/
start/stop) plus `DeviceInfoPlatform.instance = DeviceInfoPlusLinuxPlugin()`
(reads real /etc files; the method-channel default fails the
`as LinuxDeviceInfo` cast in tests). Suite 1035 green, analyze clean.

## Roadmap PR 2 — dead native plugins (2026-09-26, committed)

`app_links`, `audio_service_mpris` and `flutter_sharing_intent` had no
importers left in `lib/` (deep linking has been a no-op since `d5ce9859`), so
they were dropped from `pubspec.yaml`; the lock lost only those three plus
`app_links_{linux,platform_interface,web}` and `gtk`. Registrants for
linux/macos/windows regenerated via `flutter pub get`. iOS/macOS `Podfile.lock`
still name the removed pods — they can only be refreshed on a macOS runner and
`pod install` rewrites them on the next macOS build. Do not "fix" them here.

## Roadmap PR 4 — disk growth (2026-09-26, committed)

- `.spotube_logs` had no cap (`reportError` appended forever). Now capped:
  past `AppLogger.logFileMaxBytes` (5 MB) the file is rewritten to its last
  1 MB, starting at the first whole line. The log viewer's 256 KiB tail read is
  unchanged.
- The streamed-music cache had **no eviction at all**. New
  `preferences.music_cache_limit_mb` (schema v23, default 0 → byte-identical
  old behavior). Eviction lives in `services/music_cache_policy.dart`
  (`enforceCacheQuota`, `sweepIncompleteMirrors`, `MusicCacheUsage`) and is
  driven from `UserPreferencesNotifier`, which owns the cache dir.
- Why an in-process LRU instead of mtime: `getMusicCacheDir()` doubles as a
  local-library folder, so touching a file on play would rewrite the "date
  added" the UI shows. `MusicCacheUsage.markServed` is called on both the HEAD
  and GET cache-hit paths in `server/routes/playback.dart`; because mpv HEADs
  before it GETs and pre-warms the queue head, the current and next tracks land
  at the hot end without an explicit "in use" registry.
- Startup `.part` sweep runs inside `_initDeferredServices` (post-first-frame)
  with a 10-minute window, so a second instance mid-mirror is left alone; the
  worst case even then is a lost cache write, since
  `PlaybackCacheMirror.finish` refuses a part whose length mismatches.
- Known constraint for future agents: **`test/` is gitignored in this fork**
  (`.gitignore:/test/`) — the suite is local-only and never appears in
  commits. And any new l10n key currently regenerates 32 files that carry the
  uncommitted search-redesign diff; PR 4's Settings row therefore uses English
  literals until that work lands.

## Second-pass optimization roadmap — PRs 1–7 (2026-09-26/27, uncommitted)

Item ids below belong to this pass only; they are unrelated to the older
"Roadmap PR N" sections above (those are committed).

- **PR 1 (S-01, S-02, S-03, D-06)** — correctness fixes in queue persistence,
  server routes and history writes (details in the diffs; all pinned by the
  existing suite).
- **PR 2 (D-01)** — `NativeDatabase.createInBackground` setup hook now sets
  `journal_mode=WAL`, `synchronous=NORMAL`, `cache_size=-16384`,
  `busy_timeout=5000`. Pinned by `test/drift/pragma_setup_test.dart`.
  Do not "restore" the plain `NativeDatabase(file)` constructor.
- **PR 3 (C-02, P-02)** — cache-quota and mirror-sweep `stat()` calls run in
  waves of 32 (`_statWaveSize`); the startup update-check timer reschedules
  (max 3 deferrals) while audio is playing instead of firing mid-playback.
- **PR 4 (PB-01/02/03/08/09)** — playback route no longer wraps the dio
  stream in `asBroadcastStream` (cancel now reaches the source); mirror
  honors `onPause/onResume`; mpv gets `cache-on-disk=no`, `vid=no`, `sid=no`;
  dead `logRequests` pipeline middleware removed.
  **PB-04 deferred with evidence**: media_kit has no public bulk-append;
  `Player.add` is `loadfile` per call under a lock whose ordering relies on
  sequential awaits — parallelizing would scramble queue order.
- **PR 5 (PB-06, F-09, S-04)** — a shuffle playlist event re-permutes
  `state.tracks` from the previous list via the `_lastSyncedMedias` uri map
  (`_permutedQueue`) instead of decoding every `Media`; endless-playback
  dedupe is set-based; `directorySize` stats in waves of 64.
  Pinned by the identity test in `test/queue_batch_test.dart`.
- **PR 6 (N-04, DL-06)** — per-track stable user-agent (16-entry map) instead
  of re-randomizing per request; download manager reuses the shared artwork
  memo. **PB-05 deferred**: dropping `currentIndex` from
  `isSameQueuePayload` is not client-safe — `connect.dart` assigns the whole
  payload to the queue provider, so the field is part of the wire contract.
- **PR 7** —
  - **D-04**: `history/top/playlists.dart` watch path is now the SQL
    aggregation `historyPlaylistGroups` (same shape as tracks, incl. the
    legacy-`external_urls` drop and JSON-id grouping); `fetch` keeps the
    legacy Dart grouping. Equivalence pinned by
    `test/history_playlist_grouping_test.dart` for all six durations;
    scaling: playlist write settle 3ms at 5k rows (`history_scaling_test`).
  - **D-03 investigated, no change**: `recent.dart`'s `ROW_NUMBER` window over
    `(playlist, album)` rows emits exactly one row per item in one scan; a
    `GROUP BY item_id + MAX(created_at)` join can emit duplicate rows on
    `created_at` ties, and no measurement showed the window query as a cost.
    Do not rewrite it without a before/after number.
  - **H-01**: `ScrobblerNotifier` gates its watch listener on a
    `username|passwordHash` credential diff — the on-subscribe replay no
    longer authenticates a second time nor re-emits state; `logout()` claims
    the slot so the delete event is a no-op. No test (needs the encrypted
    keystore mocked); behavior-preserving otherwise.
  - **D-05**: plugin root dir memoized (`_pluginRootDirPath`); per-plugin
    existence checks skipped for `slug@version` pairs validated this session
    (`_validatedPlugins`, evicted by `addPlugin`/`removePlugin`).

- **PR 8 (N-01, N-02b, N-03)** —
  - **N-01**: `ConnectionCheckerService` probes are single-flight (`_probing`
    coalesces concurrent `isConnected` calls; state write + stream emit live
    in `_probe`), and every ceiling is explicit: dio 5s timeouts,
    `InternetAddress.lookup(...).timeout(5s) -> []`. Pinned by
    `test/connectivity_probe_ceilings_test.dart` (5 concurrent probes cost 1
    set of HEADs).
  - **N-02b**: all artwork goes through one `ArtworkCacheManager` singleton
    (`lib/services/artwork_cache_manager.dart`) that reuses FCM's
    `'libCachedImageData'` key with `maxNrOfCacheObjects: 1500` (default is
    200, which evicted album covers while their playlists were on screen).
    Every call site names the manager — `DefaultCacheManager()` must never be
    constructed, or two managers fight over one DB.
  - **N-03**: plugin-index responses are cached in a static TTL map (60s) with
    conditional `if-none-match`/`if-modified-since` revalidation (per-request
    `validateStatus < 400` so 304 is visible). A 304 refreshes the TTL without
    re-parsing; 304 with no cached body is reported, never rendered. Pinned by
    `test/plugin_index_cache_test.dart`; partial-failure behavior still pinned
    by `test/plugin_index_partial_failure_test.dart` (its setUp clears the
    static cache).
- **PR 9 (DL-02, DL-03, DL-05)** —
  - **DL-02**: `chunkDownload` writes each range slice straight into a
    staging `<target>.part` at its final offset (one `RandomAccessFile` per
    connection with `setPosition`), then renames once. No part files, no
    concatenate pass: measured wchar for a 5 MiB transfer over a loopback
    Range server, 10,487,000 B vs 15,729,000 B for the old flow (~33% less
    write traffic, peak free-space need 2x -> 1x), output byte-exact against
    the old flow (`test/scratch/chunk_io_bench.dart`). Connections are
    size-adaptive (`totalLength >> 21`, ceiling 4), so <2 MiB files take the
    single-stream path instead of 4 tiny ranges. A misreported length is
    caught by a staged-size check before the rename; the target is only ever
    touched by that rename, so a failed attempt can't destroy it (invariant
    now pinned twice in `test/chunk_download_test.dart`).
  - **DL-03**: startup sweep `sweepStaleChunkStaging()` (music_cache_policy)
    removes legacy `<temp>/Spotube/.chunk_dl_*` directories; runs from
    `UserPreferencesNotifier.sweepStaleMusicCacheMirrors`, which `main.dart`
    already awaits before the UI is interactive.
  - **DL-05**: a completed download deletes the playback server's mirrored
    cache copy of the same track (`_evictMusicCacheCopies`, matched by the
    sanitized `name - artists` prefix + container extension, since the cache
    name embeds the source-plugin id) and forgets the paths in
    `MusicCacheUsage`. Failure is logged, never fatal to the download.

- **PR 10 (M-01)** — optimistic library toggles (favorite/unfavorite across
  the four saved-list notifiers) and page-walk completions now call
  `scheduleSnapshotPersist()`: a 2s trailing debounce so a burst costs one
  full-list snapshot write carrying the final state; a provider disposed
  inside the window cancels the pending write (disk keeps the previous
  last-known-good — never corrupt, at most one toggle stale). `fetchAll` and
  `_revalidate` keep their awaited `persistSnapshot` (single writes, pinned
  by existing timing assertions). Pinned by the `snapshot persist debounce`
  group in `test/library_snapshot_test.dart`. **M-02/M-03 stay gated** on
  DevTools attribution — no heap evidence, no speculative refactor.

- **PR 12 (B-02, L-01, LOG-02, S-05)** —
  - **B-02**: `discord_provider` connects through `_connectWithCappedRetry`:
    the library's `autoRetry` is an uncapped `Timer.periodic` every 5s, so
    Spotube now stops it via `disconnect()` after 12 failed retries (~1
    minute). Not unit-pinned: `FlutterDiscordRPC.instance` is a native
    singleton with no seam; reworking it for a test was judged not worth the
    indirection.
  - **L-01**: the two resolution logs in `sourced_track.dart` (`"${query.name}:
    ${sourcedTrack.url}"`) are `kDebugMode`-guarded — the `url` getter reads
    the preset provider and rescans the manifest, which release mode was
    paying per resolve for a line `Level.info` drops anyway.
  - **LOG-02**: interpolated `.d`/`.t` args converted to the logger's lazy
    closure form (`log.d(() => ...)`) at the music-cache trim/sweep lines,
    the playback-server trace and the yt-dlp kill notice. `main.dart`'s
    startup logs were left alone (user WIP).
  - **S-05**: `BlackListNotifier.add` awaits its insert (callers already
    awaited `add`; a rejected insert was an unobserved future); the tray
    constructor reports `initialize()` failures through `AppLogger` instead
    of dropping them.

- **PR 13 (A-01, A-02)** — cleanup sweep, no behavior change.
  - **A-01 dead code** (each re-verified reference-free against the current
    tree, including the user's search WIP, before deletion):
    `settings/playback/edit_instance_url_dialog.dart` removed whole;
    `ServiceUtils.getTitle`/`clearArtistsOfTitle`/`randomNumber`,
    `PrimitiveUtils.getRandomElement`, `percentCompletedStream` and
    `ImagePlaceholder.online` (the dicebear avatar URL) removed with their
    now-unused `dart:math` imports; `metadata.dart`'s `primitive_utils`
    import dropped. Commented-out blocks deleted from
    `home/sections/featured.dart` (placeholder kept — the section returns
    `SizedBox.shrink()` pending a metadata-plugin featured API),
    `pages/profile/profile.dart` and
    `pages/getting_started/sections/playback.dart`. Kept deliberately:
    `List.unique` (pinned by `test/list_unique_test.dart`) and the
    tool-owned `generated_plugin_registrant.dart`.
  - **A-02**: the five-line debounce + empty-fast-path preamble that was
    copy-pasted verbatim across `user_albums`, `user_artists`,
    `user_playlists` and `settings/blacklist` now lives in
    `hooks/utils/use_debounced_filter.dart` (record of
    `{value, onChange, query}`); identical 200 ms behavior.
    `local_folder.dart` keeps its own variant — it binds through a
    `TextEditingController` seam, not `useState`, and sits in the user's
    WIP set.
  - **Image-test regression found by the full-suite run**: PR 8 wired
    `ArtworkCacheManager.instance` into `UniversalImage.imageProvider`, so the
    http branch now builds that manager, whose `Config` calls
    `getTemporaryDirectory()` on construction — which widget tests without a
    path_provider mock cannot answer (`image_decode_size_test`,
    `universal_image_source_test`; neither image subset was run after PR 8).
    Fixed test-side by registering the suite's existing `FakePathProvider` in
    those two files' `setUpAll` — no production change (the static initializer
    is already lazy, and the tests genuinely exercise the branch).

**PR 11 (Android build items) was deferred** — no Android SDK/emulator in
this environment; it remains open in the backlog alongside B-01, C-03, DL-04,
P-01 and the DevTools-gated M-02/M-03.

Suite state at this milestone: full `fvm flutter test` green at PR 5
(1076 passed / 2 skipped); history + plugin subsets green after PR 7; download
+ cache subsets (73 tests) and `chunk_download_test` (8, incl. 3 new) green
after PR 9; `library_snapshot_test` (14) and the favorite-touching search
tests green after PR 10; blacklist/server/sourced-track/yt-dlp suites green
after PR 12; full suite green after PR 13 (1091 passed / 2 skipped),
`dart analyze` clean across `lib/`. All of it is
UNCOMMITTED and must not be rebased onto the user's ~85-file search-redesign
WIP without their say.

## Internet radio (feature, complete)

A standalone internet-radio surface. It deliberately does **not** reuse the
Track model or the global music player — do not "unify" them.

- **Model**: `lib/models/radio/radio_station.dart` (freezed `RadioStation`,
  `RadioTag`, `RadioCountry`). `favoriteKey` = `provider:id` (namespaces
  cross-provider id collisions); `subtitle` = up to 3 tags + country.
- **Directory layer (plugin-backed)**: `lib/services/radio/radio_directory_provider.dart`
  keeps the `RadioDirectoryProvider` interface + `fetchStationsAcrossProviders`
  fan-out + the `radioProviders` list, but the directories are no longer in-app.
  Each installed Hetu plugin that advertises the `radio` ability is adapted to a
  `RadioDirectoryProvider` by `lib/provider/radio/plugin_directory_adapter.dart`
  (`MetadataPluginRadioDirectoryProvider`), which delegates to the plugin VM's
  `MetadataPluginRadioEndpoint` (`lib/services/metadata/endpoints/radio.dart`,
  mirrors `audio_source.dart`). `radioProvidersFor()` in
  `lib/provider/radio/stations.dart` orders plugins default-first (like
  `source_resolver._orderedPlugins`) and `radioPluginDirectorySyncProvider`
  rebuilds the global `radioProviders` list whenever plugin state changes, then
  invalidates the stations/tags/countries providers. It is `ref.watch`ed once at
  app root (`main.dart`), NOT in `build()` — the notifiers never read plugin
  state themselves, so DB-less tests can inject a fake provider without a drift
  DB. The old in-app `radio_browser_provider.dart` + `registerRadioProviders()`
  are retired (radio-browser is now a bundled plugin).
- **Browse/search state**: `radioStationsProvider` is an
  `AutoDisposeFamilyAsyncNotifier` keyed by a record `({tag, country, search})`,
  with `fetchMore` paging + dedupe; `radioTagsProvider`/`radioCountriesProvider`
  for the rail. Chosen over the shared `PaginatedAsyncNotifier` because that
  couples `MetadataPluginMixin` (Spotify rate limits).
- **Playback**: `MediaKitRadioPlayerBackend` (`lib/services/audio_player/radio_audio_player.dart`)
  wraps a *dedicated lazily-created, eagerly-disposed* `CustomPlayer` (second
  mpv context, music queue untouched). `RadioPlaybackNotifier`
  (`lib/provider/radio/radio_playback.dart`) is a non-autoDispose `Notifier`
  (must outlive the screen); it hands audio focus to `MusicPlaybackDelegate`
  on play and reads back on stop. Live ICY title is captured by observing
  mpv's `media-title` via `nativePlayer.observeProperty` (once per player,
  unobserved on dispose) → `state.liveTitle`.
- **Persistence**: favorites in a new `RadioFavoritesTable` (additive Drift
  migration); recents reuse `HistoryTable` with `type=radio` (no new table),
  read via a dedup window-function query capped at 20.
- **UI**: `lib/pages/radio/radio.dart` `RadioScreen` — search bar + now-playing
  strip + Browse/Favorites/Recent tabs (library tabs are drift-backed, render
  offline, filter client-side) + tag/country rail + Radio Browser attribution.
  Reuses `PlaybuttonView` so grid↔list follows the `mdAndUp` breakpoint. Route
  `RadioRoute` + sidebar/navbar tiles added (all additive edits to the dirty
  `routes.dart`/`routes.gr.dart`/`side_bar_tiles.dart`/`main.dart`).

**Deferred**: l10n for the new UI strings is intentionally left as literal
English — regenerating `app_*.dart` would collide with the user's dirty
localization WIP. Add the keys in a dedicated l10n pass once that WIP lands.

**Do not reinvestigate**: the two-`CustomPlayer` split is the design, not a
bug; the empty-then-populated `titleStream` is expected (best-effort ICY).

**Radio as a Hetu plugin ability (PR-1..5, uncommitted)**: `radio` is now a
fourth `PluginAbilities` value with a per-role default (`selectedForRadio` →
`defaultRadioPluginConfig`, `setDefaultRadioPlugin`, `radioPluginProvider`), a
Drift `selected_for_radio` column (schema **24→25**, additive+guarded
`from24To25`), a Settings **Radio** tab (badge + "Set as default for Radio"; tab
bar scrolls horizontally under 640px). Two bundled Hetu plugins auto-install on
first seed: **Internet Radio Browser** (radio-browser.info, server-paginated)
and **Internet Radio SomaFM** (~46-channel single-JSON catalogue, client-side
paging/tags, empty countries) — radio-browser is seeded first so it wins the
default slot. Sources in `plugins/<name>/src/plugin.ht` + `plugin.json`; build
with `scripts/build-radio-plugin.sh [<name>…]` (pinned `hetu_script_dev_tools`
CLI snapshot via `fvm dart`, then `scripts/plugin_zip.dart`), committing the
compiled `assets/plugins/spotube-plugin-<slug>/plugin.smplug`.

**Hetu 0.4.2 authoring gotchas (proven here, do not rediscover)**: no `await`
(async = `Future` via `.then`); a plugin must alias `var HttpResponse =
std.HttpResponse;` at top level (namespace recursion bug); map/list literals
must end in `.toJson()` to cross as plain Dart; **`queryParameters:` passed to
`HttpClient.get_req` MUST be `.toJson()`** — a bare `{}` is an HTStruct and the
dio binding throws `HTStruct is not a subtype of Map<String,dynamic>?` at the
endpoint's `as Map` cast; no `forEach` and no `toSet` on a List — `fold` (with a
module-level accumulator `fun`, since lambda block-bodies are ambiguous) +
`expand`/`keys`/`sort` cover group-and-count; `loadBytecodePureDart` reads std
bytecode from pub-cache for a Flutter-free VM.

Test surface (all green, UNCOMMITTED): `radio_station_test`,
`radio_registry_test`, `radio_stations_provider_test` (incl. `radioProvidersFor`
default-first ordering + ability filtering), `radio_plugin_directory_adapter_test`
(real std-only Hetu VM → production endpoint → adapter, incl. provider injection
and empty-`byId`→null), `radio_persistence_test`, `radio_playback_test` (incl.
live-title), `radio_ui_test` (mobile list / desktop grid / play / favorites
tab), and `test/drift/app_db/migration_test.dart` (v24→v25 adds
`selected_for_radio`). Each compiled plugin is additionally round-tripped live
against its upstream through the production endpoint by a throwaway probe under
the gitignored `test/scratch/` (deleted after use) before the `.smplug` is
committed. Release `flutter build linux` compiles end-to-end.


## Shell-owned glass: matching the terminal, live (2026-09-30, uncommitted)

Question: the Caelestia plugin tracked the desktop *palette* live but its
*glass* (veil alpha/color, frost, panel opacity) was hard-coded in the `.ht`,
so it described nobody's desktop. Measured target from the user's own config:
`foot.ini [colors-dark] alpha=0.78, blur=yes`, `shell.json
appearance.transparency {enabled:true}` (base defaults to 0.85), scheme
`surface` as the veil color.

Decision: derive it. `CaelestiaShellSource.getGlass()` reads those two files
plus the live scheme surface and emits
`{opacity: 1.0, blur: 16, overlay: #AA<surface>}` + `surfaces.opacity`.
`kShellBlurSigma = 16` is a named constant — Hyprland's `size 8, passes 2` is
a multi-pass box approximation with no invertible sigma, so parsing
`variables.lua` would buy false fidelity.

Source-of-truth split that makes this tractable: colors move live
(`caelestia` writes OSC into every `/dev/pts/N`), but the *treatment* is
static user config — caelestia has no foot target at all and `foot.ini` is
hand-authored. So treatment is read from disk and re-read when those files
change; palette keeps its existing path.

### Verified (do not reinvestigate)

Ground truth came from the app's own persisted
`flutter.spotube.theme_definition_cache.v2` in `shared_preferences.json`, not
from screenshots:

- Baseline: `{"source":"shell","opacity":1.0,"blur":16.0,
  "overlay":"#c7130c0e"}` — `0xc7`/255 = **0.780**, exactly `foot.ini`'s
  declared alpha; RGB `130c0e` = the live scheme `surface`.
- `foot.ini alpha` → `0.02`, **no restart** → `overlay "#05130c0e"`
  (`0x05`/255 = 0.0196). Restored → back to `#c7…`. Live watch works.
- `shell.json transparency.enabled` → `false`, no restart →
  `surfaces.opacity` 0.85 → **1.0**, veil unchanged (correct: foot's alpha
  governs the backdrop, panel transparency governs cards). Restored → 0.85.
- The inotify matcher is correct for atomic saves: a Dart probe on
  `~/.config/foot` showed `move path=sedXXXX dest=foot.ini matched=true` and
  `modify path=foot.ini matched=true`.
- Both configs restored byte-exactly and sha256-verified.

### Retracted method — then corrected, do not repeat the first version

Fitting `observed = α·surface + (1−α)·blur(wallpaper)` over "dark flat tiles"
of a Spotube screenshot returned α ≈ 0.80 and rejected a white veil
(RMSE 7 vs 79/255). **That number was worthless**: the sampled tiles were
opaque UI painted from palette roles, which the veil never touches. Proof — an
α 0.78 → 0.02 change moved 5 of 1591 tiles in the window, and those were
content, not backdrop.

The cause was the finding below, not the method. With the scaffold made
transparent the same fit recovers **α = 0.752 at σ=16** (0.73–0.78 across the
whole σ grid, never pinned at a boundary) against `foot.ini`'s declared 0.78.
RMSE ~12/255 rather than the ~2 hoped for: the model omits Hyprland's own blur
of the window and caelestia-shell's dimming of the wallpaper it draws. Causal
check: `foot.ini alpha` 0.78 → 0.02 with no restart changed **63.8% of screen
pixels** (mean delta 72/255).

### The layer was computed and never seen (fixed same session)

`ThemeBackgroundScope` set `ScaffoldTheme(backgroundColor:
colorScheme.background)` — an opaque `#130c0e` — on a `ComponentTheme` wrapping
the `Stack` that holds `ThemeBackgroundLayer`. Every descendant scaffold
therefore painted solid over the backdrop, so on browse/library/settings the
glass had literally no effect. Its own doc comment claimed the layer "stays
behind for transparent screens (player, lyrics)", but nothing in `lib/` ever
constructed a transparent `ScaffoldTheme` — this was the only construction site
— so that sentence described an intention that was never wired up.

Fix: `const ScaffoldTheme(backgroundColor: Colors.transparent)`. Sound because
the derived layer draws the wallpaper at `opacity: 1.0` full-strength and is
itself opaque, so nothing leaks through to the window behind it.

### Still open

- `test/vpn_download_test.dart` is a pre-existing flake, in more than one of its
  cases: `vpn loss mid-download pauses the retry until recovery` fails roughly
  one run in three **in isolation** (`Expected: <0>, Actual: <1>` on the retry
  count), and `vpn required + already active: shared, never disconnected` fails
  when the file runs as a group but passes under
  `--plain-name "vpn required + already active"`. Both are timing/ordering
  sensitive because the code under test reads real system state (the run logs
  `Vpn pin: tun0 (127.0.0.1)` and `no VPN interface name detected` on this
  machine). It is also the only thing that makes a full `flutter test` report
  `-1`. Nothing in the theme/shell path touches it; do not blame it on glass
  work.
- In light mode `ThemeConverter.adaptOverlayForBrightness`
  (`theme_converter.dart:66-70`) replaces the veil color with white, keeping
  only the alpha — so the surface-derived hue is dark-mode only. Observed
  live: the desktop flipped to a light scheme mid-verification and the overlay
  resolved to `#c7f7f9fd`.
- Hard-coded frosts elsewhere (`mini_lyrics.dart:224`,
  `connect/control.dart:344`, `player_actions.dart:108`, `player.dart:93`,
  `pages/track/track.dart:107`) still ignore the theme's glass.

### Third opaque paint: sidebar group headings (fixed same session)

shadcn's `_NavigationLabelDelegate.build` (`navigation_bar.dart:2124-2141`,
package `shadcn_flutter-0.0.47`) paints `theme.colorScheme.background` through a
`CustomPaint` behind every pinned `NavigationLabel`. In the sidebar that put a
solid `#130c0e` band across the backdrop at "Library" and "Pinned playlists".
Fixed in `modules/root/sidebar/sidebar.dart` by wrapping `NavigationSidebar` in
a `Theme` whose `colorScheme.background` is transparent — subtree-scoped, since
the package reads it off the ambient theme and the dependency is pinned.

Causal confirmation: an `alpha` 0.78 → 0.02 change now moves the heading rows
exactly like the gaps beside them (mean delta 38–45/255, ~60% of pixels
responding); before, headings were inert.

### One gate for all of it: `themeBackdropActiveProvider`

The sidebar override above was initially unconditional, which bent the theme for
users who never install a plugin backdrop. All three consumers now read
`themeBackdropActiveProvider` (`modules/theme_background/theme_background_image_provider.dart`),
which is `themeBackdropUrlProvider != null` — the same test the image provider
already made (shell-sourced, wallpaper path resolvable), factored out so it is
size-independent. `themeBackgroundImageProvider` is now that URL plus the
quantized decode size, and `ThemeBackgroundScope` watches the predicate instead
of recomputing it from a sized key.

Narrowed to `source == shell` the same session, at the user's insistence that
the transparency belong to the Caelestia plugin alone. It had also been firing
for `albumArt` themes, which resolved the active track's artwork as a backdrop —
a path that never actually showed, because the opaque scaffold ground that
covered it was the original bug. So album-art themes keep the appearance they
shipped with, and no longer pay a full-screen decode for nothing. The gate is
Caelestia-only by construction, not by name: `"source": "shell"` in the plugin
protocol is served solely by `themeShellSourceProvider` (one implementation,
`CaelestiaShellSource`), so a shell-sourced theme on a desktop without Caelestia
state resolves no path and stays opaque. `test/backdrop_decode_test.dart` pins
all four combinations.

The decision belongs to the plugin, not to a Spotube preference. `'background':
{'source': 'none'}` plus `'dynamic': {'source': 'shell'}` in a theme's
`getTheme()` gives the desktop's live colors on a plain opaque ground, and
`mergeShellPalette` now withholds *both* halves of the derived glass from
anything but a shell-sourced backdrop — including `surfaces.opacity`, which
used to apply regardless and left cards translucent over a ground with nothing
behind them. So "Caelestia glass" and "Caelestia colors, plain" are two `.ht`
files with no schema change and no settings row. The plain variant ships as
`../spotube-theme/caelestia-plain-1.0.0.smplug`;
`test/caelestia_plain_theme_test.dart` evaluates its real Hetu bytecode through
the production endpoint and the production merge.

### Fourth opaque paint: the title bar (fixed same session)

Album and settings pages still read as "black at the top" after the three fixes
above. The inert band was shadcn's `AppBar` (`scaffold.dart:736-746`), which
fills itself with `colorScheme.card.scaleAlpha(surfaceOpacity)` inside a
`ClipRect` + `BackdropFilter`. Measured against the ground beside it: veil
0.78 → 0.02 moved the strip by **3/255** while the sidebar moved by 61 and the
page body by 48.

Wearing the backdrop's own veil was tried first and is wrong. The ground behind
the bar is already veiled, so a second veil at the same alpha composites to
`0.95·surface + 0.05·wallpaper` — the color matched its neighbour at rest
(0.7/255 apart, which is why it looked fixed) but the strip was still inert:
delta 3.16/255. Only `alpha = 0` composites to the ground exactly.

Fix: `TitleBar` passes `backgroundColor: Colors.transparent` when the backdrop
is active and keeps the frost. shadcn lays `headers` in a flex column, not over
the body, so on the non-floating pages nothing ever scrolls under the bar and
the fill was pure loss; the four `floatingHeader: true` pages (artist, track,
lyrics, getting-started) keep a blur-only bar.

Causal confirmation after: title-bar delta **32–35/255** against 34–47 for the
sidebar and page body in the same frame — the band now behaves like the glass
around it.

### No-guesswork audit 2026-10-05 (working tree; Linux desktop priority)
- Status: Implemented + tested (6 fixes, 3 measured no-change decisions).
- **P1 fixes (all `flutter analyze` clean, targeted suites green):**
  - `_getSourcedTrack` local-track guard (`provider/server/routes/playback.dart:459-472`):
    unguarded `track as SpotubeFullTrackObject` turned any local track in the
    queue into a 500. Now `is!` returns null so the caller serves the file.
  - Queue-restore corruption guard (`models/database/tables/audio_player_state.dart:20-42`):
    `jsonDecode as List` threw on a corrupt row and broke startup restore; now
    quarantines to `[]`, skips single bad entries. Verified by
    `queue_persistence_test.dart` (4 cases green).
  - NewPipe null-`mediaFormat` skip (`services/youtube_engine/newpipe_engine.dart:26-70,127-136`):
    `mediaFormat!` crashed the whole manifest on one malformed row; parsers now
    nullable + `whereType` filter. Precedent: `parseSearchResult` null-row skip.
  - Download resolve budgets (`provider/download_manager_provider.dart:842-853`):
    `resolve`/`resolveMatch` now `.timeout(sourceCandidateBudget)` (20 s, same as
    playback cascade); chunk download itself stays unbounded. Timeout falls into
    the existing per-candidate catch → next candidate, never hangs the worker.
  - Download preset index guard (two sites, `:358-370` + `:710-721`): `presets[]`
    threw RangeError on empty/stale list (initial state is `[]`, index defaults 0;
    `quality_presets.dart:44` already uses `elementAtOrNull` precedent). Now
    explicit `StateError` with index/available counts.
  - Glance Dio timeouts (`provider/glance/glance.dart:18-24`): bare `Dio()` →
    5 s connect/receive/send, matching the probe client shape.
  - Cert-allowlist subdomain fix (`collections/http-override.dart:13-24`):
    `endsWith(spotify.com)` matched `evilspotify.com`; now exact-or-dot-suffix
    with lowercase normalization. Same rule covers the VPN manual TLS leg.
  - HEAD-probe observability (`provider/server/routes/playback.dart:548-552`):
    intentional fall-through now `PerfCounters.note('playback.headProbeFailure')`
    (debug-only, no behavior change).
- **Measured no-change (do not reinvestigate without new evidence):**
  - `source_match` index: 933 real rows, 100 lookups in 3.5 ms (0.04 ms each)
    via read-only query on the live DB — confirms prior 0.4 ms @20k finding.
    No migration.
  - `sourced_track.dart:307-308` cached `jsonDecode`: SAFE — `classifyCachedSourceMatch`
    (`sourced_track.dart:131-158`) already trial-decodes + `fromJson` before a `hit`
    decision, so the hit path cannot see unvalidated JSON. Earlier flag was a
    false positive; verified by reading, not assumed.
  - `getMusicCacheDir` per-request: already memoized (`user_preferences_provider.dart:163-176`
    `_musicCacheRootDir` cached future; Android-only `exists()` recheck is intentional
    as the OS can drop the dir). No change.
  - `test: any` (`pubspec.yaml:196`, resolves to 1.2.2): left floating — dev-only
    runner, pinning risks a resolve conflict with `flutter_test`; no harm evidenced.
- **P4 deferred with reason (201 dirty files; refactor risk > proof):**
  Layering inversions (`utils/service_utils.dart:9`, `provider/metadata_plugin_provider.dart:14`,
  `hooks/use_check_yt_dlp_installed.dart:7`, `collections/intents.dart:8-9`),
  `syncedLyricsProvider` non-autoDispose family, `PluginVmCache` no-dispose
  (hetu 0.4.2 has no dispose API — GC-only, matches TODO OPEN). Documented, not moved.
- **Verified:** `flutter analyze` clean on all touched files; 39 targeted tests
  (`playback_proxy`, `queue_persistence`, `manifest_cache`, `engine_call_budget`,
  `newpipe_tiering`) + 52 (`download_cancel`, `download_first_playback`,
  `playback_fallback_memo`, `source_engine_fallback`, `queue_membership`) green.
  Full suite not re-run (1000+ tests; targeted coverage of every touched path).

### Android every-start launch audit 2026-10-05 (working tree)
- Symptom: slow launch on **every** start (refined from "sometimes": cold start).
- Environment limit, stated not assumed: this host has **no adb, no emulator,
  no device** (`which adb/emulator` empty), so no on-device timing exists and
  none is claimed. Fixes below are structural (work removed from the
  every-start path by construction) + one instrumentation enabler.
- **Ruled out by reading (not assumed):** the untracked WIP search files
  (`modules/home/home_search_{bar,results,suggestions}.dart`) — their
  `readLibrarySnapshot(ref)` (`home_search_suggestions.dart:915-927`) is a
  synchronous `ref.read(...).asData?.value` with no I/O; untouched per R-03.
  `localTracksProvider` is only watched by the local-tracks pages + permission
  flow, not at startup. Battery-optimization prompt is once-only
  (`use_disable_battery_optimizations.dart:9`). `getMusicCacheDir` already
  memoized. `splashReady` gate already opens on the prefs-only cached theme.
- **Fix 1 — NewPipe init lazy, eager call removed:**
  `NewPipe.init(DownloaderImpl.init(OkHttpClient()))` ran as the first
  deferred step on **every** start (`main.dart`, old `:150-154`) whether or
  not any NewPipe call followed. Now single-flight lazy in
  `NewPipeEngine._ensureInitialized` (`newpipe_engine.dart`): first actual
  `searchVideos`/`getStreamManifest`/`getVideo` pays it, concurrent first
  calls share one init, a failed init is forgotten so the next call retries
  instead of failing forever on a cached error. Init seam (`NewPipeInit`)
  mirrors the existing `NewPipeSearch` seam (real channel unavailable in
  unit tests). Only `newpipe_engine.dart` + `main.dart` referenced the
  extractor (grep-verified), so no other caller depended on eager init.
  Pinned by `test/newpipe_lazy_init_test.dart` (3 cases: no init before
  first use, one init for 3 concurrent calls, failed init retries) +
  `newpipe_search_tiering_test.dart` updated to the no-op init seam (8 sites).
- **Fix 2 — release-visible startup timing:** `_startupLog`/`guardedStartupInit`
  were compiled out of release (`main.dart`, `kReleaseMode` early-returns),
  and release `log.i` never reaches the file (only `reportError` writes,
  `logger.dart:152-183`) — so a slow launch on a user device left zero trace.
  New `AppLogger.logStartupLine` (`logger.dart`): `log.i` in all modes + one
  appended line to the log file in release (fire-and-forget, error-swallowed,
  ~15 short lines/start against the 5 MB rotation). Next step for the
  reporter: launch twice, Settings > Logs, share the `[startup]` lines —
  then the real bottleneck gets a number before any further fix.
- **Verified:** `flutter analyze` clean on touched files; 16
  (lazy-init + tiering) + 45 (engine budget, fallbacks, manifest, log
  rotation, proxy) green. Full suite not re-run.

### Follow-up 2026-10-05 — `logFile` poisoned-cache fix (working tree)
- Cause found while tracing the stuck report: `logStartupLine('main')` runs
  **before** `WidgetsFlutterBinding.ensureInitialized()`, so path_provider
  throws; the old `_logFile ??= getLogsPath()` cached that dead future and
  every later startup line plus `reportError` file writes failed on it until
  something reset the cache — the new release timing was dead on arrival.
- Fix (`services/logger/logger.dart`): the getter forgets failed resolutions
  (`identical` check) instead of caching them; successes stay cached.
  Proven red: `test/log_file_cache_test.dart` (fail-once path provider →
  first call throws, retry resolves, third call identical) fails on the old
  getter, passes on the new. `analyze` clean; 20 tests green with the
  rotation + newpipe suites.

### Mobile search-tab UI 2026-10-05 (working tree)

- Bottom bar (mobile-only) is `home → search → radio → library → stats`
  again (`collections/side_bar_tiles.dart`): the search tile + `SearchRoute`
  return. New `lib/pages/search/search.dart` reuses the redesign components
  (`HomeSearchBar` + `HomeSearchResults`, shared `searchTermStateProvider`)
  instead of restoring the deleted chips page, so mobile/desktop search
  cannot diverge. (No entry autofocus: focusing would pop the keyboard over
  the landing on every visit, and the open suggestion panel's fullscreen
  barrier would eat the first tap on the scope switcher — caught by test,
  fixed in production.)
- Route: `AutoRoute(path: "search")` inside the shell children (inherits the
  no-overlap transition); `routes.gr.dart` regenerated via build_runner
  (churn is import renumbering + the new route; Radio entries were already
  stale in the generated file).
- Home (`pages/home/home.dart:69`) and Radio (`pages/radio/radio.dart:~138`)
  hide their whole search rows wherever the bottom bar is visible, through
  shared `isBottomNavVisible` (exact inverse of the bar's own gate), so the
  two can never disagree. Desktop unchanged. Mobile Home always shows
  browse (a term set on the Search page no longer swaps Home inline, since
  the field to clear it lives on the Search page). Mobile station
  text-filter moved to the Search page's radio scope (see next entry).
- No edits to untracked WIP files (`home_search_bar.dart` etc.).
- Verified: `flutter analyze lib` shows one warning,
  `vpn_manager_impl.dart:204` `releasedFirst && false` — pre-existing in
  earlier uncommitted VPN work, behavior-affecting if "fixed", left alone.
  Tests: `test/mobile_nav_search_test.dart` (3: order, route, gate matrix)
  + 46 surrounding (home search, sidebar order, tab scaffold, radio UI) green.
  Manual check still pending: mobile-width hiding, 5-button fit, Search focus.

### Unified Search page (music + radio scopes) 2026-10-05 (working tree)
- Bottom-bar Search tab leads to a new `lib/pages/search/search.dart`: a
  Music|Radio segmented switch (`_ScopeChip`, same secondary/outline idiom
  as radio's `_Chip`) over scope bodies. Music reuses `HomeSearchBar` +
  `HomeSearchResults`; radio mounts `_SearchRadioScope`, which calls the
  shared `useStationSearchSlivers` hook — so the radio scope can never
  diverge from the Radio page. Scopes mount only when active (no wasted
  directory requests); the music term survives switches via the shared
  provider, the radio field resets (documented tradeoff).
- Blank music landing (`lib/pages/search/search_landing.dart`): recent
  searches as tappable chips (tap submits, clear-all included) above
  `HomeRecentlyPlayedSection` + `HomeNewReleasesSection`; blank radio
  landing reuses favorites/history rails (local Drift watches). All
  self-shrink on empty. No genre content: no data source exists
  (`featured.dart` is a deliberate placeholder).
- Extraction, not duplication: `lib/pages/radio/station_search.dart` holds
  `useStationSearchSlivers` (custom hook — a widget can't return slivers,
  and manual `.build()` calls misattribute hooks) + moved-verbatim
  `_BrowseRail`/`_Chip`/bones/attribution (now public
  `RadioAttributionSliver`); `RadioScreen` is ~70 lines delegating to it.
  While typing, browse rails step aside and only the results grid shows
  (same rule as music search replacing Browse) — a deliberate, documented
  behavior change vs rails-always; the grid header reads 'Results' vs
  'All stations' accordingly.
- Deliberately no autofocus on Search entry: focusing would pop the
  keyboard over the landing on every visit, and the open suggestion
  panel's fullscreen barrier would eat the first tap on the scope chips
  (caught by the new widget test, fixed in production not just the test).
- Searching polish: tracks/albums/playlists tabs gained the shared
  `NotFound` empty state on `hasValue && isEmpty` (artists already had its
  own); `SearchPlaceholder`'s empty-term branch stays unreachable by
  construction (hosts gate tabs on non-blank) — left alone, noted.
- Verified: `analyze lib` clean except the known pre-existing
  `vpn_manager_impl.dart:204` warning. Tests: `search_page_test.dart`
  (unified page: seeded recents, scope switch, radio search, back —
  hermetic via fake directory/player/prefs/DB), `mobile_nav_search_test`,
  plus 53 across radio/search/sidebar/chips suites green. Test-side
  findings: providers backing shimmer cards must be pre-resolved before
  the first frame (loading flash renders FakeData cards that touch the
  native player), and drift needs unmount + clock advance around container
  disposal — both follow existing repo precedents.
- Manual check still pending: phone-width landing/scopes, 5-button bar fit,
  desktop unchanged.

### Real window transparency, plugin-driven (working tree, uncommitted)
- Goal: compositor-level transparency on Linux (Hyprland/Caelestia) instead
  of the painted-wallpaper fake. Decisions: full window, manual setting,
  window_manager upgrade allowed, `background.transparent` tri-state,
  setting AND plugin, absent defers to setting.
- **Phase 0 — window_manager 0.4.3 → 0.5.2** (`pubspec.yaml:125`): resolves
  clean, `analyze` clean on all consumers. Linux background-color fixes
  (#249, #250) are in this range.
- **Phase 1 — native alpha** (`linux/my_application.cc`): RGBA visual +
  app-paintable before realization, skipped when not composited. Zero
  visual change alone (Flutter still paints opaque); compiled via
  `flutter build linux --release` green.
- **Contract — `ThemeBackground.transparent`, NULLABLE tri-state**
  (`models/metadata/theme.dart:162-181`): true = wants transparency (still
  needs the setting), false = veto (always opaque), absent/null = no
  opinion (setting decides — what every old theme decodes to). Lenient
  decode (`_transparentFromJson`: non-bool → null) so one bad flag never
  nukes a theme. Sanitizer passes it through explicitly (bools can't
  poison layout). No cache bump: old payloads lack the key → null → defer,
  identical semantics.
- **Build-system trap found the hard way:** `theme.dart` is `part of
  metadata.dart`, and editing ONLY the part did not invalidate
  json_serializable's cache — `.freezed.dart` regenerated WITH the field
  while `.g.dart` regenerated WITHOUT it (split-brain generated code that
  compiles and silently drops the flag). A content change to the library
  file itself forced a correct regen. Any future part-file model edit must
  verify the `.g.dart` actually contains the field; `analyze` cannot catch
  this (both files compile).
- **Master setting:** `preferences_table.transparent_window` (default
  false), schema 26→27 guarded step + `make migrate` snapshots, setter,
  Linux-only row in Settings → Appearance (literal English, avoiding the
  dirty l10n regen — PR4 precedent).
- **Predicate** (`modules/theme_background/real_transparency.dart`):
  Linux && setting && (definition null/absent → true; false → false);
  loading → false (no transparent flash a veto would retract).
- **Paint gating** (all default-off, predicate-keyed): backdrop layer off,
  scaffold ground transparent (scope), sidebar label band + rail, titlebar
  fill + in-app blur off, bottom nav AppBar fill + blur + opacity off
  (inner AppBar fills `card` at opacity — blur alone can't clear it),
  palette Material grounds via constructor param, root scaffold ground,
  player `SurfaceCard` (`filled`+`fillColor` together — fillColor alone is
  inert), track-page image skipped + blur sigma 0. Content surfaces
  (cards, dialogs, menus, lyrics frost) keep fills: transparency = absence
  of paint, and content legibility over a live desktop is the compositor
  blur's job.
- **Frame-clock lesson:** `PaletteTransitionScope` MUST stay provider-free —
  a `Consumer` form watching the predicate shifted rebuild timing and broke
  10/19 `theme_transition_test` cases (proven by stash A/B: 19/19 without,
  9/19 with). The single watch lives in `Spotube.build`, threaded down as
  a `realTransparent` constructor param (default false). Same reason the
  scope documents the constraint on the param itself.
- **Verified:** `analyze lib` clean except pre-existing
  `vpn_manager_impl.dart:204`; 353 migration pairs incl. →27 green;
  `real_transparency_test.dart` (7: decode ×4, sanitizer, setting-decides,
  veto) green — with a harness note: dispose a container holding the real
  theme chain races riverpod teardown, so predicate tests override the
  chain and settle the future before dispose; 19 transition + 34
  tokens/backdrop/wallpaper green; Linux release builds.
- **Author docs** (`background.transparent` tri-state + `.ht` example)
  belong in the sibling theme checkout, not this repo (no theme-plugin
  docs exist under `docs/`).
- **Live verification still pending (user machine):** theme with
  `transparent = true` + setting on → desktop shows through (needs
  Hyprland blur/rounding rules for the Spotube window — app can't shape
  Wayland windows); setting off → today's look; explicit `false` + on →
  opaque (veto proof); old theme + on → transparent (defer proof).
  Two-wallpaper screenshot check.
- **Plugin side — Caelestia glassier 1.2.0** (`../spotube-theme`,
  the installed Shell Theme): `background` gained `'transparent': true`
  (with a comment stating the tri-state), manifest bumped 1.1.0 → 1.2.0
  (fresh version = fresh resolution everywhere, no reliance on
  re-extraction heuristics), rebuilt via `compile_plugin.dart` +
  `scripts/plugin_zip.dart` → `caelestia-glassier-1.2.0.smplug`
  (`plugin.json` + `plugin.out`, verified entry names).
- **Merge carry fix** (`theme_shell_source.dart:104`): shell glass replaced
  the whole background block, which would have silently degraded an
  explicit `false` veto (or a grant) to defer. The merge now carries the
  plugin's `transparent` through `copyWith`; absent stays absent.
- **Pinned** by `test/caelestia_transparent_theme_test.dart` (manifest
  names + 1.2.0, endpoint `transparent == true`, merge grant/veto/absent,
  sanitizer pass-through) + plain-theme regression green (7 total).
- Note for the user: under real transparency the theme's painted veil
  (`overlay`, `opacity`, `blur`) is skipped by the app — tune glass via
  the compositor from here. Install step is manual: re-upload the 1.2.0
  `.smplug` in Settings → Plugins, set default theme, flip the setting.


## 2026-10-22 — the theme plugin repo got a toolchain (theme side first)

- The theme plugins now live in a repository of their own with a build of
  their own: `../spotube-theme` (published as
  `Adamyabhatt01/Caelestia-theme-plugin-spotube`). `tools/build.dart`
  compiles a theme, boots the bytecode the way the app does, calls
  `getTheme()`, validates the payload and packages it. The old flow needed
  the app's package config and a hand-run zip.
- The payload contract is written down for the first time:
  `schemas/theme.v2.schema.json` (frozen — exactly the fields this app
  reads) and `schemas/theme.v3.schema.json` (the draft). The validator
  mirrors this app's rules one-for-one: the 17 required roles per scheme,
  the ranges the sanitizer clamps, the enums it falls back on, the lenient
  tri-state `transparent` flag. One bad colour still costs the whole theme
  here — but it now fails the *build*.
- v3 is drafted on the theme side first: typography, spacing, motion,
  scale, icon sizes, component styles, the shell's composition, a branding
  block and a declarative UI tree (slots, screens, bindings, actions).
  `themes/brand-demo` ships the whole payload; on this app it draws as a
  palette, because unknown fields are ignored — the compatibility rule the
  host work will be built against. The v3 rules (node types, binding and
  action allowlists, asset paths, id allowlists, depth and size limits) are
  validated in the theme repo too.
- `sdk/palette.ht` derives both schemes from one seed colour, `sdk/defaults.ht`
  holds the neutral palette and a merge. `themes/minimal` is the SDK in nine
  lines.
- App-side changes: none to the theme model, the sanitizer, the endpoint or
  the cache. The theme tests' artifact paths moved with the artifacts
  (`../spotube-theme/dist/…`, `../spotube-theme/dist/legacy/…`), and two
  themes were unified with their published twins, so the pinned versions
  moved with them.
- The published install URLs still resolve to the same paths
  (`caelestia/plugin.smplug`, `caelestia-glassier/plugin.smplug`, plus
  `caelestia-plain`, `caelestia-shell` and `spotify-shell`).

## 2026-10-22 — the theme contract is complete (theme side)

- The v3 payload now covers everything a theme may decide: the extra colour
  roles (popover, sidebar, status, charts), typography, spacing, motion,
  scale, icon sizes and overrides, per-component styles for every shadcn
  component the app draws with, the shell's composition, branding, assets,
  and a declarative UI tree (slots, screens, templates, bindings, actions).
- The registries are closed and shared: nav/navbar/library ids, home and
  settings sections, the slot names, the node types, the bindings, the
  actions, the colour roles. A theme that names something the host does not
  have is rejected by the theme repo's validator, not silently ignored.
- `getUi()` and `onUiAction()` are part of the plugin contract, so a theme
  can answer with its own UI and can update it from a `plugin` action.
  `themes/ui-demo` implements both; the app ignores them until it grows the
  renderer.
- The theme repo's build checks that every `asset://` path a theme names is
  a file it ships, and warns about files it ships but never uses. Assets are
  packaged with their paths preserved (`assets/images/x.png`), which the
  app's own `scripts/plugin_zip.dart` would flatten — that helper still needs
  the same fix on the app side.
- `tools/install.dart` was verified end to end against a profile with a real
  SQLite database: the files land in the extraction directory the host
  expects, and the row is written with the theme ability and the selection.
- **The app has not changed**: no model, no sanitizer, no endpoint, no
  cache. A v3 theme draws as its two colour schemes until the host
  implements the rest. The theme repo is the specification of record —
  `schemas/theme.v3.schema.json` and `AUTHORING.md`.

## 2026-10-22 — the host reads the v3 colour roles

- `ThemeDefinition` carries `specVersion` (2 by default, 3 when the payload
  says so). It describes the payload, not the host's capabilities: the app
  reads the fields it knows and ignores the rest.
- `ThemeColors` gained the v3 roles — `popover`, `popoverForeground`, the
  eight `sidebar*` roles, `chart1` … `chart6`, and `success` / `warning` /
  `info` with their foregrounds. All optional; each falls back to the role it
  aliases, so a v2 payload decodes and draws exactly as before.
- The status colours and the sixth chart colour have no slot in shadcn's
  `ColorScheme`, so they are resolved beside it (`ThemeSemanticColors`) and
  published through `AppLayout`: `context.successColor`,
  `context.warningColor`, `context.infoColor`, `context.chart6Color` and
  their foregrounds.
- **A single unreadable colour no longer discards the whole palette.**
  `ThemeConverter.toColorScheme` resolves every role on its own against the
  built-in scheme, instead of building the scheme in one expression where a
  single bad value threw and the app drew its built-in palette — the theme
  appeared not to apply, and nothing said why. This was the last of the
  "one typo loses the theme" failures.
- The converter's signature changed: it now takes the fallback scheme, and
  never throws.
- Pinned by `test/theme_color_roles_test.dart` (11 tests): the roles reach
  the scheme, the aliases fall back, one bad colour keeps the rest of the
  palette, the status colours resolve and are published, and the payload
  version decodes.

## 2026-10-22 — the theme repository lives in this repo now

- The theme-plugin contract was in a separate repository
  (`Adamyabhatt01/Caelestia-theme-plugin-spotube`), and this repo's tests
  reached it through `../spotube-theme/dist/…` behind
  `skip: !archive.existsSync()`. **On a machine without that checkout, or in
  CI, the tests that pin the artifacts the app installs skipped silently** —
  the contract was tested everywhere except where it was enforced.
- Subtree merge (history preserved) into `themes/`. The standalone repo keeps
  serving its old URLs but takes no further changes; it is an archive.
- What had to move for a subdirectory to work:
  - `themes/analysis_options.yaml` — the package is plain Dart, so the
    nearest options win and the app's flutter_lints do not reach it. Lint
    parity is a later job; correctness does not wait on it.
  - `.github/workflows/themes.yml` — GitHub only runs workflows at the repo
    root, so `themes/.github/workflows/ci.yml` moved up, every step runs in
    `themes/` via `defaults.run.working-directory`, and it triggers only on
    changes to that directory.
  - The app's theme tests read `themes/dist/…` now. They run in a fresh
    clone.
- The published install URLs moved to this repo's raw paths
  (`…/spotube/master/themes/<id>/plugin.smplug`); all five verified 200 with
  matching bytes. Each theme's `plugin.json` `repository` field and the
  schema `$id` were repointed with them, which required rebuilding every
  artifact — the payloads are unchanged (goldens clean), and the theme suite
  (51) plus the app's artifact tests (29) pass against the rebuilt files.
- Still outstanding on the host, unchanged by this: the v3 tokens,
  components, shell, branding, UI renderer, action dispatcher, asset
  resolver and font loader. `themes/schemas/theme.v3.schema.json` and
  `themes/AUTHORING.md` are the specification for each.
