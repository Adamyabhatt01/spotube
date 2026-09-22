<div align="center">
  <img width="600" src="assets/branding/spotube_banner.png" alt="Spotube">

**Unofficial fork build of [Spotube](https://github.com/KRTirtho/spotube)** — a cross-platform,
open-source music streaming client that brings your own metadata, playlists and audio sources.

This fork is **not** affiliated with, endorsed by, or maintained by the Spotube project.

[Install](#-install) · [What this fork changes](#-what-this-fork-changes) · [Build from source](#-build-from-source) · [Upstream project](https://github.com/KRTirtho/spotube)

</div>

---

> **Start with upstream.** [KRTirtho/spotube](https://github.com/KRTirtho/spotube) and its
> [documentation site](https://spotube.krtirtho.dev) are the source of truth for what Spotube is,
> how the plugin system works, and how to install official builds for every platform — including
> Windows, macOS, iOS, Flatpak, Debian/Ubuntu, Arch, Fedora, Homebrew, Chocolatey, Scoop and
> WinGet. This page documents only the differences in this fork and how to install those.

## 📦 Install

### Android

Grab an APK from [**Releases**](../../releases) and open it on your phone.

| Build | File | Use when |
| --- | --- | --- |
| Arm64 (recommended) | `Spotube-android-arm64-v8a.apk` | Almost any phone sold since ~2017 |
| Universal | `Spotube-android-universal.apk` | You don't know the ABI, or the device is 32-bit / x86 |

Both require **Android 7.0 (API 24) or newer** and contain `arm64-v8a`, `armeabi-v7a` and
`x86_64` code (the universal build) or just `arm64-v8a` (the arm64 build).

Before installing, three things you should know:

- **This is a personal fork, signed with a throwaway test key**, not the upstream release key.
  It will therefore **not** install as an update over an official Spotube — uninstall that first.
  Your Spotify credentials, playlists and listening history live with your account, not the app,
  so nothing is lost; but the local library index, downloaded files and settings are per-app and
  will not carry over between the official build and this one.
- **You won't get updates automatically.** This fork has no update feed. Re-check
  [Releases](../../releases) when you want a newer build.
- Android will warn about an unfamiliar publisher and about the app requesting media playback
  permissions. That's expected for any APK installed outside an app store, not specific to this fork.

### Linux — install this repo's build

If you have a checkout of this repository, one command builds a release binary and installs it:

```bash
bash scripts/install-local.sh
```

It picks a location it can write to (`/usr/local/share/spotube-custom`, falling back to
`~/.local/share/spotube-custom` without root), tars a backup of whatever it is replacing to
`~/spotube-local-backup-<timestamp>.tar`, installs the build, and writes a launcher entry to
`~/.local/share/applications/spotube.desktop`. It refuses to do anything if the binary it would
install is already byte-identical to what's there, and it warns if `libmpv`, `libsecret` or the
tray library are missing. Re-running it after a `git pull` is the upgrade path; there is no
separate uninstall step — delete the install directory and the `.desktop` file.

Useful flags: `--skip-build` installs the bundle that's already in `build/linux/`, and
`--prefix DIR` chooses the install location.

## 🔧 What this fork changes

Everything below is on top of upstream. The short version: this fork is mostly about the parts
that break in daily use — source matching, rate limits, streams that expire, and long sessions on
low-end devices.

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

### Lyrics

A settings-driven provider registry with LRCLib as primary and Better Lyrics TTML as fallback,
track-scoped caching behind a single-flight lock, and retry that targets only the providers that
actually failed.

### Performance and stability

Mostly Android-focused, since that's the device where it hurt:

- Home-screen widget updates coalesced instead of one platform round trip per second.
- Single 1 Hz playback-position ticker; queue persisted on mutation rather than on tick.
- Scroll-time blur frozen once per gesture instead of recomputed per frame.
- Bounded local-library scan concurrency, resize-aware local artwork, and pruning of orphaned
  artwork after a full scan.
- Top-track history aggregated in SQL and auto-disposing stats providers.
- Startup subscription hardening, plus fixes to scrobbling, the sleep timer, Discord RPC and
  glance.
- yt-dlp is located by **absolute path** rather than relying on the process `PATH`, which is why
  desktop detection no longer depends on how the app happened to be launched.

### Themes

Plugins can ship a full theme (colour roles, glass surfaces, art or shell backgrounds, radius,
density, dynamic colour), with untrusted values clamped to render-safe ranges and malformed themes
falling back rather than crashing. On Linux there's optional Caelestia shell sync, following the
active scheme from `~/.local/state/caelestia/scheme.json`. A custom splash screen is configurable
under Settings → Appearance.

### Plumbing

Database schema through **v13** with per-step migration guards, dependency pinning with a CI job
that detects drift, and a reproducible build script.

## 🛠 Build from source

Requires [FVM](https://fvm.app) with the Flutter version pinned in `.fvmrc` (currently 3.35.2).

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

Note this project defines Gradle product flavors, so `flutter build apk` needs `--flavor`.

## ⚠️ Status and caveats

- **Unofficial and unsupported.** I'm not maintaining this for anyone else's benefit. If something
  breaks, opening that issue against *upstream* will get you the wrong advice, because much of
  what breaks is this fork's own code.
- **Source may run behind the binaries.** Releases here can include a working tree that hasn't
  been tagged, so the APK is not necessarily reproducible from the commit it names. If that
  matters to you, build it yourself from the steps above.
- **No signature continuity.** The test key means this fork's builds are only interchangeable with
  each other, never with official releases.

## 📄 License

Spotube is open source under the **[BSD-4-Clause](LICENSE)** license, copyright
[Kingkor Roy Tirtho](https://github.com/KRTirtho) and contributors. This fork is distributed under
the same license and keeps that license file intact; the advertising clause of BSD-4-Clause applies
to upstream's name. Fork-specific changes carry the same license and are offered without warranty.

For everything upstream — the plugin ecosystem, translations, full platform guides and the
community — go to [spotube.krtirtho.dev](https://spotube.krtirtho.dev).
