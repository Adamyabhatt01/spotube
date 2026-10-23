# Spotube Architecture

High-level map of the actual codebase. Read this to find the right subsystem,
then inspect only the relevant source. Prefer flows, paths, and constraints
over code. Source is authoritative; fix this doc if it drifts.

Entry point: `lib/main.dart`. Project is `package:spotube`, version `5.1.2+45`.

## Application startup

- Entry: `lib/main.dart` → `SpotubeApp` (`lib/modules/root/root.dart`).
- Explicit startup readiness (recent hardening): guarded/sequenced init rather
  than fire-and-forget. See `lib/modules/root/use_global_subscriptions.dart`.
- Settings: Drift `preferences_table` (single row id 0). Loaded by
  `UserPreferencesNotifier` (`lib/provider/user_preferences/user_preferences_provider.dart`),
  which subscribes to `watchSingle()` so changes propagate reactively without
  restart.
- Database: Drift, opened via `databaseProvider` (`lib/provider/database/database.dart`).
  Schema version 28 (`lib/models/database/database.dart:90`), steps guarded
  per-step via `_tableColumns(...).contains(...)`.
- Plugin (Hetu) system initialized lazily; audio-source plugin VMs are cached
  globally per `(config, engine)` — see `lib/services/sourced_track/source_resolver.dart`.
- First frame: splash (`lib/modules/splash`) then home. No lyrics/audio work at
  startup by default.

## UI

- Routing: `auto_route` (`lib/modules/root/routes.dart`).
- Main navigation: bottom/rail nav across home, search, library, connect, etc.
  Screens under `lib/pages/`, modular widgets under `lib/modules/`.
  Desktop sidebar top nav is Browse + Radio + Stats
  (`getSidebarTileList`, `lib/collections/side_bar_tiles.dart`); mobile bottom
  bar is home → search → radio → library → stats (`getNavbarTileList`).
  Search lives in Browse on desktop (`HomeSearchBar` sliver) and on its own
  `SearchRoute` (music + radio scopes) on mobile.
- State: Riverpod (`hooks_riverpod`) + `flutter_hooks`. Providers under
  `lib/provider/`, scoped to consumed slices where hot (e.g. player state).
- Large lists are `ListView.builder`-style; local-tracks scanning is streamed
  in bounded waves (see Performance).
- Player UI: `lib/modules/player/`; lyrics UI: `lib/pages/lyrics/` (`lyrics.dart`,
  `synced_lyrics.dart`, `plain_lyrics.dart`).
- Settings screens: `lib/pages/settings/settings.dart` + `sections/*`.
- Sidebar: `lib/modules/root/sidebar/sidebar.dart` — static top nav +
  reorderable Library group (`sidebarLibraryOrder`) + pinned playlists
  (`pinnedPlaylistIds`) + pinned radio stations (`pinnedStationIds`,
  whole-row plays, no detail route). Pin index merges saved + mirrored
  playlists (`lib/provider/sidebar/sidebar_provider.dart`); liked-tracks
  synthetic is built in UI (needs l10n). Reorder UI is the shared
  `SidebarOrderDialog`, opened from Settings → Sidebar, plus direct
  whole-row drag in the sidebar itself (`SidebarReorderableItem`, box/sliver
  adaptive — a bare box child fails sliver protocol in `NavigationSidebar`).
  Pin group headings are compact custom slivers (`_PinGroupHeading`, ~22px),
  not `NavigationLabel` (fixed 48px), with a 6px gap between the two pin
  groups instead of a full divider.
