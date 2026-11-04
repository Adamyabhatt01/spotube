# Spotube Theme Work — Session File

Living state for the theme subsystem. Current as of 2026-11-04. This file is a
resume point, not the contract: `AUTHORING.md`, the schemas and the source win
when they disagree.

## Current state

- **v4 is the current contract.** `specVersion: 4` is required for the v4
  surface; v2 payloads (no `specVersion`) still load as a palette;
  `specVersion: 3` is rejected with `specVersion 3 is not supported; migrate to
  4` and has one migration path, `themes/tools/migrate_v3.dart`.
- **Phases 0–10 are committed** at `0fe2d4d5` (`feat(theme): v4 phase 10 — …`):
  spec/validator, kits and layout nodes, inputs/overlays, render points, data
  display, bindings/palette, shell regions, routed pages, library mutations,
  context menus, host widgets, theme settings, install/uninstall and the
  active-theme fallback.
- **Phase 11 is committed** (2026-11-04), the final phase: the reference
  theme, conformance fixtures, migration evidence, the runtime v3 gate,
  performance measurements and the doc pass. See `.ai/TODO.md` and
  `.ai/AUDIT_STATE.md` for the evidence table.
- **Reference theme:** `themes/spotify-shell-v4`. Its golden is
  `conformance/spotify-shell-v4.json` (v4, 0 errors/0 warnings); its test is
  `themes/test/spotify_shell_v4_test.dart`. Host render tests
  (`test/theme_ui_document_test.dart`, `theme_ui_host_test.dart`,
  `theme_ui_node_test.dart`, `spotify_theme_payload_test.dart`) read the same
  golden/archive. The v3 `spotify-shell` remains published at its 1.1.0 URL.
- **New v4 surface exercised there:** a theme-owned aside (`layout.aside:
  theme`, `aside.content`), a routed Audio page (`pages` + `ui.pages` +
  `page.audio` under `settings`), six `@palette.*` tokens and the
  `setBass`/`setTreble` audio actions.
- **Runtime v3 gate:** `sanitizeThemeDefinition` drops a v3 payload's inline
  tree (its colours survive) and `themeUiProvider` refuses before calling
  `pluginThemeUiProvider`, so a v3 theme's `getUi()` never runs. The active
  theme's card says `theme_contract_too_old` instead of silently reverting.
- **Debug instrumentation:** `getUi`/`onUiAction` counters live at the plugin
  endpoint (`lib/services/metadata/endpoints/theme.dart`), are debug-only via
  `kDebugMode`, and show in the binding overlay as
  `getUi N · onUiAction M`.
- **Untracked user work, not part of Phase 11:** `themes/themes/neon-cabinet`
  and `themes/themes/neon-maximalist` (with their goldens/tests) are newer and
  currently stale — they fail `build`, `conformance` and `schema` tests. Do not
  stage or "fix" them as part of the Phase 11 commit.

## Quick resume

The theme toolchain lives in this checkout (`themes/`); the standalone
`spotube-theme` repository is an archive.

```bash
cd themes
fvm dart pub get

fvm dart run tools/build.dart -t spotify-shell-v4   # compile/validate/package
fvm dart run tools/build.dart --check               # validate every theme
fvm dart test                                       # contract suite
fvm dart analyze

# install the built reference theme into a scratch profile and select it
fvm dart run tools/install.dart -t spotify-shell-v4 \
  --profile /tmp/spotube-v4-profile --select

# remove it again
fvm dart run tools/install.dart -t spotify-shell-v4 \
  --profile /tmp/spotube-v4-profile --uninstall --version 1.0.0
```

`make build`, `make check`, `make test` and `make conformance` wrap the same
commands. In the app: **Settings → Metadata plugins** installs a `.smplug` and
the **Theme** tab selects it; the trash button removes files, row, settings and
warm-start cache, and deleting the active theme returns to the built-in shell.

Performance:

```bash
fvm flutter build linux --release
DISPLAY=:1 scripts/mem-report --no-build --label <name>
```

## Repo layout (current)

```
themes/<id>/theme.ht        Hetu source; one theme per directory
themes/<id>/plugin.json     manifest the app installs (name/author identity)
themes/<id>/build.json      where the artifact is published
themes/<id>/assets/         optional files shipped inside the .smplug
sdk/                        shared Hetu source (palette/defaults)
lib/                        validators, v3→v4 migration, installer library
tools/build.dart            compile → run → validate → package → index
tools/validate.dart         validate a payload file
tools/inspect.dart          payload of a build; compare two builds
tools/install.dart          install/select/uninstall against a profile DB
tools/export.dart           regenerate conformance/ goldens
tools/migrate_v3.dart       v3 → v4 conversion + report
schemas/                    v2 (frozen), v3 (migration), v4 (current)
conformance/                generated goldens + hand-written fixtures
dist/                       built artifacts (committed)
```

## Verification baseline (Phase 11)

- Host suite: **2,284 passed / 2 skipped / 0 failed** (includes
  `test/theme_v3_rejection_test.dart` 8/8 and the debug-counter test).
