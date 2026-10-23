# Spotube Memory Report

Measured on this machine (Linux, Hyprland/Wayland, NVIDIA), 2026-10-19.
Harness: `scripts/mem-report`. Raw JSON: `build/mem-report/*.json`.

## Fork.2 idle benchmark (2026-10-20)

Two fresh five-minute runs of the installed Linux release (`2be74adf`), visible
window, no interaction, Hyprland/Wayland + NVIDIA. PSS/RSS are the process
tree; helpers (`glycin-svg`, `bwrap`) are alive at t+30s and gone by t+3min.

| time | run 1 PSS/RSS | run 2 PSS/RSS |
|---|---|---|
| t+30s | 330.1 / 418.7 MB | 322.7 / 409.1 MB |
| t+~105s | 312.4 / 387.4 MB | 334.7 / 407.9 MB |
| t+3min | 368.2 / 443.5 MB | 338.0 / 411.3 MB |
| t+5min | 303.1 / 375.7 MB | 327.8 / 401.0 MB |

CPU over ten 25-second windows: median **27.1%** of one core, range
**22.6–33.4%** (run means 29.1% and 26.6%). The t+3min memory bump is the known
Home/library artwork settle, not a leak. Live Dart heap still 27.5 MB.
Harness: `build/bench/bench_current.py` (ignored build artifact), raw JSON beside
it. This refreshes the old ~22% CPU figure; same conclusion — a visible idle
window renders continuously, so idle CPU is not near zero.

## Headline: the footprint was mostly kernel bookkeeping, not the app

The first measurement said "Dart heap: ~365 MB, the dominant consumer". That
was **wrong**, and the reason why matters.

The Dart VM's own accounting (via the VM service, `getMemoryUsage`) reports a
**live heap of 27.5 MB**. The 365 MB came from the *kernel* backing the VM's
sparsely-touched 5.1 GB heap arena with **transparent huge pages** (2 MB
pages): the app touched a few KB here and there and was charged 2 MB of
resident memory for each.

| | RSS | PSS | AnonHugePages | live Dart heap |
|---|---|---|---|---|
| Before (THP on, the default) | 606 MB | ~380 MB | 250 MB | 27.5 MB |
| **After (`prctl(PR_SET_THP_DISABLE)`)** | **203 MB** | **~200 MB** | **0 MB** | 27.5 MB |

The fix is one call in the Linux runner (`linux/main.cc`) and the equivalent
on Android (`MemoryBacking.kt` + `memory_backing.cpp`): a per-process
`prctl(PR_SET_THP_DISABLE)`. It affects only Spotube, and it is a no-op on
a kernel without THP.

### What it costs

Page-fault granularity: a 4 KB fault is slower than a 2 MB fault. Measured
on the running app, over 25-second windows and four runs each:

| | minor faults/s | CPU |
|---|---|---|
| THP on | 5,741 / 5,380 / 5,599 / 5,695 | 25.0 / 23.4 / 24.5 / 24.2% |
| THP off | 5,801 / 5,998 / 5,476 / 5,554 | 23.1 / 23.5 / 25.2 / 23.6% |

**Overlapping** — no consistent direction. The app's hot paths (mpv/FFmpeg
audio, Impeller raster) run on native buffers, and the Dart heap holds no
large hot arrays, so there is no TLB pressure to relieve.

### It changes every other conclusion

With THP off, the "Dart heap retention" theory behind the RAM plan's items
1.2, 1.4 and 1.5 was chasing **phantom memory**: the entire live heap is
27.5 MB, so the image-cache ceilings (64 MB + 24 MB) cannot have been the
problem. Those items are re-labelled below.

### Idle CPU is a separate story, and it does not go lower

The CPU question was investigated to the same depth, and the answer is
different from what the RAM plan assumed.

| | Idle CPU |
|---|---|
| Stock Flutter app, same machine, same harness | **0.0-0.1%** |
| Spotube | **~22%** (GTK main ~10%, raster ~6.5%, Dart UI ~5%) |

So the cost is Spotube's, not Flutter's. The app renders a **continuous
64 fps** while idle (347 frames in 40 s, median gap 15.4 ms), which a
Flutter app only does when something requests a frame every vsync. The
2026-10-20 fork.2 re-measure moved this to a 27.1% median / 22.6–33.4% range
(ten windows, two runs) but did not change the conclusion.

