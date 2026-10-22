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
| `spotify-shell` | A Spotify-shaped shell instead of the Caelestia one: black and green, inset content, rail navigation, seek bar below the player | `https://raw.githubusercontent.com/Adamyabhatt01/spotube/master/themes/spotify-shell/plugin.smplug` |

### Which one should you install?

| Theme | Choose it if… |
| --- | --- |
| `caelestia` | You want the safe, conservative Caelestia look. Surfaces at 65%, a 70% white veil over the wallpaper: readable, and the wallpaper still shows. **Start here.** |
| `caelestia-glassier` | You want maximum glass — the most desktop showing through. Surfaces at 55% and a 40% veil. Best on a dark wallpaper; text can wash out on a bright one. |
| `caelestia-shell` | You want the glass look but readable text. The glassier backdrop with surfaces at 75%. **Best with real transparency on.** |
| `caelestia-plain` | You want no wallpaper and no veil at all — a flat, quiet surface. With real transparency on it is completely clear. |
| `spotify-shell` | You want Spotube to look like Spotify rather than like your desktop shell. Works on every platform. |

Under real window transparency (Linux, with the host setting on) the wallpaper
and its blur are not painted at all: the veil decides how much of the desktop
shows through — about 30% for `caelestia`, 60% for `caelestia-glassier` and
`caelestia-shell`, and everything for `caelestia-plain`. `spotify-shell` does
not ask for transparency and stays opaque.

The Caelestia themes need the [Caelestia shell](https://github.com/caelestia-dots/shell)
for the live wallpaper and palette; without it you still get the static
palette, the glass and the layout. `spotify-shell` needs nothing but the app.


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
dist/                built artifacts (committed)
dist/legacy/         artifacts that predate the toolchain, kept as-is
conformance/         golden payloads used by the tests
schemas/             the payload contract: v2 (frozen) and v3
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
fvm dart run tools/install.dart -t caelestia --select

fvm dart test                            # the contract's tests
```

`build.dart` runs the theme before it packages it. A theme that compiles but
returns nothing — or returns a color the app cannot parse — is a build
failure here, not a user's blank app.

## The themes

| Theme | What it is |
|---|---|
| `caelestia` | Matches the active Caelestia shell scheme — published |
| `caelestia-glassier` | The same, with thinner surfaces — published |
| `caelestia-plain` | The base palette with no backdrop and no glass — published |
| `caelestia-shell` | The balanced variant: readable text over a bright wallpaper — published |
| `spotify-shell` | A Spotify-shaped shell: black and green, inset panel, rail navigation — published |
| `minimal` | The SDK in nine lines: one seed colour |
| `brand-demo` | The whole v3 payload, including a slot and a screen |
| `ui-demo` | A theme that answers with its own UI (`getUi()`, `onUiAction()`) |
| `asset-demo` | A theme that ships an image and points at it |
| `kitchen-sink` | Every field the v3 payload has, in one theme |

## The payload

`getTheme()` returns a map. The fields the app reads today (v2):

| Field | Meaning |
|---|---|
| `light`, `dark` | 17 color roles each: `background`, `foreground`, `card`, `cardForeground`, `primary`, `primaryForeground`, `secondary`, `secondaryForeground`, `muted`, `mutedForeground`, `accent`, `accentForeground`, `destructive`, `destructiveForeground`, `border`, `input`, `ring` |
| `surfaces` | `opacity` (0..1), `blur` (0..100), `tint` (`#RRGGBB` / `#AARRGGBB`) |
| `background` | `source` (`none` / `albumArt` / `shell`), `opacity`, `blur`, `overlay`, `transparent` |
| `radius` | `small`, `medium`, `large`, `pill` |
| `density` | 0.7..1.5 — one number for the whole UI's size |
| `tokens` | `cardWidth`, `cardHeight`, `artistCardWidth`, `artistCardHeight`, `gutter`, `fontFamily` |
| `layout` | `chrome` (`flat` / `inset`), `nav` (`labels` / `rail`), `progress` (`inline` / `below`) |
| `dynamic` | `source` (`albumArt` / `shell`), `algorithm` (`material`) |

Rules that are not obvious:

- **Colors are `#RRGGBB` or `#AARRGGBB`.** Anything else makes the app throw,
  and a throw there discards the *entire* theme — one typo loses the palette.
- **Every one of the 17 roles is required** in both `light` and `dark`.
- **Unknown fields are ignored.** That is what lets a newer theme ship to an
  older app: the app skips what it does not know. `build.dart` reports those
  fields as warnings.
- **Numbers outside the app's range are clamped**, not rejected. The build
  prints the value the app will actually use.

`schemas/theme.v2.schema.json` is the contract in full, and `conformance/`
holds the payloads that have to keep working.

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
- It cannot load a font file; a font family has to exist on the machine.

## v3

`specVersion: 3` adds four kinds of decision on top of v2: more colour roles
(popover, sidebar, status, charts), tokens (typography, spacing, motion,
scale, icons), component styles, and the shell's composition — plus branding,
assets and a declarative UI tree with slots, screens, bindings and actions.

The contract is written down in `schemas/theme.v3.schema.json`, enforced by
`lib/v3_validator.dart`, and demonstrated by `themes/kitchen-sink` — the theme
that has to carry every field, so a new field without an example fails the
test suite.

A v2 host ignores all of it, which is what lets a v3 theme ship to an older
app. `AUTHORING.md` is the full reference.