- Themes suite: **347/347** at the Phase 11 checkpoint. The untracked neon
  themes were added afterwards and currently account for six failures; run the
  reference/conformance/migration/installer subset to verify Phase 11 without
  them (107/107 last run).
- `fvm flutter analyze` and `themes: fvm dart analyze`: clean.
- `conformance/spotify-shell-v4.json`: v4, 0 errors, 0 warnings.
- Runtime v3 gate: `test/theme_v3_rejection_test.dart` pins both seams and the
  one-`getUi()`-per-session budget.
- Release memory/CPU: see `.ai/PERFORMANCE.md` — "Theme v4 cost (2026-11-03)".
  Idle CPU 0.2–0.4% (budget ≤30%), theme load ~1–2 ms of Hetu work (budget
  ≤300 ms cold), theme cost ≈+22 MB PSS; the ≤330/≤420 memory budget is
  missed by the unthemed build too, so it is recorded as missed.
- Both release targets were green: `fvm flutter build linux --release` and
  `make apk-arm64` (115.1 MB arm64-v8a stable APK).

## Open items

- Rebuild the untracked neon themes' goldens/payloads if that work resumes
  (`neon-maximalist` currently has a decimal `background.scale`, which the
  contract rounds with a warning, and both goldens are stale). Out of scope
  for the Phase 11 commit.
- Manual smoke test of the reference theme on a signed-in desktop session
  (aside, Audio page, palette accents); not claimed yet.
- Frame time with the theme shell, Android memory and the
  artwork-palette extraction cost remain unmeasured (no device/AVD here).
- Phase 11 is committed; the uncommitted voice/player work and the neon
  themes are separate and deliberately untouched.

## Historical notes (pre-v4)

The sections below are the state of the older Caelestia/shell-theme work and are
kept for provenance. Paths and provider names may have moved.

## Host architecture (as of 2026-09)

- Protocol `lib/models/metadata/theme.dart`: 17-role `ThemeColors`,
  `surfaces`, `background(none|albumArt|shell)`, `ThemeRadius`,
  `density`, `dynamic(albumArt|shell)`.
- Pipeline: Hetu `.smplug` → `theme.getTheme()` → sanitize (clamps) →
  `themeDefinitionProvider` → `resolveThemeDefinition` → `ThemeConverter` →
  shadcn `ThemeData`.
- Renderer: `theme_background/` (layer, scope, image provider,
  `ThemeShellSource` + `CaelestiaShellSource`), `theme_surfaces/`,
  `theme_caelestia/` (state dir, scheme reader, mode-aware).
- Live refresh: directory watchers (atomic-save safe) → separate scheme /
  wallpaper signals → provider recompute. Manual: notifier
  `refreshThemeDefinition()`.
- Startup: stale-while-revalidate theme cache (plugin identity keys) →
  themed first paint; in-app themed splash with a 6s cap.
- Pre-first-frame diet: NewPipe/Discord/yt-dlp-binary/localNotifier init
  deferred post-first-frame (`_initDeferredServices`).

## Proven facts (don't re-prove)

- Hetu plugins cannot read files (bindings audited + runtime probe).
- Caelestia saves `scheme.json` atomically → must watch the directory,
  matching move-destination events.
- `scheme.json` hex has no `#` prefix; overlay/tint accept `#AARRGGBB`.
- `XDG_STATE_HOME` redirect hides shell state → the symlink is required.
- Provider prunes DB rows whose extraction files are missing (reinstall
  after wiping the profile).
- `theme_mode=system` follows OS brightness, not Caelestia mode.

## 2026-10-06 — plugin-driven transparency + 1.1.0 flags (live)

- Host gate is plugin-driven (strict): real transparency needs the theme's
  explicit `'transparent': true`; absent/null → opaque; the Settings switch is
  a user opt-out.
- `caelestia_theme.ht` (base) and `caelestia_theme_plain.ht` gained
  `'transparent': true`; manifests bumped 1.0.0 → 1.1.0.
- Verified live: Plain 1.0.0 (unflagged) + allow ON renders opaque stock;
  flagged 1.3.0 + allow ON is real.

## 2026-10-06 — 1.3.0 transparency tuning (installed, live)

- Real window transparency in the host is fixed (the runner now sets
  `fl_view_set_background_color` to `#00000000`).
- `caelestia-shell-1.3.0.smplug`: only `surfaces.opacity` changed
  (0.55 → 0.75) for readable cards over a live desktop.
- Caveat: live Caelestia glass currently overrides `surfaces.opacity` to 0.85
  (`mergeShellPalette`), so 0.75 only rules when shell glass is absent.

## Deferred / not re-opened

- Visual gates needing eyes: Phase 2 charts, lyrics hybrid states.
- Deferred: async IO refactor, density/radius-scale wiring,
  Caelestia-mode-following, upstream PR shaping.
- Tuneables (plugin-only rebuilds): veil alpha, opacities, blur radii.
- Splash customization is complete (`lib/modules/splash/`, Settings →
  Appearance; themed splash with a 6s safety cap).
