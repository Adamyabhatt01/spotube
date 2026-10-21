<div align="center">
  <img width="600" src="assets/branding/spotube_banner.png" alt="Spotube">

**Unofficial fork build of [Spotube](https://github.com/KRTirtho/spotube)** — a cross-platform,
open-source music streaming client that brings your own metadata, playlists and audio sources.

This fork is **not** affiliated with, endorsed by, or maintained by the Spotube project.

[Install](#-install) · [What you'll notice](#-what-youll-notice) · [Settings worth turning on](#-settings-worth-turning-on) · [Troubleshooting](#-troubleshooting) · [Under the hood](#-under-the-hood) · [Upstream project](https://github.com/KRTirtho/spotube)

</div>

---

> **New to Spotube? Read upstream first.** [KRTirtho/spotube](https://github.com/KRTirtho/spotube)
> and its [documentation site](https://spotube.krtirtho.dev) explain what the app is, how the plugin
> system works, and how to install official builds for every platform — Windows, macOS, iOS, Flatpak,
> Debian/Ubuntu, Arch, Fedora, Homebrew, Chocolatey, Scoop, WinGet. **This page only documents what
> this fork adds and how to install that.** If you just want Spotube, use upstream.

## 📦 Install

### Android — download an APK

Get a file from [**Releases**](../../releases) and open it on your phone.

| You want | File (in the latest release) | Use it when |
| --- | --- | --- |
| **Arm64** (recommended) | `Spotube-<ver>-android-arm64-v8a.apk` | Almost any phone sold since ~2017 |
| **32-bit ARM** | `Spotube-<ver>-android-armeabi-v7a.apk` | Older 32-bit phones and tablets |
| **x86_64** | `Spotube-<ver>-android-x86_64.apk` | Emulators and x86_64 devices |
| **Universal** | `Spotube-<ver>-android-universal.apk` | You don't know the ABI, or want one file that runs anywhere |

`<ver>` is the release version on the tag you downloaded, e.g. `5.1.2-fork.6`. Sizes vary per
build and are listed on the release page.

All four need **Android 7.0 (API 24) or newer**. The universal build carries `arm64-v8a`,
`armeabi-v7a` and `x86_64` machine code; each split build carries only its own ABI. Check what you
downloaded with `sha256sum -c RELEASE.sha256sum`.

Three things to know **before** you install:

1. **It will not update over official Spotube.** This fork is signed with a throwaway test key, so
   Android treats it as a different app. Uninstall the official one first. Your Spotify account,
   playlists and listening history are safe — they live with your account — but the local library
   index, downloaded files and in-app settings don't carry across between the two builds.
2. **Going from universal → a split build needs a reinstall.** The per-ABI builds carry higher
   version codes (5506 armeabi-v7a, 6506 arm64-v8a, 8506 x86_64) than the universal build (4506),
   so Android refuses a split build as a downgrade over the universal one. The other direction is
   fine.
3. **The app itself won't tell you an update exists.** This fork has no update feed — re-check
   [Releases](../../releases) when you want a newer build. The Spotify **metadata plugin** does
   check its own repository once a day ([why that matters](#the-spotify-plugin-comes-bundled)).
   Android will also warn about an unfamiliar publisher and about media-playback permissions;
   that's normal for any sideloaded APK.

### Linux — one command, from a checkout

```bash
bash scripts/install-local.sh
```

This builds a release binary and installs it: it picks a location it can write to
(`/usr/local/share/spotube-custom`, falling back to `~/.local/share/spotube-custom` without root),
backs up whatever it's replacing to `~/spotube-local-backup-<timestamp>.tar`, installs the build, and
adds a menu entry at `~/.local/share/applications/spotube.desktop`. It refuses to touch anything if
the binary is already identical, and warns if `libmpv`, `libsecret` or the tray library is missing.

- **Upgrade path:** `git pull`, then run the same command again. **Uninstall:** delete the install
  directory and that `.desktop` file.
- Flags: `--skip-build` installs the bundle already in `build/linux/`; `--prefix DIR` chooses the
  location.
- The build is a plain portable bundle (`spotube` plus `data/` and `lib/`), so you can also run
  `build/linux/x64/release/bundle/spotube` without installing anything at all. There is **no `.deb`,
  `.rpm` or `.AppImage` build here** — see [caveats](#-status-and-caveats).

### The Spotify plugin comes bundled

Spotube resolves metadata through plugins, and upstream ships none for Spotify. This fork builds its
own ([Adamyabhatt01/spotube-plugin-spotify](https://github.com/Adamyabhatt01/spotube-plugin-spotify))
and puts it **inside the app**: `assets/plugins/spotube-plugin-spotify/plugin.smplug`, currently
version 0.2.10. A fresh install seeds it, preinstalls it and selects it as the default metadata
source, so signing in is the only step — there is nothing to find and install by hand.

- **Updating an older install.** The bundled copy is compared against what's installed by
  `plugin.json`'s version, so an install carrying 0.2.9 moves to the bundled 0.2.10 on the next
  launch. The plugin also checks its own repository's latest release about once a day and offers
  the update in Settings → Metadata plugins.
- **Installing by hand** (only if you're on a build that predates the bundle) — Settings →
  Metadata plugins → Install:
  `https://raw.githubusercontent.com/Adamyabhatt01/spotube-plugin-spotify/0.2.10/dist/plugin.smplug`
- **What it does.** Search, albums, artists, playlists, Liked Songs (against Spotify's real
  library membership), playlist edits including removing a track, and stream resolution against
  the logged-in account. Anonymous sessions get the "please log in" fallback rather than the
  plugin's raw error.

## ✨ What you'll notice

The changes people actually feel. Several link to the mechanics further down.

- **The play button tells the truth.** Once audio is audible the transport shows pause and stays
  usable, even if the source manifest is still settling in the background. Pausing a track that has
  already played no longer brings the spinner back. The frosted bottom bar also keeps its tint
  through play/pause and scrolling.
- **Likes are real likes.** The heart reads Spotify's actual library membership, so liking a track
  adds it to Liked Songs and unliking removes it, instead of trusting editorial metadata that was
  true for most of the catalogue.
- **Artwork opens the album.** Tapping a cover navigates — on touch and on desktop — because the
  cover is part of the card's own tap target instead of a competing play gesture. The play, queue
  and pin buttons keep their own small taps, and a card or row stays tappable while its audio
  source is still resolving.
- **Search is scoped.** The mobile Search tab now has separate Music and Radio landings: Music
  shows personalised rails and New Releases, Radio drops the Music shortcut and Recent rail. The
  real Browse and Radio pages are untouched.
- **You get the recording you asked for.** Searches used to land on a lyric video, a slowed + reverb
  edit or a random fan channel — and keep that answer for six hours. The studio version wins now.
  → [Finding the right recording](#finding-the-right-recording)
- **A rate limit is a message, not a frozen app.** Hit Spotify's 429 and you get an error card that
  recovers on its own; your saved lists keep showing the last good data instead of going blank.
  → [Rate limits](#surviving-spotifys-rate-limits)
- **Tracks don't stop half-way.** An expired stream link used to stall playback mid-song; it's now
  noticed from the link's own expiry stamp and refreshed. → [Playback](#playback-and-streaming)
- **Downloads survive interruptions.** Chunked and resumable, up to 3 at a time, and importing a
  playlist asks "already downloaded, skip?" once instead of once per track.
- **Removing a song from a playlist works.** It failed silently for a long time: the call died in
  the plugin, the app didn't await it and nothing reported the failure. Now it reaches Spotify,
  says so when it can't, and drops the track from the local download mirror too, so it doesn't come
  back on reload.
- **The frost is there when you arrive.** On Android, a playlist or album header used to show a flat
  translucent panel until the first scroll blurred it, and the lyrics backdrop likewise. The artwork
  is now blurred as it's painted rather than sampled from behind, so it's correct on the first frame.
- **Lyrics open without the hitch.** The 1–2 s stutter on entering the lyrics page came from a
  full-screen blur over a cover that was still decoding, plus a loading shimmer that overflowed its
  own row by hundreds of pixels on a phone. Both are gone.
- **One button to clear downloaded music.** Library → Local files → *Delete local library* forgets
  every downloaded playlist and deletes the files this app wrote, cancelling downloads in progress.
  Music in folders you added yourself, play history, pinned playlists and your Spotify playlists are
  left alone, and the confirmation tells you how many files and how much space it's about to free.
- **Smoother on cheap phones and long sessions.** Less work per scroll, per second of playback, and
  per library row. → [Performance](#performance)
- **Optional: put your traffic through your own VPN** for downloads, streaming, or both — opt-in, off
  by default, and it never touches a connection it didn't create.
  → [Automatic VPN](#routing-through-your-own-vpn)
- **Your library, your layout.** Browse and Radio sit in the sidebar next to Stats; pin playlists
  and radio stations under the Library section, reorder the Library section, dock the
  player bar, choose how the volume control behaves, and let plugins ship whole themes.

## ⚙️ Settings worth turning on

Everything here is **off or default until you change it** — a fresh install behaves like upstream.

| Setting | Where | What it does |
| --- | --- | --- |
| **Automatic VPN** | Settings → Downloads | Route downloads and/or stream fetches through a VPN you already own. Also picks *which* target: a NetworkManager connection, or a live tunnel device from your provider's app. |
| **Disconnect when done** | Settings → Downloads | Whether a VPN Spotube started is brought down afterwards. Your own connections are never disconnected, whatever this says. |
| **VPN wait timeout** | not in the UI yet | How long a protected download waits for the VPN before failing, instead of quietly going over the normal connection. Stored as 60 s and editable only through the database at the moment. |
| **Player position** | Settings → Playback | **Full width** stretches the bar across the window; **Docked** stops it at the sidebar so the sidebar runs full height. |
| **Sidebar order / Pinned playlists & stations** | Settings → Sidebar, or long-press a playlist / station | Reorder the Library section and pin favourite playlists and radio stations under it. The sidebar top nav holds Browse, Radio and Stats. |
| **Volume control** | Settings → Desktop | Always visible, show on hover, or hidden. Desktop-only setting. |
| **Source priority** | Settings → Playback | Which provider (yt-dlp, NewPipe, YouTube Explode) to try first. |
| **Theme / splash screen** | Settings → Appearance | Plugin-supplied themes, and a custom splash. On Linux, optional Caelestia shell sync. |

## ❓ Troubleshooting

- **"App not installed" / update fails.** Almost always a signature mismatch: an official Spotube (or
  a build from a different key) is already installed. Uninstall it, then install this APK.
- **Nothing plays, or a 403 / endless spinner.** A stream link expired or YouTube changed something.
  Skip to the next track and back, or re-pick the source under Settings → Playback. Long stalls are
  the case worth reporting.
- **Library looks stale or shows an error card.** You're rate-limited by Spotify. This build stops
  hammering the API on purpose — wait it out. What you see is your last good snapshot, which is
  working as intended.
- **Downloads fail with a VPN error after enabling Automatic VPN.** The selected connection or tunnel
  wasn't reachable inside the wait window. The failure is deliberate: this build would rather fail
  than send traffic you asked to protect. Connect the VPN, widen the target choice, or turn the mode
  back to **Disabled**.
- **`Automatic VPN is not supported on this platform yet`.** System connections need Linux with
  NetworkManager and `nmcli` on PATH. Live tunnel devices work on any platform; if `nmcli` is absent,
  only the system-connection kind is unavailable.
- **Update check never announces anything.** By design — this fork publishes no update feed for the
  app. The bundled Spotify plugin is the exception: it checks its own repository's latest release and
  will offer an update there.

---

Everything below is the mechanics. The sections above are all most readers need.

## 🔬 Under the hood

### Finding the right recording

The largest behavioural change. Previously a search could resolve a track to a **lyric video, a
slowed + reverb edit, a live boot or a random fan channel** and then keep that answer for six
hours. Now:

- On Android, streaming goes through the NewPipe engine, which is searched with YouTube's **music
  songs** category first and falls back to the general **videos** category when the songs page
  doesn't answer the query — so the studio recording outranks video versions instead of losing to
  them. Tracks identified by ISRC are deliberately kept on the videos path, where the songs
  category returns an unusable page of unrelated results.
- A channel whose name appears in the query is preferred over one that doesn't, which is how the
  original artist wins over a re-uploader. The uploader *verification badge* is specifically
  **not** used as a signal — on measured real results it is inverted, because studio uploads sit on
  unverified auto-generated label channels while lyric re-upload channels are verified.
- Ranking is shared across all engines (so yt-dlp and YouTube Explode on desktop benefit too):
  official *lyric* videos no longer earn a bonus, altered versions (slowed, reverb, sped up,
  karaoke, covers, lyric rips) are penalized, and a candidate whose duration is off by more than
  15 seconds from the track's real length is penalized.
- A live/short/length-less result is demoted, never discarded — if the only thing YouTube has is a
  live version, you still get the song.

### Surviving Spotify's rate limits

A session-wide rate-limit gate replaces "retry until the API answers" with a single recorded
state: once a 429 is seen, further calls are short-circuited instead of hammering the wall, with
bounded auto-retry, a friendly error card instead of a spinner, and shared saved-artist/album id
sets so one list doesn't cost N requests. Library snapshots are persisted, so saved lists still
render from the last good snapshot while you're limited rather than going blank.

### Playback and streaming

- Fixes a YouTube **403 loop** by using `ios`/`androidVr` clients with a TV-manifest fallback, and
  re-validates a stream before refresh.
- Stream URLs are validated in bounded parallel waves and an **expired signed URL is detected from
  its own `expire` stamp** and refreshed, instead of stalling mid-track.
- A bounded playback-server rebind chain, playback cache mirroring, and a source-priority picker.
- Downloads are chunked and resumable, up to **3 concurrently**, with existing files on disk
  batch-checked first so a playlist import asks you once instead of per track.
- The queue-end radio fires once per tail track instead of once per position tick, and the player
  starts on the page already on screen while the rest of the queue streams in behind it.

### Routing through your own VPN

Strictly opt-in and **off by default** — with the setting untouched, every byte goes where it went
before. When enabled for downloads, playback, or both, Spotube waits for the VPN you picked before
a protected request, holds it for the duration, and fails *closed* rather than silently falling
back to your normal connection when it can't be had.

- Two kinds of target. A **system connection** (Linux + NetworkManager) is one of your own
  `nmcli` connections, which Spotube may activate before an operation and bring down after. A
  **tunnel device** is a live interface from your provider's app (`nordlynx`, `proton0`,
  `mullvad-*`): cross-platform, and Spotube only *shares* it — it never connects or disconnects
  something it doesn't own.
- Concurrent downloads share **one** reference-counted lease, so the tunnel isn't flapped per track.
- VPN you connected yourself is used but never torn down; only a connection Spotube activated is
  brought down, and only with "Disconnect when done" on. No passwords, keys or tokens are stored —
  authentication stays with the operating system.
- Mid-download VPN loss **pauses and waits** (bounded, default 60 s, cancellable) instead of
  retrying over the clear path; if recovery doesn't come, the download fails with an explicit error.
- While a lease is held, Dio sockets are source-pinned to the tunnel's own address
  (`Socket.connect(sourceAddress:)`) — qBittorrent-style hardening, since Dart has no
  `SO_BINDTODEVICE`. Unpinnable means no traffic, not unpinned traffic.

This is **not a VPN provider and not a system-wide kill switch**: there is no Spotube service,
server or subscription, and kernel routing, DNS, other applications and the Hetu/yt-dlp/NewPipe
transports are outside what the app can enforce. See
[`docs/automatic-vpn.md`](docs/automatic-vpn.md) for exactly what is and isn't pinned.

### Lyrics

An ordered in-code provider registry (`lyricsProviders`) with LRCLib first and Better Lyrics TTML as
fallback, track-scoped caching behind a single-flight lock, and retry that targets only the providers
that actually failed. Providers are tried in registration order and may be inserted at init, so a new
lyric source is a code-level extension rather than a user setting. Concurrent fetches for one track
collapse into one request, misses are memoized, and TTML parsing moved off the UI thread.

### Getting around

- Playlists and radio stations can be **pinned** under the Library section of the sidebar (cover
  tap plays, label navigates; station rows play), and that section is reorderable — directly in
  the sidebar or from Settings → Sidebar (top navigation stays fixed). Pin group headings are
  compact so the pins stay dense.
- The player bar can be **docked** to stop at the sidebar — so the sidebar runs full height — instead
  of stretching across the whole window.
- Volume control is a setting: always visible, show on hover, or hidden.

### Performance

Android first, because that's the device where it hurt:

- Home-screen widget updates coalesced instead of one platform round trip per second.
- Single 1 Hz playback-position ticker; queue persisted on mutation rather than on tick.
- Large background/header blur frozen once per gesture instead of recomputed per frame; the pinned
  bottom chrome keeps its frost because dropping it there was not a measured win and made the bar
  disappear under translucent themes.
- Bounded local-library scan concurrency, resize-aware local artwork, and pruning of orphaned
  artwork after a full scan.
- Top-track history aggregated in SQL and auto-disposing stats providers.
- Startup subscription hardening, plus fixes to scrobbling, the sleep timer, Discord RPC and
  glance.
- yt-dlp is located by **absolute path** rather than relying on the process `PATH`, which is why
  desktop detection no longer depends on how the app happened to be launched.

#### Benchmarks: RAM and CPU

Linux release bundle from fork build 2 (`2be74adf`), Flutter 3.35.2, visible window on
Hyprland/Wayland with an NVIDIA GPU. Fresh launch, no interaction, two five-minute runs. PSS and
RSS are the process tree (the app plus any helper still alive at that sample); CPU is the Spotube
process as a percentage of one core.

| Time after launch | PSS | RSS | Processes |
| --- | --- | --- | --- |
| 30 s | 323–330 MB | 409–419 MB | 4 |
| 3 min | 338–368 MB | 411–444 MB | 1 |
| 5 min | 303–328 MB | 376–401 MB | 1 |

The 3-minute bump is the Home/library artwork loading, not a leak; it settles again by five
minutes. Live Dart heap was **27.5 MB** in the VM's own accounting.

Idle CPU over ten 25-second windows: **median 27%, range 23–33% of one core** (the two runs averaged
29% and 27%). "Idle" here means no input, not no work: the visible window keeps drawing every vsync,
and the earlier ticker audit found 24 always-mounted animations. A 0% figure would mean the window
had stopped rendering. Compositor and NVIDIA driver work is excluded.

Android has no comparable on-device numbers from this machine (no `adb` or device); the THP fix
there is the same kernel setting, but Android CPU and frame-time numbers remain unmeasured.

#### Why RAM use went down

The short version: most of the reported "Dart heap" was not the Dart heap. The kernel was backing
the VM's large, sparsely-touched heap arena with 2 MB transparent huge pages (THP), so touching a
few KB charged megabytes of resident memory. The VM's own accounting put the live heap at
**27.5 MB**; RSS said hundreds.

The fix is a per-process `prctl(PR_SET_THP_DISABLE)` in the Linux runner and on Android
(`MemoryBacking.kt` + `memory_backing.cpp`). It affects only Spotube and is a no-op where THP is
already off. The pre-fix build measured **PSS 548 MB / RSS 648 MB** at five minutes; the current
runs settle at **PSS 303–328 MB / RSS 376–401 MB**.

The smoothness cost was measured over four 25-second windows: minor faults and CPU overlapped
run-to-run with no consistent direction, because the hot paths are native mpv/FFmpeg and Impeller
buffers, not the Dart heap. The app's three artwork caches also share one device-aware budget now —
a quarter of Android's per-app heap limit, clamped to 8–64 MB — instead of fixed ceilings plus an
unbounded per-URL memo.

The same measurements explain what *did not* help: replacing spinners, removing the nav bar, or
dropping `surfaceBlur`. Each was tested and reverted; idle CPU is spent in always-mounted animated
widgets and the framework's per-frame work, not in the frosted chrome.

Then a pass over desktop, each item measured before and after:

- Saved lists render from their on-disk snapshot immediately and revalidate behind the answer,
  instead of paying a 2 × 30 s retry chain for data already in the database.
- Playlist membership writes are batched and reconciled once per change: a queue rewrite that cost
  74 ms per write at 5k rows and 263–713 ms at 25k now costs **0 writes** unless membership really
  changed, and 10–33 ms when it does.
- Download-queue subscriptions are scoped to the row that reads them, the local-library prefilter's
  `stat` fan-out is bounded, and mirrored playlist decodes are cached by `(trackId, updatedAt)`.
- One in-memory fetch per cover URL across callers, list search debounced, and scroll-time
  re-blurring and re-decoding stopped per frame.
- Every network path is now *timed* (`dio.<host>`, `metadata.request`, `source.resolve`,
  `engine.<call>`, keyed by host so signed tokens never land in a key), which is how the 2026-09-23
  round was diagnosed at all. A rejected Spotify login says so rather than spinning.
- Update checks run once a day, not once a launch.

### Themes

Plugins can ship a full theme (colour roles, glass surfaces, art or shell backgrounds, radius,
density, dynamic colour), with untrusted values clamped to render-safe ranges and malformed themes
falling back rather than crashing. On Linux there's optional Caelestia shell sync, following the
active scheme from `~/.local/state/caelestia/scheme.json`. A custom splash screen is configurable
under Settings → Appearance.

### Plumbing

Database schema through **v27** with per-step migration guards (each step re-checks the live column
set, so a half-applied migration can be finished rather than only retried), dependency pinning with
a CI job that detects drift, and a reproducible build script. APKs are versioned
`5.1.2+4506` — upstream's build `45` plus the fork's own `06` — and per-ABI builds get Flutter's
`abiIndex * 1000 + versionCode` override, which is why arm64 reports 6506 while universal reports
4506.

## 🛠 Build from source

Requires [FVM](https://fvm.app) with the Flutter version pinned in `.fvmrc` (currently 3.38.10).

```bash
# Linux system deps (Debian/Ubuntu); see upstream docs for other platforms
sudo apt-get install mpv libmpv-dev libappindicator3-1 libappindicator3-dev \
  libsecret-1-0 libsecret-1-dev libnotify-dev avahi-daemon libnss-mdns libwebkit2gtk-4.1-0 libsoup-3.0-0

git clone https://github.com/Adamyabhatt01/spotube.git && cd spotube

# .env.example contains $PLACEHOLDERS — generate it, don't copy it verbatim
ENABLE_UPDATE_CHECK=0 RELEASE_CHANNEL=nightly HIDE_DONATIONS=0 \
  envsubst < .env.example > .env

fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs

fvm flutter run -d linux            # or windows | macos | <android-device-id>
```

Android artifacts, all built from this repo:

```bash
fvm flutter build apk --release --flavor stable                  # universal
fvm flutter build apk --release --flavor stable --split-per-abi   # per-ABI, smaller
```

Note this project defines Gradle product flavors, so `flutter build apk` needs `--flavor`. Release
builds are signed with `android/key.properties`, which points at a local test keystore — supply your
own if you publish your own builds. Automatic VPN needs `nmcli` (NetworkManager) on the machine
running the app; nothing needs to be installed to build without it.

Android builds run on Impeller. Flutter 3.38 includes the engine fix for the backdrop-filter pass
([flutter/flutter#173622](https://github.com/flutter/flutter/issues/173622)), so the frosted bottom
chrome stays stable without the temporary Skia fallback.

## ⚠️ Status and caveats

- **Unofficial and unsupported.** I'm not maintaining this for anyone else's benefit. If something
  breaks, opening that issue against *upstream* will get you the wrong advice, because much of
  what breaks is this fork's own code.
- **Linux packaging is thin.** Only the portable bundle is published; `.deb`, `.rpm` and `.AppImage`
  need `fastforge`, which isn't installed in the environment that builds these binaries.
- **Older releases may not match their commit.** From `v5.1.2-fork.6` the published binaries are
  built from the tagged commit, so the tag is the source of the artifact. Fork builds `.1`–`.4` were
  made from working trees, which is why that caveat used to apply to every release here.
- **No signature continuity.** The test key means this fork's builds are only interchangeable with
  each other, never with official releases.
- **The regression suite is not published.** About 1,500 tests guard this fork's own code — the VPN
  lease logic, download reconciliation, source ranking, snapshot revalidation — and none of them are
  in this repo; `test/` is gitignored on purpose. So a clone has nothing to run, and the CI test gate
  passes because it finds zero tests. Treat the shipped binary as better tested than the source
  tree looks.

## 📄 License

Spotube is open source under the **[BSD-4-Clause](LICENSE)** license, copyright
[Kingkor Roy Tirtho](https://github.com/KRTirtho) and contributors. This fork is distributed under
the same license and keeps that license file intact; the advertising clause of BSD-4-Clause applies
to upstream's name. Fork-specific changes carry the same license and are offered without warranty.

For everything upstream — the wider plugin ecosystem, translations, full platform guides and the
community — go to [spotube.krtirtho.dev](https://spotube.krtirtho.dev). The Spotify metadata plugin
is the exception: it is this fork's own, so issues about metadata, playlists or likes belong on
[Adamyabhatt01/spotube-plugin-spotify](https://github.com/Adamyabhatt01/spotube-plugin-spotify).