- **Library refresh (cross-device)**: the saved lists are read once per app
  session — `SavedListCacheMixin.buildSavedList` serves the disk snapshot and
  revalidates *behind* it, and that revalidation only runs inside `build()`.
  `SavedLibraryRefresher` (`lib/provider/metadata_plugin/library/library_refresh.dart`)
  is the single owner of every "the library may have changed" trigger (app
  start, app resume, window focus, connectivity restored, the Playlists page
  opening, a 10-minute foreground heartbeat) behind a 1-minute cooldown per
  list; it calls `SavedListCacheMixin.refresh()`, which re-reads the list from
  the network and re-persists the snapshot. All four saved lists are in it:
  playlists, liked tracks, saved albums, followed artists. Depth is per list
  (`refreshAllPages`): the playlists/albums/artists lists walk every page
  (they are small, and Spotify appends a new playlist to the **end** of the
  library, so a page-one probe cannot see it); the liked-tracks list is probed
  only (thousands of rows, and a newly liked track arrives at its head). A
  re-read costs one request unless the probe says the library moved. Every
  re-read is logged (`[library] <list>: N rows, M new`). Snapshots carry a
  `complete` flag (`library_snapshot_table`, payload v2) so a list that was
  still paging is not mistaken for the whole account.
- **Auth state changes only when the account does.** The plugin's auth
  provider re-publishes its answer on every plugin event (a token refresh
  included); writing it again rebuilds every provider watching it — the saved
  lists among them — and on a rejected token that looped. The saved lists
  therefore watch `metadataAccountProvider` (the last *settled* answer), not
  the auth provider itself, and the plugin reports when its stored
  credentials have landed (`auth.isLoaded()`) so "not known yet" is never
  published as "signed out". A 401 refreshes the session from its stored
  cookies and retries once (`metadataSessionRefresherProvider`).
- Playlists page order is independent of sidebar pins: `mainPlaylistOrder`
  (nullable: null means never initialized) drives
  `lib/pages/library/user_playlists.dart`, reordered by
  `PlaylistOrderDialogButton`. Sidebar pin reorder and main reorder write
  different columns; neither reads the other.
- Bottom player: `BottomPlayer` (`lib/modules/root/bottom_player.dart`) docks
  `fullWidth` (floating scaffold footer, schema v20 `playerDock`) or `docked`
  (in-flow under content via `Sidebar.contentFooter`, sidebar full height).
  Switch in Settings → Playback; inert on compact/mobile (`PlayerOverlay`).
- Theme-plugin geometry: `ThemeDefinition.tokens`/`.radius`/`.density` are
  clamped once at `sanitizeThemeDefinition`
  (`lib/services/metadata/theme_sanitizer.dart`), published by `AppLayout`
  (`lib/modules/app_layout/app_layout.dart`) and read as logical px through the
  `AppLayoutX` context extension. `density` rides `AdaptiveScaling` in `main.dart`
  so every `* scale` site honors it; card sizes/gutters/radii come from tokens.
  Cells are never shorter than their content — see `theme_layout_tokens_test.dart`.
- Theme-plugin contract — lives in `themes/` in this repo (subtree-merged
  from `Adamyabhatt01/Caelestia-theme-plugin-spotube`, which stays as an
  archive). It is a plain Dart package with its own `pubspec.yaml` and
  `analysis_options.yaml`; `themes/.github/workflows` moved to
  `.github/workflows/themes.yml` at the repo root, because GitHub only runs
  workflows from the root. The payload a theme returns is defined in
  `themes/schemas/theme.v2.schema.json` (frozen, the fields this app reads
  today) and `theme.v3.schema.json` (the draft), and it is validated there
  before this app ever sees it (`themes/lib/validator.dart`,
  `themes/lib/v3_validator.dart`). The theme build runs each theme and
  validates what it returns, so a payload that would throw here fails the
  build instead. This repo keeps the other half: `ThemeDefinition`
  (`lib/models/metadata/theme.dart`), `sanitizeThemeDefinition`, the theme
  endpoint and the theme cache. The golden payloads in
  `themes/conformance/` are what this repo's theme tests pin, and those
  tests read `themes/dist/` — in-repo, so they run in a fresh clone, where
  they used to read a sibling checkout that only existed on one machine and
  skipped silently elsewhere.
  Unknown payload fields are ignored by design — that is what lets a v3
  theme ship to a v2 app.