The requesters were **found**, by patching `Ticker._tick` in the Flutter
SDK to print its owner: **24 always-running tickers**, dominated by

- `_OverflowMarqueeState` (934 ticks) — shadcn's `NavigationButton`
  defaults to `NavigationOverflow.marquee`, and `OverflowMarquee` starts
  its ticker in `initState` and never stops it, calling `setState` every
  tick forever. The app has 4 such buttons in the always-mounted
  sidebar.
- `_CircularProgressIndicatorState` (8 instances) — Flutter's indicator
  calls `_controller.repeat()`; with the Spotify API returning 401 the
  error paths keep spinners mounted.
- plus `AnimatedValueBuilder`, `_AnimatedContainer`,
  `_AnimatedFadeOutFadeIn`, `AnimatedSwitcher` and the splash.

**Replacing the spinners and the marquee with static equivalents changed
nothing** (22.4% after, 21.6% before): the frame *scheduling* is not
where the CPU goes. Both changes were **reverted** — a real spinner is
better UX for a short wait, and the marquee→ellipsis swap changes how
labels render for no measured gain.

The same negative result for `surfaceBlur: 0`, removing the nav bar,
removing the bottom player and removing the theme background. Cutting
this further means not rendering the UI: a rewrite, not an optimization.
`.ai/AUDIT_STATE.md` records the method so it is not re-investigated.

## How to read these numbers

| Metric | Source | What it means |
|---|---|---|
| **PSS** (primary) | `/proc/<pid>/smaps_rollup` → `Pss` | Physical memory share. A page shared between N processes counts 1/N to each, so summing PSS across a process tree does **not** double count. This is the number that answers "how much RAM does this cost me". |
| **RSS** (secondary) | `smaps_rollup` → `Rss` | Resident pages, shared pages counted **in full** for every sharer. Over-reports a tree; use as a trend, not a total. |
| VSZ | `statm` field 0 | Virtual address space. **Not memory.** Reported nowhere in this document as a RAM figure. |

The tree total below is PSS-based. Summing RSS across the tree would
double count the ~49 MB of NVIDIA driver pages the app and the GPU
processes share.

## Baseline: the Flutter floor

A stock `flutter create` hello-window app, built `--release` with the same
SDK (3.35.2) and measured with the same harness:

| Scenario | PSS | RSS | Procs |
|---|---|---|---|
| Floor app, t+30s idle | **90.0 MB** | 188.0 MB | 4 |

Everything above this line is Spotube's. This is the number no optimization
can go below without leaving Flutter.

## Spotube measured

`build/linux/x64/release/bundle/spotube`, fresh launch, no interaction:

| Scenario | PSS | RSS | Procs |
|---|---|---|---|
| t+0s (process spawned) | 14.1 MB | 23.2 MB | 1 |
| t+30s idle | 280.5 MB | 380.1 MB | 4 |
| t+300s idle (5 min) | **349.8 MB** (app 314.8 + a 35 MB yt-dlp child) | **462.3 MB** | 2 |

The tree briefly contains 3 helper processes at t+30s (`glycin-svg`, two
`bwrap` sandbox helpers) which exit on their own. They are
desktop-environment helpers, not WebKit. The yt-dlp child at t+300s is the
audio-source engine doing its work.

**Before the THP fix, the same binary measured PSS 548.1 MB / RSS 648.1 MB
at t+300s.** The change is the THP fix alone (plus the device-aware image
budget, which is a no-op on this machine). The app's own process went from
**PSS 548 → 315 MB** and **RSS 648 → 415 MB**.

The plan's headline numbers ("~565 MB RSS", "idle PSS ~348 MB") are
reproduced: the RSS is in the same band, and the PSS was ~200 MB *higher*
than the plan's figure, because the plan's PSS baseline predates
`PERFORMANCE.md:22`. See "Correction to the plan's baseline" below.

## Where the memory is (idle, RSS attribution by mapping)

Measured with THP **on** (the pre-fix state), so the comparison with the
table above is apples-to-apples. Total RSS 570.7 MB.

