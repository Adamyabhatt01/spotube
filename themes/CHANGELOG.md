# Changelog

The themes and the tool that builds them. The payload contract is versioned
here; the app's reader is versioned with the app.

## 2.3.0 — the node frost, and the schema meets the prop table

`box` and `card` take `blur` (sigma, 0..100) and `blurTint` (the colour laid
over the blur). This is the wallpaper blur handed to one surface: a hero panel,
a player bar, a single card can now sit on the artwork behind it without the
whole window being frosted. `card` gets the pair through `_v4ExtraBaseProps`, so
the v3 tables stay frozen. The host drops the filter rather than keep it mounted
while a scroll is in flight — a zero-sigma `BackdropFilter` still costs a
backdrop pass every frame, which is the bug `.ai/PERFORMANCE.md` records for the
title bar — and keeps the tint, so a frosted panel stays a panel through a drag.
`AUTHORING.md` says plainly that the prop is expensive and that a long list
frosts its container, not each row.

- `test/v4_schema_test.dart` now compares every `uiNode` branch's declared
  props with `v4UiNodeProps`. It found one real hole: the published schema's
  `hostWidget` branch declared neither `id` nor `props` under
  `additionalProperties: false`, so an editor built on the schema rejected the
  only node that mounts a host surface while the validator and the host both
  required it. The branch now lists the widget ids, and a second test pins that
  list to `v4HostWidgetProps.keys` — hand-copying it went three widgets short
  before the pin existed, which is exactly why it is a test and not a comment.
- The same sweep found that no fixture had ever drawn `list.filter`,
  `list.columns` or `progress.style`, three props v4 added to types v3 already
  had. The kitchen sink draws them now, and its prop test requires every v4
  added prop of any type it uses — a prop no fixture draws is a prop nothing
  proves the host reads.
- `conformance/draft/v4-kitchen-sink.json` carries a frosted sidebar panel, so
  the new props are schema-checked in a payload and not only in a unit test.

## 2.2.0 — the last six themes move to v4

Nothing in the catalogue is v3 any more. `asset-demo`, `brand-demo`,
`kitchen-sink`, `obsidian`, `spotify-shell` and `ui-demo` go to **2.0.0** with
`specVersion: 4` and `uiKit: shadcn`, by way of `tools/migrate_v3.dart` — the
report was run, its notes applied to the Hetu source, and the payload rebuilt,
so each golden still is what its theme produces.

This was not cosmetic. The host refuses `specVersion: 3` outright: it nulls the
`ui` block and never asks the plugin for a tree, so all six were drawing their
palettes inside the default shell and telling the user "This theme was built
for an older interface contract" — `obsidian` and `spotify-shell` doing it with
a 15 KB and a 32 KB UI document behind that message. Colours, layout keys, UI
trees and assets are otherwise byte-identical, so nothing else changes.

- `layout.enforce` left four of them. v4 reads presence rather than a claim
  list, so the key that named which parts a theme owned has no meaning; the
  lists themselves stay and are what the host draws.
- `kitchen-sink` and `spotify-shell` each carried one `search` node. It was a
  v3 node the host wired by itself, and the v4 host has no renderer for it, so
  the migration's rename to `textField` alone would have produced a field that
  accepts keystrokes and tells no one. Both are now bound to `search.query` and
  write it back with `setQuery`, which is the path `spotify-shell`'s own
  `search.content` page reads.
- The superseded artifacts moved to `themes/dist/legacy/` and their payloads to
  `themes/conformance/legacy/`. That keeps two things honest: the v3 rejection
  gate and the migration mapper stay pinned against real published payloads
  rather than synthetic ones, and `test/conformance_test.dart` can now require
  every golden to validate through the host's own entry point — a v3 payload
  landing back in `conformance/` fails there instead of quietly taking the
  legacy path.

## 2.1.0 — `dynamic` is a v4 key; the Caelestia themes move to v4

v4 opened by deleting `dynamic` as a v3 escape hatch, but that key was the only
way a theme could say where its colours come from, and the host still read it on
every version. It is restored to the v4 vocabulary: added to `v4TopLevelKeys`
and to `schemas/theme.v4.schema.json`, and `tools/migrate_v3.dart` now carries
`dynamic` through instead of deleting it. No payload resolution changed — the
validator already parsed and re-emitted the block for every version; only the
v4 top-level sweep rejected it.

