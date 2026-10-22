# Spotube Theme Work — Session File

Living state for the Caelestia shell-theme project. Everything below is
current as of 2026-09-13 evening; run the launcher to resume.
Sandbox left RUNNING (PID 115300 at save time) — `launch-*.sh kill` to stop.

## Quick resume

```bash
/home/adamya/projects/launch-spotube-sandbox.sh run     # kill + fresh launch
/home/adamya/projects/launch-spotube-sandbox.sh status  # proc, theme, cache, scheme
/home/adamya/projects/launch-spotube-sandbox.sh rebuild # build + launch
/home/adamya/projects/launch-spotube-sandbox.sh kill    # stop
```

Then in the sandbox app: Settings → Metadata Plugins → upload
`/home/adamya/projects/spotube-theme/dist/caelestia-1.2.0.smplug` →
Theme tab → Set default theme.

Or, without the upload dialog:

```bash
fvm dart run tools/install.dart -t caelestia-theme --select
```

## Sandbox layout

- Profile: `/tmp/spotube-bench-home` (DB, config, cache — scratch)
- Live Caelestia state: symlinked `…/.local/state/caelestia → ~/.local/state/caelestia`
  (reads + inotify follow the link; everything else stays isolated)
- Log: `/tmp/spotube-bench-app.log`
- Scratch DB: `…/.local/share/oss.krtirtho.spotube/db.sqlite`
- Scratch prefs (theme cache keys): `…/shared_preferences.json`
- Real DB/profile: never touched (verified repeatedly)

## Theme repo (`/home/adamya/projects/spotube-theme/`)

A git repo of theme plugins with its own toolchain. The theme side of the
contract (schema, validator, fixtures, sample themes) lands here first; the
app implements against it second.

- `themes/<id>/theme.ht` — source (static fallback palettes + glass values +
  `shell` markers; no file reads, no extraction)
- `themes/<id>/plugin.json` — abilities `["theme"]`, entryPoint
  `CaelestiaTheme`; `themes/<id>/build.json` — where the built artifact is
  published (the install URL in the README points there)
- `tools/build.dart` — compile → run → validate → package → `dist/index.json`
  (`fvm dart run tools/build.dart`, `--check`, `--watch -t <id>`)
- `tools/validate.dart`, `tools/inspect.dart`, `tools/install.dart`,
  `tools/export.dart`
- `lib/validator.dart` + `lib/v3_validator.dart` — the payload rules
- `schemas/theme.v2.schema.json` (frozen), `schemas/theme.v3.schema.json`
  (draft), `conformance/` (goldens + broken fixtures + the v3 kitchen sink)
- `sdk/palette.ht` (seed → both schemes), `sdk/defaults.ht` (neutral palette
  + merge)
- `dist/<id>-<version>.smplug` — build outputs (committed)
- `dist/legacy/` — artifacts that predate the toolchain (plain 1.0.0,
  glassier 1.1.0/1.2.0, the pre-unification base); kept byte-for-byte
  because the app's pinned artifact tests point at them
- `caelestia-plain` — same colors as the glass theme,
  `'background': {'source': 'none'}`: the plugin-side opt-out of the desktop
  backdrop and of the terminal-derived glass (pinned by
  `test/caelestia_plain_theme_test.dart`)

The build runs the theme before packaging it, so a theme that returns nothing
or a color the app cannot parse fails here instead of on screen. The old
`compile_plugin.dart` needed the app's package config; the toolchain has its
own `pubspec.yaml` and needs nothing from the app checkout.

`make build`, `make check`, `make test`, `make conformance` wrap the same
commands.
- Current glass values: surfaces `{0.65, 30}`, background
  `{shell, 0.55, 45, #B3FFFFFF}`, radius `{8, 14, 20, 999}`, density `1.0`

## Host architecture (all in `/home/adamya/projects/spotube`, uncommitted)
- Protocol `lib/models/metadata/theme.dart`: 17-role `ThemeColors`,
  `surfaces`, `background(none|albumArt|shell)`, `ThemeRadius`,
  `density` (parsed, unwired), `dynamic(albumArt|shell)`. Frozen.
- Pipeline: Hetu `.smplug` → `theme.getTheme()` → sanitize (clamps) →
  `themeDefinitionProvider` → `resolveThemeDefinition` (shell palette
  merged, rendering stays plugin-owned) → `ThemeConverter` → shadcn
  `ThemeData`. Errors logged, never silent.
- Renderer: `theme_background/` (layer, scope, image provider,
  `ThemeShellSource` + `CaelestiaShellSource`), `theme_surfaces/`
  (tint-only `CardTheme`), `theme_caelestia/` (state dir, scheme reader,
  mode-aware: active side Caelestia, other side built-in slate).