- The v3 contract is **complete on the theme side**: colours (the extra
  roles: popover, sidebar, status, charts), typography, spacing, motion,
  scale, icon sizes and overrides, the style of every shadcn component the
  app draws with, the shell's composition (`layout`, `enforce`,
  `responsive`), branding, assets, and a declarative UI tree with slots,
  screens, templates, bindings and actions. `themes/kitchen-sink` carries
  every field, and a test in `themes/test/` fails when the schema grows
  without an example. `getUi()` and `onUiAction()` are part of the plugin
  contract: a theme may answer with its own UI instead of carrying it in the
  payload.
- **Host v3 renderer:** `lib/modules/theme_ui/` turns a validated
  `ThemeUiDocument` into widgets. Nodes use flattened props (legacy `props`
  is merged with a warning), templates/conditionals/bindings are resolved by
  `ThemeUiRenderer`, and `progress` is a tappable/draggable seek control that
  dispatches `seek(fraction)`. `theme_ui_host.dart` owns the slot registry,
  the overlay screen stack, asset/font scopes and the host-provided back
  chrome; `theme_ui_action_dispatcher.dart` whitelists actions (and lets a
  `plugin` action return a UI override). `getUi()` / `onUiAction()` are
  served by the theme endpoint and cached by the metadata-plugin provider.
- **Shell consumption:** `AppLayout` publishes chrome/nav/progress decisions;
  `layout.player` drives the dock and `stage` slots (`stage.center`,
  `stage.below`), and the same layout feeds the sidebar, home, bottom player
  and splash. Theme assets resolve under `<plugin>/assets/` with the legacy
  root fallback; tiled images use nearest-neighbour filtering and theme fonts
  go through `FontLoader`. `branding.windowTitle` also calls
  `windowManager.setTitle` (GTK reflects it, but Hyprland keeps reporting the
  initial title).
- **Still host-owned:** `layout.responsive`, entry ordering
  (`navItems`/`libraryItems`), home/settings section lists, `titlebar` geometry
  and `enforce` are validated and carried in the model but the host continues
  to use its own breakpoints and user preferences. `progress` bars avoid
  `LayoutBuilder` so they survive shadcn's intrinsic footer measurement; a
  docked player gets its real content width from `PlayerSeekWidth`.

## Playback

- Track → `SpotubeMedia` (media_kit). For online tracks the URI is the local
  proxy: `http://<host>:<port>/stream/<trackId>` (`lib/services/audio_player/audio_player.dart`).
- Player is media_kit / libmpv via `SpotubeAudioPlayer`
  (`lib/services/audio_player/audio_player_impl.dart`), global `audioPlayer`.
- State provider: `audioPlayerProvider` (`lib/provider/audio_player/audio_player.dart`)
  exposing `AudioPlayerState.activeTrack`; position ticks are throttled to 1 Hz by
  a shared ticker in
  `lib/services/audio_player/audio_players_streams_mixin.dart` (seek and track
  change emit immediately) and fanned out through one `playerStreamPositions`
  provider rather than per-consumer gates.
- Serving: local shelf server `lib/provider/server/server.dart`, playback routes
  `lib/provider/server/routes/playback.dart` (download-first, cache, or proxy).

### Serving order (per request)

1. `findDownloadedFile(downloadLocation, track)` → serve local file with Range.
2. Streaming cache file.
3. Proxy upstream: `resolveServingUrl(track)` → dio HEAD preflight → GET stream;
   on failure lazily iterate `playbackFallbackUrls(ref, track)`.

## Source resolution

- `lib/services/sourced_track/source_resolver.dart` — `SourceResolver.candidates()`
  = plugins × engines. `audioSourcePluginProvider` resolves the default candidate;
  a global Hetu VM cache `_pluginCache` avoids recreating VMs.
- `playbackFallbackUrls` walks the candidate cascade lazily (only on failure).
- Downloads select a source separately (`lib/provider/download_manager_provider.dart`).

## Lyrics

- Interface: `LyricsProvider` (`lib/services/lyrics/lyrics_provider.dart`);
  global ordered `lyricsProviders` list. First non-empty result wins; failures
  are isolated per provider (throw → caught, continue).