- `caelestia`, `caelestia-glassier`, `caelestia-plain` and `caelestia-shell` go
  to **2.0.0** with `specVersion: 4` and `uiKit: shadcn`. Their colours,
  surfaces, background (including `overlay` and `transparent`) and `dynamic`
  block are byte-identical to the v2 builds, so the look is unchanged — what
  changes is that they now sit inside the current contract. The superseded
  artifacts moved to `themes/dist/legacy/` and stay pinned by the app's tests,
  so the v2 path keeps its coverage.
- `test/v4_schema_test.dart` now asserts the schema's top-level properties and
  `v4TopLevelKeys` are the same set. The two had no cross-check, which is
  precisely how a contract drifts: an editor would offer a key the build then
  rejects, or hide one it accepts.
- `AUTHORING.md` documents `dynamic` and corrects the `layout.enforce` advice —
  a v4 payload must omit it, since it is not in the v4 `layout` key set.
- `themes/neon-maximalist`: `background.scale` 1.2 → 1.0, the value the host
  already rounded to. `make check` is now silent across the catalogue.
- Three more schema/validator drifts, all found by the new cross-check and by
  the goldens: the published schema did not accept `setting.*` bindings or a
  `button` with `variant: "default"` (both of which the validator and the host
  have supported), and `kitComponents.buttons` lacked the `default` key. A theme
  using any of them built and shipped fine while an editor called it invalid.
- `virtualList` takes `columns` (1..12), the count `list` and `grid` already
  took. Moving a long collection to the recommended lazy node no longer costs
  the grid; the app renders it as rows of equal-width cells, one `itemExtent`
  per row.
- `test/v4_schema_test.dart` now matches every `uiBinding` branch against
  `isV4UiBinding` over a corpus, instead of only checking that a pattern exists.
  That weaker assertion is what let the `setting.*` gap through.

## 2.0.0 — v4, the whole contract

`specVersion: 4` is the current contract and it is breaking: the host rejects
`specVersion: 3` with `specVersion 3 is not supported; migrate to 4`. A v2
payload (no `specVersion`) still loads as a palette. `themes/tools/migrate_v3.dart`
is the only supported v3 path.

- **Kits and layout.** `uiKit` selects `shadcn` (default), `material` or
  `cupertino`; `kitScope` and per-node `kit` override it. v4 adds
  `box`/`grid`/`resizable`/`safeArea`/`aspectRatio`, the input and overlay set
  (`slider`, `switch`, `checkbox`, `radioGroup`, `textField`, `textArea`,
  `select`, `segmented`, `tabs`, `menu`, `contextMenu`, `popover`, `tooltip`,
  `dialog`, `sheet`) and data display (`badge`, `chip`, `avatar`, `skeleton`,
  `spinner`, virtualized `table`/`virtualList`, `tree`, `accordion`,
  `collapsible`, `carousel`).
- **Capabilities.** `library.read`, `player.control` and `theme.assets` are
  implicit; `library.write`, `audio.effects`, `ui.pages`, `ui.hostWidgets`,
  `settings.write` and `clipboard.write` are opt-in. An unknown capability, or
  a binding/action that needs an undeclared one, is a build error.
- **Bindings and palette.** A document scan drives demand, so a theme pays only
  for the provider namespaces it references. `palette.*` and `@palette.*`
  resolve from a URL-keyed artwork palette cache and fall back to the scheme
  role. The v4 validator accepts the six `@palette.*` colour tokens.
- **Shell regions.** `layout.sidebar`/`aside` and their widths, the
  `sidebar.content`/`sidebar.library`/`aside.content`/`library.local.content`
  slots, `toggleSidebar`/`toggleAside`, and `layout.shell` — a
  row/column/stack/grid tree of host regions with px/`%`/`auto` sizes, flex,
  clamps, drag handles, collapsible/hidden-when rules and per-breakpoint trees.
- **Pages, menus, widgets, settings.** `pages`/`ui.pages` route theme pages
  under `sidebar`, `library`, `library.local` or `settings`, each rendering its
  `page.<id>` slot. `ui.menus` appends namespaced `theme.*` rows to host context
  menus without taking over the user's `contextMenu.config` order.
  `ui.renderPoints` replaces host surface pixels while keeping their behaviour.
  `hostWidget` mounts one of twelve host-owned surfaces. `showSettings()`
  renders `settings.content` and persists values per theme as
  `theme.<author>.<name>.<key>`.
