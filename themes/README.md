# Spotube Theme Plugins

> **Now part of the app repository.** These sources, the contract, and the
> tooling live in `themes/` here, so the contract's tests and the artifacts
> they pin are always in the same checkout — the app's tests read
> `themes/dist/` directly, and CI builds every theme on every change to this
> directory. The standalone repository this was lifted from
> (`Adamyabhatt01/Caelestia-theme-plugin-spotube`) stays as an archive.

Theme plugins for Spotube: the sources, the payload contract they have to
satisfy, and the tooling that turns a source file into an installable
`.smplug`.

A theme plugin is a Hetu program that answers one question — *what should the
app look like?* — with a JSON payload. The app reads that payload, sanitizes
it, and draws itself from it. This repository owns the payload side of that
contract.

| Theme | Difference | Install URL |
| --- | --- | --- |
| `caelestia` | Matches the active Caelestia shell scheme: glass surfaces, shell background, dynamic Material colour | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/caelestia/plugin.smplug` |
| `caelestia-glassier` | Thinner surfaces than the base theme: more transparency, more blur, a lighter veil over the shell background | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/caelestia-glassier/plugin.smplug` |
| `caelestia-shell` | The glassier backdrop with more opaque surfaces, so text survives a bright wallpaper | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/caelestia-shell/plugin.smplug` |
| `caelestia-plain` | The base palette with no desktop backdrop and no shell-derived glass | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/caelestia-plain/plugin.smplug` |
| `spotify-shell` | A Spotify-shaped shell instead of the Caelestia one: black and green, inset content, labelled sidebar, a full-width seek line with elapsed and total time below the transport, Inter | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/spotify-shell/plugin.smplug` |
| `obsidian` | A pixel-Minecraft theme: black amethyst and lavender end stone, a stage player and a record that turns with the track | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/obsidian/plugin.smplug` |

### Which one should you install?

| Theme | Choose it if… |
| --- | --- |
| `caelestia` | You want the safe, conservative Caelestia look. Surfaces at 65%, a 70% white veil over the wallpaper: readable, and the wallpaper still shows. **Start here.** |
| `caelestia-glassier` | You want maximum glass — the most desktop showing through. Surfaces at 55% and a 40% veil. Best on a dark wallpaper; text can wash out on a bright one. |
| `caelestia-shell` | You want the glass look but readable text. The glassier backdrop with surfaces at 75%. **Best with real transparency on.** |
| `caelestia-plain` | You want no wallpaper and no veil at all — a flat, quiet surface. With real transparency on it is completely clear. |
| `spotify-shell` | You want Spotube to look like Spotify rather than like your desktop shell. Works on every platform. |
| `obsidian` | You want a pixel-art player with a stage layout and a record for a player, in two schemes. Ships its own OFL fonts, so it looks the same everywhere. |

Under real window transparency (Linux, with the host setting on) the wallpaper
and its blur are not painted at all: the veil decides how much of the desktop
shows through — about 30% for `caelestia`, 60% for `caelestia-glassier` and
`caelestia-shell`, and everything for `caelestia-plain`. `spotify-shell` does
not ask for transparency and stays opaque.