- Registry init: `registerLyricsProviders()` in
  `lib/provider/lyrics/synced.dart` registers in order:
  1. `LRCLibLyricsProvider` (`lib/services/lyrics/lrclib_provider.dart`) — primary,
     queries with artist/track/album/duration; returns synced or plain.
  2. `BetterLyricsLyricsProvider` (`lib/services/lyrics/better_lyrics_provider.dart`)
     — Apple Music TTML fallback; `parseBetterLyricsTtml` handles line- and
     word-timed docs, `ss.mmm` and `m:ss.mmm` timestamps.
- Provider: `syncedLyricsProvider` (`SyncedLyricsNotifier`, family keyed by track).
  Flow: cache read → iterate providers → first non-empty wins → cache write.
- Cache: Drift `lyrics_table` (`lib/models/database/tables/lyrics.dart`), JSON
  blob via `SubtitleTypeConverter`. Fresh results do **not** overwrite a
  non-empty cache row (see synced.dart).
- Models: `lib/models/lyrics.dart` — `SubtitleSimple`, `LyricSlice`. Plain lyrics
  use `time == Duration.zero` for every line.
- Highlight: `lib/modules/lyrics/use_synced_lyrics.dart` — binary-search active
  line (`most recent time <= position + delay`), index-based. No `duration/lines`
  even distribution.

## Downloads

- `lib/provider/download_manager_provider.dart` — queue, concurrency (3 workers),
  progress, per-task `CancelToken`. `addToQueue`/`addAllToQueue` both go through
  one private `_enqueue`, which drops any track already live in `state`; a batch
  is therefore safe to overlap another (it used to append duplicates).
- Retention: terminal tasks are dropped past 100 entries, so the in-memory list
  is a *session* view. What a track's file really is lives in `track_download_table`.
- `_setStatus` is the only writer of download status, in memory and on disk: it
  persists the transition winner `unawaited`, so DB latency never enters the UI
  path. `canceled → completed` is refused there *and* in SQL (`DoUpdate where`),
  because an in-flight worker can still lose the race.
- Startup: `reconcilePersisted()` (unawaited from `build()`) marks
  `queued|downloading` rows `interrupted`, then re-checks `completed` rows for
  their file in waves of 32 → `missing`. No audio file is ever deleted here.
- Download containers load asynchronously with the audio-source plugin. A task
  queued before presets exist stays `queued` (not `failed`), and a presets
  listener starts it once a destination extension is available.
- Adoption of files downloaded before this existed is lazy: `_downloadTrack`
  finds the file on disk and the row becomes `completed`. A file cannot be
  matched to a Spotify track id up front — `SpotubeTrackObject.toMetadata`
  writes no id — so a scan-and-backfill is impossible.
- Chunk downloader: `lib/extensions/dio.dart` `ChunkDownloaderDioExtension`
  (HEAD Range probe → N ranged GETs; Range-ignoring server → full fallback).
- Optional VPN gate (default off): `_downloadTrack` holds one
  `RefCountVpnManager` lease for the whole attempt when `vpnMode` covers
  downloads (`lib/services/vpn/`, `lib/provider/vpn/vpn_provider.dart`).
  Two target kinds: NM UUID (managed: activate/verify/deactivate) and
  tunnel device name (share-only: wait/share/never touch, works without
  any backend); UUID wins when both set. Picker offers NM connections plus
  live tunnel interfaces (verified ∪ hint-matched; Wi-Fi/Ethernet
  unselectable).
  `_chunkDownloadWithRetry` takes a `beforeAttempt` hook so a VPN loss
  pauses retries instead of falling back to clearnet. While a lease is
  held, the download/playback/`globalDio` clients additionally source-pin
  sockets to the tunnel address (`vpn_pin.dart`, `pinned_client.dart` via
  `IOHttpClientAdapter.createHttpClient`); no pin means a default client.
  See `docs/automatic-vpn.md` (hardening, not a kill switch).