- **Install lifecycle.** Manifests are validated before extraction (required
  fields, length caps, path-safe name/author, parseable `pluginApiVersion`), so
  a refused archive leaves no orphan directory. Uninstall drops the version
  directory, row, theme KV namespace and warm-start cache; removing the active
  theme clears `selected_for_theme`, resets the UI and falls back to the built-in
  shell instead of promoting another theme. A row whose version fails the path
  guard is still removable. The CLI mirrors the same field rules.
- **Reference theme.** `themes/spotify-shell-v4` is the v4 acceptance test: the
  Spotify shell plus a theme-owned aside, a routed Audio page, palette tokens
  and audio actions. Its golden is `conformance/spotify-shell-v4.json`
  (0 errors/warnings) and `test/spotify_shell_v4_test.dart` pins the v4-only
  surface. `spotify-shell` stays published at its 1.1.0 v3 URL: a user on it
  keeps its colours and loses its layout until they install
  `spotify-shell-v4`, and the active theme's card in Settings → Metadata
  plugins says so instead of letting the shell silently revert.
- **Migration and conformance.** `tools/migrate_v3.dart` maps v3 to v4, reports
  `renamed`/`removed`/`needs a human`, and validates the result.
  `test/v4_conformance_test.dart` requires a fixture for palette, sidebar,
  inputs, pages and audio. `AUTHORING.md` gained "v4 in one page"; `README.md`
  and the schemas describe the current contract.
- **Debug instrumentation.** `getUi`/`onUiAction` are counted in debug builds
  at the plugin endpoint and shown in the binding overlay, so a per-frame VM
  call would be visible.
- **Verification.** Host suite **2,284 passed / 2 skipped / 0 failed** and
  themes **347/347** after Phase 11, both analyzers clean and both release
  targets green (`fvm flutter build linux --release`, `make apk-arm64`).
  The host suite now
  includes `test/theme_v3_rejection_test.dart`, which pins the runtime gate on
  both seams (`sanitizeThemeDefinition` for the inline tree, `themeUiProvider`
  so a v3 theme's `getUi()` is never invoked) and the §8 "one `getUi()` per
  session" budget. Release measurements are recorded in
  `.ai/PERFORMANCE.md` — "Theme v4 cost (2026-11-03)": idle CPU (0.2–0.4%) and
  theme load (≈1–2 ms of Hetu work) pass §8 with room, the reference theme
  costs roughly +22 MB PSS over an unthemed build, and the idle memory budget
  is missed by **both** builds, which is recorded rather than smoothed over.

## 1.7.0 — the host reads the presentation blocks

The v3 payload already carried a type scale, spacing, motion, scale and icon
ladder. The host now applies them instead of only validating them.

- **Presentation blocks are consumed.** `typography.styles` resolves into
  shadcn's type ladder (missing fields keep the host value; `color` accepts
  `@role`), `icons` into the icon sizes, `scale` into independent size, text,
  radius, icon and spacing multipliers, `spacing` into page/section/card
  padding and `motion` into the durations and easing the UI renderer uses.
  Every number is clamped on read.
- **The kitchen sink exercises the whole contract again.** It now carries the
  `player` component group, a `search` node and `card.hoverBackground`, so the
  reference theme cannot drift behind the validator (22 node variants).
- **`spotify-shell`:** the seek line moved below the transport and now draws
  elapsed/total time, the search page has an empty state, track rows expose a
  download button, and the theme declares its 16/20/24/32 icon ladder. The
  manifest moves 1.0.0 → 1.1.0 so installed copies replace the old payload;
  the build emits `spotify-shell-1.1.0.smplug` and the install copy at
  `themes/spotify-shell/plugin.smplug`.
- **Tests:** 141 in the contract suite, including the kitchen-sink drift
  checks; the app pins the resolved presentation in
  `test/theme_presentation_test.dart`.

## 1.6.0 — obsidian, and a contract you can check

The v3 contract stopped being a draft and became something the build enforces
end to end. `obsidian` is the first theme written against it.

- **The v3 contract is enforced.** Flat node props are canonical; a legacy
  `props: {}` block is merged in with a warning. Unknown props, bindings,
  actions, asset paths and icon names fail the build. `ui.specVersion: 2`
  adds the `animate` node and the `stage` dock; pixel borders and tiled or
  scaled backgrounds are validated too.
- **A real schema.** `schemas/theme.v3.schema.json` is draft-07 with all 19
  node variants. `test/schema_test.dart` validates every golden and the
  kitchen sink against it (the `json_schema` package is draft-07-only).