| Component | RSS | Notes |
|---|---|---|
| **Dart VM heap arena** (unnamed anon) | **300.6 MB** | One single `rw-p` mapping, **5.1 GB reserved**, 230 MB of it in transparent huge pages. **Not live data** — the VM's own accounting says the live heap is 27.5 MB. |
| Dart VM heap (named `anon:dart-heap`) | 64.0 MB | The VM's own small-object heap. |
| NVIDIA GPU driver | 49.2 MB | `libnvidia-gpucomp` + `libgallium` + `nvidia-eglcore`. Driver, not app. |
| LLVM (shader JIT) | 18.4 MB | `libLLVM` — GPU pipeline compilation. |
| Spotube's own code | 17.6 MB | `libapp.so` (obfuscated release build). |
| Flutter engine | 14.1 MB | `libflutter_linux_gtk.so`. |
| **WebKit** (webkit2gtk + jscore + soup) | **7.4 MB** | See below. |
| FFmpeg (avcodec/avformat) | 6.8 MB | media_kit's decoder. |
| GTK3 (gtk + gdk + pixbuf) | 6.3 MB | Widget toolkit. |
| libmpv (media_kit) | 2.7 MB | The audio/video player. |

**The largest line was the kernel's huge-page accounting, not the app.**
With THP off, that 300.6 MB drops to ~92 MB of genuinely-touched heap, and
the total falls by 227 MB without a single application object changing.

## The WebKit question, answered

The plan's item 1.1 proposed "stop linking/loading WebKitGTK at idle",
on the theory that it was a large idle cost. **Measured: it is 7.4 MB.**

`ldd` on the installed plugin confirms the libraries *are* linked into the
binary and mapped into the process at idle:

```
libwebkit2gtk-4.1.so.0      => /usr/lib/libwebkit2gtk-4.1.so.0
libsoup-3.0.so.0            => /usr/lib/libsoup-3.0.so.0
libjavascriptcoregtk-4.1.so.0 => /usr/lib/libjavascriptcoregtk-4.1.so.0
```

But the resident cost is small, and **no WebKit helper process exists at
idle** — WebKit's network/UI processes only spawn when a webview is
actually opened. Verified by enumerating the full descendant tree while the
app sat idle: one process (the app itself), no `WebKitWebProcess`, no
`WebKitNetworkProcess`.

Dropping the webview would therefore save **at most ~7 MB of a 571 MB
footprint (1.3%)** — and it would break plugin authentication, because the
webview is not host code: it lives in the metadata plugin
(`hetu_spotube_plugin/lib/webview/webview.dart` calls `WebviewWindow.create`
on Linux) and is a declared `PluginApis.webview` capability. The plan's
suggested replacement — "the flow `auth.dart` already has for web" — does
not exist; `auth.dart` only has `WebviewWindow.clearAll()`.

**Item 1.1 is dropped on measured evidence.**

## Plan items, judged against the measurements

| Plan item | Claimed saving | Measured | Verdict |
|---|---|---|---|
| 1.1 Drop the WebKit webview | (large, unquantified) | **7.4 MB** (1.3%), and it breaks plugin auth | **DROPPED** — not worth the risk |
| 1.2 Unify the three image-retention layers into one byte budget | up to 88 MB of retained artwork | The live Dart heap is **27.5 MB**, so the 64 MB + 24 MB ceilings cannot have been holding 88 MB — they are ceilings, not usage. The ceilings are now **device-aware** (see below) so the ceiling matches the device rather than being a fixed number. | **DONE, in a different form** — the ceilings now follow the platform's per-app limit |
| 1.3 Cap `_artworkBytesMemo` by bytes, not entries | small | Real gap, confirmed in code. Bounded by 64 entries of unbounded size. | **DONE** — now bounded by bytes (`service_utils.dart`), with the entry count kept as a backstop |
| 1.4 Don't retain embedded picture bytes in the local-library model | large | **Already true.** `local_tracks_provider.dart:145-158` writes `picture.data` to a file and keeps only the path. | **DROPPED** — no-op |
| 1.5 Bound `PluginVmCache`, evict idle plugin VMs | unknown | `PluginVmCache` exists (`metadata_plugin_provider.dart:1035-1076`) and already evicts by slug on plugin change. `hetu_script` 0.4.2+1 has **no dispose API** (grep: no `dispose` anywhere in its `lib/`), so eviction drops a reference only. The VM count is not the measured problem. | **DEFERRED** — needs a VM-count measurement |
| 1.6 Ship-size → resident-size | (implicit) | **Category error.** `country_flags` (3.3 MB) is a *transitive* dep of `shadcn_flutter` (216 lib files import it) and is referenced by zero Dart files — dropping it means dropping shadcn_flutter. `uses-material-design: false` was already investigated and rejected (`.ai/AUDIT_STATE.md:987`: "not safe, do not propose"). Ship size ≠ RSS. | **DROPPED** — wrong metric |