- Storage: `downloadLocation/<Name - Artists>.<ext>`; containers via
  `lib/models/metadata/audio_source.dart`. The path is computed by `_savePathFor`
  and recorded into `track_download_table.file_path`, so lookups stop matching names.
  A retry of a failed/interrupted transfer writes to
  `<Name - Artists> [<trackId>].<ext>` instead: a partial or colliding file is
  neither mistaken for the retry's output nor overwritten.

## Playlist mirroring

- `lib/provider/playlist_download_provider.dart` — `PlaylistMirrorService`.
  `mirror()` records an explicit whole-collection download; `reconcile()` (on
  playlist page load) rewrites membership to Spotify's current order and queues
  only tracks with no `track_download_table` row at all.
- `playlist_download_mirror_table.autoDownload` is the separate opt-in for
  background maintenance. `syncAutoDownloadPlaylists()` runs at startup and
  after an offline→online edge, walking each opted-in playlist page-by-page
  (`limit` 50), queueing per page, and writing the header + complete membership
  only after the last page. Successful runs are throttled; a failed run is
  retryable immediately and schedules bounded backoff retries (30s/60s/120s)
  so a transient plugin error does not leave later pages unchecked. The
  synthetic Liked Tracks entry is included: its `user-liked-tracks` id routes
  the fetch to `user.savedTracks`, not `playlist.tracks`.
- Auto sync reuses a valid global file from any playlist. It requeues when the
  recorded file is missing/empty (marking a `completed` row `missing`) and
  retries persisted `failed`/`interrupted` rows and in-memory `failed` tasks,
  including ones whose previous attempt left a non-empty file. Retries write to
  an id-suffixed path so the leftover file is never reused or overwritten. A
  canceled row is never overruled. File validation is only existence + non-zero
  size; it is not codec/checksum integrity.
- Deletion safety: `forget()` bumps a per-playlist generation before deleting
  the header/membership. Every playlist-scoped write and enqueue rechecks that
  generation, the auto flag, and the header, so an in-flight fetch cannot
  recreate a deleted mirror. Disabling auto-download only clears the flag.
  Neither path deletes a `track_download_table` row or an audio file.
- Identity is the Spotify playlist id throughout; the name is payload, never a
  key.
- Offline: `PlaylistPage` falls back to `mirroredPlaylistTracksProvider` (the
  membership join, in `position` order) and hides the fetch error when it has
  rows to show; `UserPlaylistsPage` merges `mirroredPlaylistsProvider` into the
  Spotify list by id.

## Local library

- `lib/provider/local_tracks/` — directory scan streamed in bounded waves
  (concurrency-bounded), `cancelled` sentinel via `ref.onDispose`.
- Metadata extraction via `metadata_god` (Rust/FFI). DB persistence in Drift.

## Database

- Drift, single SQLite DB (`db.sqlite` in app support dir). `@DriftDatabase` at
  `lib/models/database/database.dart`, tables under `lib/models/database/tables/`.
  Sixteen tables, named `<entity>_table` in SQL: `preferences_table`,
  `authentication_table`, `blacklist_table`, `history_table`, `lyrics_table`,
  `plugins_table` (incl. `selected_for_radio`), `scrobbler_table`,
  `skip_segment_table`, `source_match_table`,
  `source_match_quarantine_table`, `audio_player_state_table`,
  `library_snapshot_table`, `radio_favorites_table`, plus the three
  download/mirror tables below. There is no table of the user's Spotify playlists —
  those are read from the metadata plugin every time — and since v16 three that
  are local by definition:
  - `track_download_table` — one row per owned file, keyed by the Spotify
    `trackId` (`track_data` holds the full track JSON so a mirrored playlist
    renders and retries without the network).
  - `playlist_download_table` — membership only:
    `(playlist_id, track_id, position, added_at_ms)`. One track in three
    playlists is three rows here and one `track_download_table` row, which is
    what makes "never download twice" a database guarantee rather than a rule to
    remember.
  - `playlist_download_mirror_table` — one header row per playlist the user chose
    to mirror or opted into automatic downloads, so the entry renders in the
    Playlists section offline. Bounded by construction: a row exists only from
    an explicit whole-collection download or a user toggle, never from browsing.
    `auto_download` is off by default.