- **Reproducible builds.** The Hetu compiler's timestamp is normalised to
  `1970-01-01 00:00:00`, so two builds of the same source are byte-identical.
- **`obsidian`**: a pixel-Minecraft theme in black amethyst and lavender end
  stone. 39 roles per scheme, OFL Silkscreen and VT323 fonts, 20 pixel icons,
  a transparent obsidian tile, a stage dock, a record that turns with the track
  and carries its title and artist, plus now-playing and colophon screens.
  Published at `obsidian/plugin.smplug` (~95 kB).
- **`tools/preview.dart`**: turns a built payload and its assets into one
  standalone HTML file with both schemes, the palette, every component
  sample, the screens and the stage. Nothing is fetched at runtime; fonts and
  images are inlined. `#mode=light`, `#screen=palette`, `#screen=now-playing`
  and `#screen=colophon` share a state.
- **Tests**: 20 for the theme (contract, record, contrast, assets, icons) and
  6 for the preview (standalone document, fonts, schemes, stage, tile,
  network-free).

## 1.5.0 — the whole v3 contract

The payload is now complete: everything a theme may decide about the app, in
one schema, one validator and one example.

- **The contract** (`schemas/theme.v3.schema.json`) grew to cover everything
  a theme can decide: the extra colour roles (popover, sidebar, status,
  charts), typography, spacing, motion, scale, icon sizes and overrides, the
  style of every shadcn component the app draws with, the shell's
  composition, branding, the assets a theme ships, and the declarative UI
  tree.
- **`lib/v3_validator.dart`** enforces it: node types, bindings, actions,
  asset paths, the id registries, the depth and size limits, the component
  ranges. A theme that breaks a rule fails the build, not the app.
- **The slot registry** is closed: a theme may only fill a slot the host
  publishes, so a typo cannot silently disappear.
- **`getUi()` and `onUiAction()`** are now part of the plugin contract: a
  theme may answer with its own UI instead of carrying it in the payload, and
  answer a `plugin` action with a new one. `themes/ui-demo` does both.
- **Assets**: a theme's files are packaged with their paths preserved, and
  the build checks that every `asset://` path a theme names is a file it
  ships — and warns about the ones it ships but never uses.
- **`themes/kitchen-sink`** carries every field the schema has, and a test
  says so: a new field without an example fails the suite.
- **CI** runs the analyzer, the tests and the build on every push, and checks
  that the golden payloads are up to date.
- **`tools/install.dart`** was given a library behind it (`lib/installer.dart`)
  and a test: it writes the plugin into a profile and registers it, against a
  real SQLite database.

## 1.4.0 — the toolchain

The repository grew a build of its own, and the themes moved into it.

- `tools/build.dart` compiles a theme, runs it, validates the payload it
  produces and packages it. A theme that returns nothing, or a colour the app
  cannot parse, fails the build instead of the app.
- `tools/validate.dart`, `tools/inspect.dart`, `tools/install.dart` and
  `tools/export.dart`: validate a payload, print a build's payload and compare
  two builds, install a build into a profile, refresh the golden payloads.
- `lib/validator.dart` mirrors the app's rules one-for-one — the seventeen
  required roles, the ranges it clamps, the enums it falls back on — and
  `lib/v3_validator.dart` does the same for the v3 blocks.
- `schemas/theme.v2.schema.json` freezes the payload the app reads today;
  `schemas/theme.v3.schema.json` drafts what comes next.
- `conformance/` holds the payloads that have to keep working: one golden per
  theme, generated; one broken payload per failure mode, hand-written; and
  the v3 kitchen sink.
- `sdk/palette.ht` derives both schemes from one seed colour;
  `sdk/defaults.ht` holds the neutral palette and a merge.
- `themes/minimal` is the SDK in nine lines. `themes/brand-demo` is the v3
  payload in full, including a slot and a screen.

## 1.3.0 — the balanced Caelestia theme

`caelestia-shell` at 75% surface opacity: the desktop still shows through,
and text stays readable over a bright wallpaper. Published as
`caelestia-shell/plugin.smplug`.

## 1.2.0 — the base Caelestia theme

The published `caelestia` theme, with the transparency opt-in the published
copy never had: with the host's transparency setting on, the compositor shows
through instead of a painted backdrop.

## 1.1.0 — the glassier Caelestia theme

Thinner surfaces than the base theme: more transparency, more blur, a lighter
veil over the shell background.