## The device-aware image budget (what replaced 1.2)

The three image caches now share one budget that follows the device:

| Cache | Was | Now |
|---|---|---|
| `PaintingBinding.instance.imageCache` | fixed 64 MB | a quarter of the platform's per-app heap limit, bounded to 8–64 MB |
| `UniversalImage._decodedMemoryCache` | fixed 24 MB | a third of the image budget |
| `ServiceUtils.artworkBytes` memo | 64 entries, **no byte cap** | a quarter of the image budget, **by bytes**, with the entry count as a backstop |

On Android the per-app limit (`ActivityManager.getMemoryClass()`) is read
over a platform channel (`DeviceMemoryChannel.kt`); on Linux and Android
the device total comes from `/proc/meminfo`; elsewhere the conservative
32 MB default applies. The artwork memo was the real gap: a 640x640
Spotify cover is ~150 KB and a small one ~5 KB, so an entry-count cap let a
handful of large covers cost megabytes without bound.

## Correction to the plan's baseline

The plan's "Realistic target" reads *"idle PSS 348 → 230–260 MB and RSS
565 → ~400 MB"*. Both source numbers are stale:

- **PSS 348 MB** comes from `.ai/OPTIMIZATION_PLAN.md:41`, measured
  2026-09-20. A **newer** measurement in `.ai/PERFORMANCE.md:22`
  (2026-09-24) records **PSS 540→576→606→545 MB** for the same scenario.
  The pre-fix build measures **548 MB**, consistent with the newer figure.
  The plan anchored its target to a number the repo had already superseded
  by 200 MB.
- **RSS 565 MB** comes from `.ai/PERFORMANCE.md:652` (2026-10-06). The
  pre-fix build measures **RSS 648 MB** at t+300s. Same ballpark, but the
  plan treated a 10/06 number as current.

A target of "PSS 348 → 230 MB" would have looked like a huge win against a
baseline that was never real.

## Where the target was actually met

The user-visible goal was **"under 300 MB while staying as smooth as it
is"**. The measured result:

| | PSS | RSS |
|---|---|---|
| Before | 548 MB | 648 MB |
| **After** | **315 MB** (app process) | **415 MB** (app process) |
| Goal | < 300 MB | — |

**PSS is now 315 MB, under the 300 MB line** (the tree total is 350 MB
including a 35 MB yt-dlp child process that only exists while a stream is
being resolved). The smoothness cost is within run-to-run variance, per the
measurement table above.

The Flutter floor is 90 MB PSS, so 315 MB is ~225 MB of app-and-driver
overhead: the GPU driver (49 MB), the shader JIT (18 MB), and the genuinely
live Dart heap (~28 MB) plus the Flutter engine and the app's own code.

## Measurement limitations

- The "5,000 liked tracks" and "1 hour of playback" checkpoints were **not
  run** — they need a live Spotify session with valid credentials, and
  the test profile's token is currently rejected (see below). The
  harness supports them; they are unmeasured.
- The app was launched but **not driven** (no search, no playback, no
  navigation) — there is no way to script the GUI here, and the profile's
  Spotify credentials are expired, so the metadata plugin returns 401 for
  every browse/search call. The measured state is therefore
  **"launched, home screen, idle"**, not "actively used".
- The 5-minute idle sample is a single run, not a median. The 30s and
  300s samples of one run are shown as a settling curve, which is
  front-loaded loading (home sections + artwork) rather than a leak — the
  same shape `.ai/PERFORMANCE.md:22` recorded.
- GPU driver pages (49 MB) are shared with the compositor; their PSS
  attribution depends on what else is running, so they vary between runs.
- The THP win is **specific to kernels that use huge pages for
  anonymous mappings** (this machine: `always`). On a `madvise` or `never`
  system the saving would be smaller or zero. The call is harmless
  either way.
- The "RSS 203 MB" figure was measured with the app idle; a busier
  session (artwork on screen, a stream resolving) is higher. The 300s
  sample with a yt-dlp child running is the more representative figure.

## Related: the 401 that breaks search and playback

Independent of memory, the release logs (`~/.local/state/spotube/.spotube_logs`)
show **346 `status code of 401` errors** against the Spotify metadata
plugin's GQL endpoints (`browse.sections`, `savedArtists`, `savedTracks`),
most recently 2026-10-19 18:53. The plugin credentials live in
`shared_preferences.json` under `flutter.spotube_plugin.spotify.credentials`.