- Live refresh: directory watchers (atomic-save safe) → separate scheme /
  wallpaper signals → provider recompute. Manual: notifier
  `refreshThemeDefinition()`.
- Startup: stale-while-revalidate theme cache (plugin identity keys;
  shell mtime recorded but not gating) → themed first paint; in-app
  branded splash (logo + themed bg, reactive hide, 6s cap) because native
  splash has no Linux branding. Splash carries its own Directionality and
  dispatcher brightness (renders above ShadcnApp — no app widgets exist
  there; forgetting this yields the red error screen).
- Pre-first-frame diet: NewPipe/Discord/yt-dlp-binary/localNotifier init
  deferred post-first-frame (`_initDeferredServices`); engine boot
  (~660ms debug) dominates the remaining black window — release builds
  shrink it further. Not sandbox-specific.
- Integration: Phase 1 semantic remaps (13 files), Phase 2 derived charts,
  hybrid lyrics (`hasArtwork`), adaptive veil (white light / black dark),
  background-role scaffolds. Brand/status/scrims deliberately preserved.

## Proven facts (don't re-prove)

- Hetu plugins cannot read files (bindings audited + runtime probe).
- Caelestia saves `scheme.json` atomically → must watch the directory,
  matching move-destination events.
- `scheme.json` hex has no `#` prefix; overlay/tint accept `#AARRGGBB`.
- `XDG_STATE_HOME` redirect hides shell state → the symlink is required.
- Provider prunes DB rows whose extraction files are missing (reinstall
  after wiping the profile).
- `theme_mode=system` follows OS brightness, not Caelestia mode (open item).

## 2026-10-06 — plugin-driven transparency + 1.1.0 flags (live)

- Host gate is now plugin-driven (strict): real transparency needs the
  theme's explicit `'transparent': true`; absent/null → opaque; the Settings
  switch is a user opt-out ("Allow real transparency", fresh installs
  default on, no DB migration). Fake (painted) backdrop is what you get
  whenever real is off or unrequested — plugin's choice, host no longer
  forces it via a master switch.
- `caelestia_theme.ht` (base) and `caelestia_theme_plain.ht` gained
  `'transparent': true`; manifests bumped 1.0.0 → 1.1.0; rebuilt
  `caelestia-plugin.out`, `caelestia-plugin-plain.out` and packaged
  `caelestia-theme-1.1.0.smplug`, `caelestia-plain-1.1.0.smplug` (old
  smplugs kept). Plain is now the ideal real-transparency theme
  (`source: none` + flag = compositor is the ground, no veil ever).
- Verified live: Plain 1.0.0 (unflagged installed copy) + allow ON renders
  opaque stock — strict gate holds; flagged 1.3.0 + allow ON is real.

## 2026-10-06 — 1.3.0 transparency tuning (installed, live)

- Real window transparency in the host is FIXED (was rendering black:
  runner never called `fl_view_set_background_color`; now `#00000000`).
- New `caelestia_theme_v130.ht` (from glassier) + `caelestia-plugin-v130.json`
  (version 1.3.0) → `caelestia-plugin-v130.out` → `caelestia-shell-1.3.0.smplug`.
- Only value change vs 1.2.0: `surfaces.opacity` 0.55 → 0.75 (in transparent
  mode the host zeroes in-app blur and skips the veil, so cards sit over the
  live desktop; 0.55 washed out over bright wallpaper). bg block, colors,
  geometry untouched; `transparent: true` kept.
- Installed in real profile (extraction dir + plugins_table row, 1.2.0
  deselected, theme cache key bumped to 1.3.0); verified live via screenshot.
- Caveat: live Caelestia glass currently overrides surfaces.opacity to 0.85
  (host mergeShellPalette), so 0.75 only rules when shell glass is absent.

## Open / deferred

- Visual gates needing eyes: Phase 2 charts, lyrics hybrid states.
- Deferred: async IO refactor, density/radius-scale wiring, typography,
  Caelestia-mode-following, upstream PR shaping.
- Tuneables (plugin-only rebuilds): veil alpha, opacities, blur radii.

## Splash customization (complete)

- `lib/modules/splash/`: `splash_screen.dart` (none/fade/scale/slide
  presets, duration, themed bg, custom logo/bg files incl. animated
  GIF/WebP), `splash_prefs.dart` (SharedPreferences, no DB migration).
- Settings → Appearance section: animation, duration, themed toggle,
  logo/background pickers (file_picker, copied to app support dir).
- Gate: hides the moment a themed frame is ready (no minimum hold),
  6s safety cap. Warm starts paint themed near-instantly from cache.
- Full `flutter test` suite has 2 PRE-EXISTING failures (template
  counter test without ProviderScope; stale drift schema_v1) — proven
  on pristine tree, unrelated to theme work.