- Row-level SQL for those three lives in `lib/services/downloads/download_store.dart`
  as pure `AppDatabase`-taking functions (no DAO layer in this repo; precedent
  `lib/services/metadata/library_snapshot.dart`).
- Migrations: `MigrationStrategy` (schemaVersion 28) using `stepByStep`; guarded
  per-step via `_tableColumns(...).contains(...)`. Snapshots +
  `test/drift/app_db/migration_test.dart` auto-verify every version pair.
  After a schema change run `make migrate` (`drift_dev make-migrations`).
  `Migrator.createTable` does **not** create `@TableIndex` entities — a migration
  must call `m.createIndex(...)` itself, guarded by `_indexExists`.

## Plugins

- Hetu-based metadata plugins (`lib/services/metadata/`, `lib/modules/metadata_plugins/`).
- Discovery/registration; lifecycle: one VM per plugin reused (global cache),
  theme plugin VMs memoized. Extract via `lib/services/...`; safe path checks in
  `plugin_extraction_test.dart`.

## Networking

- HTTP via Dio (`globalDio`, `lib/services/dio/dio.dart`). Source/lyrics requests
  use `globalDio`; streaming uses `ResponseType.stream`/`ResponseBody`.
- Retry bounded (`lib/services/sourced_track/`); source TTL + single-shot
  `fetchAll`. Timeouts set per request (e.g. Better Lyrics 8s receive).

## State management

- Riverpod throughout. Key provider families:
  - `audioPlayerProvider` — playback state, scoped watches.
  - `userPreferencesProvider` — settings (reactive via `watchSingle`).
  - `syncedLyricsProvider(track)` — lyrics, family-keyed, not autoDispose.
  - `sourcedTrackProvider` — autoDispose + retention for current/next tracks.
- Async notifier `update()` used as a staleness guard; `ref.onDispose` sentinel
  (`_ScanCancelled`) for cancelling stale work.

## Platform / native

- Linux, Android, Windows, macOS, iOS, Web.
- Player: media_kit libs (`media_kit_libs_audio`).
- Audio metadata: `metadata_god` (Rust via flutter_rust_bridge).
- YouTube: `youtube_explode_dart` run in an isolate
  (`lib/services/youtube_engine/youtube_explode_engine.dart`, `IsolatedYoutubeExplode`).

## Critical Architecture Rules

- **Playback must preserve source-fallback semantics** — download-first, then
  cache, then proxy, then fallback cascade. Don't reorder or break the cascade.
- **Provider failures must not poison unrelated providers** — the lyrics loop
  isolates per-provider errors; keep it that way.
- **Expensive providers/resources should be lazy** — don't build VMs, isolates,
  or native resources at startup "just in case" (RAM goal).
- **High-frequency player state must not rebuild entire lists** — watch scoped
  slices (`audioPlayerProvider.select`), not the whole state.
- **Large collections should not be materialized unnecessarily** — stream scans;
  avoid `toList()` on huge listings.
- **Caches must be bounded** — e.g. sourced-track retention, bounded download
  task retention; no unbounded static/in-memory caches.
- **Native resources require explicit lifecycle** — isolates (YouTube engine)
  must be disposed; VMs cached, not leaked.
- **Lyrics sync must not divide duration evenly** — use actual line/audio data;
  plain lyrics use `time == Duration.zero`.
- **Real transparency is plugin-requested, user-vetoable** — the gate
  (`real_transparency.dart`) is `linux && allow-setting && theme loaded &&
  theme.background.transparent == true`. Absent flag or no theme plugin =
  opaque (strict); the setting is an opt-out, not a master switch. When real
  is active the host skips the painted wallpaper image and zeroes in-app blur
  — that is physics (painting covers the desktop; BackdropFilter samples
  nothing over a transparent window), not policy, so it is not theme
  configurable — but keeps painting the translucent overlay veil, so the
  theme's background colour survives over the live desktop. OFF (or
  unrequested) always falls back to the painted (fake) backdrop.