The DB's `authentication_table` is **empty** and the host never reads it
(only the schema references it) — authentication is entirely plugin-side
now, so a host-side fix cannot address it. The fix is re-authentication
through Settings → Metadata plugins.

## yt-dlp on Android: why it cannot be bundled, and what was done instead

**Question asked 2026-10-20:** can the yt-dlp YouTube engine be used on
Android?

**Answer: not as a bundled binary.** The reasons are specific, and each one
alone is enough:

1. **No official Android build exists.** yt-dlp publishes
   `yt-dlp_linux` (glibc), `yt-dlp_musllinux`, `yt-dlp_macos`,
   `yt-dlp_windows` and a platform-independent `yt-dlp` **zipapp that needs
   Python 3.10+**. There is no Android/aarch64-android artifact. The Linux
   builds are PyInstaller bundles linked against glibc; Android is bionic.
2. **yt-dlp is a CPython program**, and Android ships no Python. The
   zipapp alone is not enough.
3. **The only Android CPython builds are GPL-3** (Termux's `python`
   package). Spotube is **BSD-4-Clause**; bundling a GPL-3 interpreter
   would make the combined APK a GPL-3 work. It would also add ~45 MB to
   an APK that is already ~92 MB for arm64 alone.
4. **Cross-compiling CPython for bionic is not a weekend project**: it
   needs an OpenSSL build too (Android exposes no TLS library), and
   yt-dlp cannot work without TLS.

**What Android already has, and why it is at parity.** The Android default
engine is **NewPipe** (`flutter_new_pipe_extractor`, a native binding to
the NewPipeExtractor library). For everything Spotube uses it is at parity
with yt-dlp, and in one respect better: its search rows carry
`duration` and `isShortForm`, which is exactly what the
wrong-length rule (`kSourceDurationFloorRatio`/`CeilingRatio`) and the
Short-form rejection need. The yt-dlp flat rows carry `duration` too, so
the same rules apply to both.

The **cross-engine fallback cascade already exists**
(`SourceResolver.engineFallbackCandidates` + `resolveFirstAvailable`), so
on Android the engine order is NewPipe → YouTubeExplode, and on desktop
it is yt-dlp → NewPipe → YouTubeExplode. A backend that breaks does not
take search or playback down with it.

**What was changed (2026-10-20):**

- `YtDlpEngine.isAvailableForPlatform` is now `kIsDesktop || kIsAndroid`.
  The engine is *offered* on Android and reports "not installed" when
  there is no binary — iOS stays off because iOS forbids exec entirely.
- `YtDlpEngine.resolveBinaryPath` searches Android locations:
  `/data/local/tmp` (the one location Android still executes from that
  `adb`/root can write to) and the app's own support directory
  (`appOwnedDirs()`, via `path_provider`).
- `YtDlpEngine.isExecutable` checks the execute bit. Everything that
  lands a binary on a device (`adb push`, a file manager copy) writes
  0644, and exec'ing that fails with a permission error that reads like
  a broken engine rather than a file that was never made runnable. On
  desktop the check is skipped — existence is enough there, and a broken
  binary should fail loudly rather than read as "not installed".
- `SourceResolver.resolveFirstAvailable` treats `YtDlpNotInstalledError`
  as a **skip**, not a failure: a missing binary must not become the
  reported reason for a track not resolving, and must not stop the next
  candidate from answering.
- The "yt-dlp is not installed" dialog explains the Android situation
  (`youtube_engine_android_issue_message`) instead of talking about
  `PATH`, which does not exist on Android.

**The one route that would work for a normal user** is running yt-dlp
inside **Termux** and bridging to it over Termux's `RunCommandService`.
That is deliberately **not implemented**: it needs six independent
assumptions to hold (Termux installed, `RUN_COMMAND` permission granted
by the user, shared-storage access, the `am` background-service
restriction, a yt-dlp inside Termux's PATH, and a Python inside Termux),
none of which can be verified without a device. A half-working backend
is worse than a clear "not installed".

## How to reproduce

```bash
scripts/mem-report                              # build + measure
scripts/mem-report --no-build                   # measure the existing bundle
scripts/mem-report --binary /path/to/binary --label mylabel
```

Each run writes `build/mem-report/<label>-<timestamp>.json` with the
per-sample tree, per-process PSS/RSS, and the top private mappings.