The Caelestia themes need the [Caelestia shell](https://github.com/caelestia-dots/shell)
for the live wallpaper and palette; without it you still get the static
palette, the glass and the layout. `spotify-shell` and `obsidian` need nothing
but the app.


## Requirements

**A Spotube build that supports the `theme` plugin ability — this fork
([Adamyabhatt01/spotube](https://github.com/Adamyabhatt01/spotube)), not
upstream release builds.** Upstream has no theme plugin API, so installing an
`.smplug` there would do nothing.

The shell-sync half needs the [Caelestia shell](https://github.com/caelestia-dots/shell)
itself (Linux). Without it the plugin still works — you just get the static
palette.

## Install

1. Spotube → **Settings → Metadata plugins** → paste one of the URLs above →
   install. A local `plugin.smplug` works too (the file picker accepts
   `.smplug`).
2. **Settings → Metadata plugins → Theme** tab → set it as the default theme.

Re-installing after a version bump replaces the entry, since Spotube
identifies a plugin by **name and author**.

## Layout

```
themes/<id>/         one theme: theme.ht (source) + plugin.json (manifest)
                      + build.json (where the artifact is published)
                      + assets/ (optional, shipped inside the archive)
sdk/                 shared Hetu source a theme can include
lib/                 the validator, the palette SDK's host side, the installer
tools/build.dart     compile → run → validate → package
tools/validate.dart  validate a payload file
tools/inspect.dart   print a built theme's payload, compare two builds
tools/install.dart   install a built theme into a Spotube profile
tools/export.dart    write each theme's payload to conformance/
tools/preview.dart   render a payload and its assets to one standalone HTML file
dist/                built artifacts (committed)
dist/legacy/         artifacts that predate the toolchain, kept as-is
conformance/         golden payloads used by the tests
schemas/             the payload contract: v2 (frozen), v3 and v4
.github/workflows/   the build, the tests and the goldens on every push
```

## Commands

```bash
fvm dart pub get

fvm dart run tools/build.dart            # build every theme into dist/
fvm dart run tools/build.dart --check    # validate only, write nothing
fvm dart run tools/build.dart -t spotify-shell
fvm dart run tools/build.dart --watch -t spotify-shell

fvm dart run tools/inspect.dart -f dist/caelestia-1.2.0.smplug --json
fvm dart run tools/inspect.dart -f old.smplug -f new.smplug   # same payload?

fvm dart run tools/export.dart           # regenerate the golden payloads
fvm dart run tools/preview.dart obsidian   # write dist/preview/obsidian.html
fvm dart run tools/install.dart -t caelestia --select

fvm dart test                            # the contract's tests
```

`build.dart` runs the theme before it packages it. A theme that compiles but
returns nothing — or returns a color the app cannot parse — is a build
failure here, not a user's blank app. Builds are byte-reproducible: the Hetu
compiler's timestamp is pinned, so two builds of the same source produce
identical archives.

## Preview a theme

```bash
fvm dart run tools/export.dart
fvm dart run tools/preview.dart obsidian
```

The second command writes `dist/preview/obsidian.html`: one file, no network,
with the fonts, icons, album tile and both schemes inlined. It shows the
palette, every component sample, the theme's screens, and the stage if the
theme has one. Open it in a browser; the top bar switches scheme and
play/pause, and the URL carries the state (`#mode=light`,
`#screen=palette`, `#screen=now-playing`, `#screen=colophon`).

The preview reads the same payload as the host, but it is still
obsidian-shaped: its sample track, pixel styling and font allow-list assume
that theme, and it does not draw `home.content` or `list` nodes. Use it to
review obsidian or a stage-based theme; for any other theme the app is the
reference renderer (`fvm flutter run -d linux` with the theme selected).

## The themes

| Theme | What it is |
|---|---|
| `caelestia` | Matches the active Caelestia shell scheme — published |
| `caelestia-glassier` | The same, with thinner surfaces — published |
| `caelestia-plain` | The base palette with no backdrop and no glass — published |
| `caelestia-shell` | The balanced variant: readable text over a bright wallpaper — published |
| `spotify-shell` | A Spotify-shaped shell: black and green, inset panel, labelled sidebar, a full-width seek line with elapsed and total time below the transport, per-row downloads, a search empty state, Inter, its own page bodies — published |
| `obsidian` | A pixel-Minecraft theme: black amethyst / lavender end stone, OFL fonts, pixel icons, a stage player and a turning record — published |
| `minimal` | The SDK in nine lines: one seed colour |
| `brand-demo` | The whole v3 payload, including a slot and a screen |
| `ui-demo` | A theme that answers with its own UI (`getUi()`, `onUiAction()`) |
| `asset-demo` | A theme that ships an image and points at it |
| `kitchen-sink` | Every field the v3 payload has, in one theme |

## The payload

`getTheme()` returns a map. `specVersion: 4` is the approved contract; a
payload with no `specVersion` is v2. `specVersion: 3` is rejected by the v4
host and must be migrated (see below). The fields the contract defines:

| Field | Meaning |
|---|---|
| `specVersion` | `4` for the v4 payload, `2` when omitted; `3` is rejected with a migration message |
| `light`, `dark` | 17 required color roles each: `background`, `foreground`, `card`, `cardForeground`, `primary`, `primaryForeground`, `secondary`, `secondaryForeground`, `muted`, `mutedForeground`, `accent`, `accentForeground`, `destructive`, `destructiveForeground`, `border`, `input`, `ring`; plus the optional v3 roles (sidebar, popover, chart, status) |
| `surfaces` | `opacity` (0..1), `blur` (0..100), `tint` (`#RRGGBB` / `#AARRGGBB`) |
| `background` | `source` (`none` / `albumArt` / `shell` / `asset`), `opacity`, `blur`, `asset`, `tile`, `scale`, `overlay`, `transparent` |
| `radius` | `small`, `medium`, `large`, `pill` |
| `density` | 0.7..1.5 — one number for the whole UI's size |
| `tokens` | `cardWidth`, `cardHeight`, `artistCardWidth`, `artistCardHeight`, `gutter`, `fontFamily` |
| `layout` | `chrome`, `nav`, `progress`, `player`, `enforce`, `navItems`, `navbarItems`, `libraryItems`, `home`, `settings`, `titlebar`, `splash`, `sidebar`, `sidebarWidth`, `aside`, `asideWidth`, `shell`, `pinTargets`, `responsive` |
| `typography`, `spacing`, `motion`, `scale`, `icons` | The v3 presentation blocks the host applies: font ladder and role colours, page padding and card gaps, animation durations and curves, scale multipliers, icon sizes |
| `components`, `branding`, `assets` | The host draws the `player` component group and the `card`/`buttons` overrides used by UI nodes; branding drives the window title, wordmark and about text; assets resolve theme-shipped images |
| `ui` | The theme's own UI tree: `specVersion`, `slots`, `screens`, `templates`, `renderPoints` |
| `ext` | Theme-owned extension data; the host ignores it |

Rules that are not obvious:

- **Colors are `#RRGGBB` or `#AARRGGBB`.** Anything else makes the app throw,
  and a throw there discards the *entire* theme — one typo loses the palette.
- **Every one of the 17 base roles is required** in both `light` and `dark`.
  The v3 roles are optional and fall back to the role they alias.
- **Unknown fields are ignored.** That is what lets a newer theme ship to an
  older app: the app skips what it does not know. `build.dart` reports those
  fields as warnings.
- **Numbers outside the app's range are clamped**, not rejected. The build
  prints the value the app will actually use.
- **`dynamic` is v2-only.** The v3 schema has no `dynamic` block; use
  `background.source` (`none` / `albumArt` / `shell` / `asset`). The validator
  still accepts the legacy key, but nothing in the host reads it.

`schemas/theme.v4.schema.json` is the current contract;
`schemas/theme.v3.schema.json` is kept for the migration tool;
`schemas/theme.v2.schema.json` is frozen and remains supported. `conformance/`
holds the payloads used by the tests. The full v4 specification is
`/home/adamya/.opencode/plan/v4-theme-contract.md`; `AUTHORING.md` documents
the blocks that exist in the tree.

## Authoring a theme

A theme is a Hetu class with a `theme` member that answers `getTheme()`:

```hetu
class SpotifyThemeApi {
  fun getTheme() {
    return {
      'light': { 'background': '#ffffff', /* … */ },
      'dark':  { 'background': '#121212', /* … */ },
      'layout': {'chrome': 'inset', 'nav': 'rail', 'progress': 'below'}
    };
  }
}

class SpotifyTheme {
  var theme = SpotifyThemeApi();
}
```

The manifest (`plugin.json`) names the entry point and declares the abilities:

```json
{"abilities": ["theme"], "entryPoint": "SpotifyTheme", "name": "…", "version": "1.0.0", "author": "…", "pluginApiVersion": "2.0.0"}
```

Shared source goes in `sdk/` and is pulled in with an include directive:

```hetu
//#include "sdk/defaults.ht"
```

## What a theme cannot do

- It cannot read files or the network. The app's Hetu VM has no bindings for
  either; `asset://` paths are resolved by the app, not by the plugin.
- It cannot change the app's package id, launcher name or icon. That is
  build-time branding, not a theme.
- It cannot read a font from an arbitrary path or the network. It can ship one
  as a v3 asset (`kind: font`); the app validates and loads it from the plugin
  archive. A v2 payload still names a family that has to exist on the machine.

## v3

`specVersion: 3` adds four kinds of decision on top of v2: more colour roles
(popover, sidebar, status, charts), tokens (typography, spacing, motion,
scale, icons), component styles, and the shell's composition — plus branding,
assets and a declarative UI tree with slots, screens, bindings and actions.

The contract is written down in `schemas/theme.v3.schema.json` (draft-07,
every node variant), enforced by `lib/v3_validator.dart`, and demonstrated by
`themes/kitchen-sink` — the theme that has to carry every field, so a new field
without an example fails the test suite. v3 payloads are stricter than v2:
unknown node props, bindings, actions, asset paths and icon names fail the
build instead of being ignored.

`themes/obsidian` is the first theme built on the whole contract: two 39-role
schemes, shipped OFL fonts and pixel icons, a tiled background, a stage dock
and a record that turns with the track.

A v2 host ignores all of it, which is what lets a v3 theme ship to an older
app. The **v4 host does not read v3**: it rejects `specVersion: 3` with a
migration message. `AUTHORING.md` is the full reference.

## v4

**v4 is a breaking contract.** It is specified by
`/home/adamya/.opencode/plan/v4-theme-contract.md`; read that file before
authoring a v4 theme. The short version:

- `specVersion: 4` is required. `specVersion: 3` is rejected with
  `specVersion 3 is not supported; migrate to 4`; `themes/tools/migrate_v3.dart`
  produces a best-effort v4 payload and a report. There is no runtime v3
  compatibility layer. v2 payloads (no `specVersion`) remain supported.
- `uiKit` selects the default kit: `shadcn` (default), `material` or
  `cupertino`. A node or `kitScope` may override it. Phases 0–2 ship the
  resolver, the `box`/`grid`/`safeArea`/`aspectRatio`/`kitScope` nodes, and the
  input/overlay set (`slider`, `switch`, `checkbox`, `radioGroup`, `textField`,
  `textArea`, `select`, `segmented`, `tabs`, `menu`, `contextMenu`, `popover`,
  `tooltip`, `dialog`, `sheet`). Material and Cupertino render `button`,
  `progress` and `slider` natively and fall back to shadcn for everything else.
- `capabilities` declares what the theme may use (`library.read`,
  `player.control`, `theme.assets` are defaults; `library.write`,
  `audio.effects`, `ui.pages`, `ui.hostWidgets`, `settings.write`,
  `clipboard.write` are opt-in). Unknown capabilities are errors, and a node
  or action that needs an undeclared capability is an error.
- `layout` gains `sidebar` (`host`/`theme`), `aside` (`none`/`theme`) and
  their widths, plus the `shell` descriptor for rearranging regions. A
  theme-owned sidebar draws through `sidebar.content` and can replace the
  library group with `sidebar.library`; `aside.content` fills the right panel.
  Both regions respond to `toggleSidebar`/`toggleAside` (Ctrl/Cmd+B and
  Ctrl/Cmd+Shift+B) and publish `app.sidebarCollapsed`/`app.asideOpen`.
  `library.local.content` replaces the local-library body and publishes
  `library.folders`/`library.counts`.
- `layout.shell` builds a row/column/stack/grid tree of `content`, `sidebar`,
  `aside`, `player`, `titlebar`, `navbar` and repeatable `custom` regions, with
  px/`%`/`auto` sizes, flex, clamps, `resizable` handles, `collapsible`,
  `hiddenWhen`, safe areas and per-breakpoint trees. Exactly one `content`
  mounts the router outlet; custom regions require `id`, `slot` and `label`.
  A malformed tree falls back to the legacy shell. `layout.pinTargets` declares
  pin destinations; `library.pinTargets` publishes them, `library.pins` entries
  carry `target`, and `pinItem`/`unpinItem` accept one.
- `pages` declares routed theme pages under host sections; `ui.screens` stays
  for overlays.
- `ui.renderPoints` replaces the pixels of a host surface without taking its
  behaviour: the closed v4.0 catalogue covers search (field, dropdown, rows,
  groups, empty/loading/recent) and `contextMenu.item` today; the rest of the
  catalogue is validated and wired when its host surface ships. A point names
  a template; `hostWidget` is forbidden inside one, expansion stops at eight
  levels, and a missing or malformed template falls back to the host default
  with a single diagnostic. See `AUTHORING.md` for the catalogue and the
  `search.*` / `menu.*` / `item.*` / `group.*` context bindings.
- The semantic node set is the plan's full vocabulary (layout, content,
  input, navigation, overlay, data and logic nodes), not the abandoned
  `video`/`group` draft. See plan §4.3.
- Bindings, actions, slots and the closed `hostWidget` registry are the plan's
  lists (§4.5, §4.6, §4.7, §4.9).

The v4 host is at **Phase 5B** (runtime core, kits, layout nodes, inputs,
overlays, render points, data display, bindings/palette, layout regions, and
the shell descriptor with pin targets).
`themes/lib/v4_validator.dart`, `theme.v4.schema.json`, `conformance/draft/v4-kitchen-sink.json` and
`test/v4_*_test.dart` are the current contract and its suite. Inputs read
`bind` and fire `action`/`actions` with `$value`; dialogs and sheets follow
`openBind` and close locally through `dismiss`. `virtualList` and a sticky
`table` virtualize host-side, `list`/`virtualList` can filter a typed binding
without a rebuild per keystroke, and `tree`, `accordion`, `collapsible` and
`carousel` keep their open/page state in the host. `resizable` splits its two
panes and persists the drag size through `storageKey`. The acceptance test for
the finished contract is `themes/spotify-shell-v4`.
