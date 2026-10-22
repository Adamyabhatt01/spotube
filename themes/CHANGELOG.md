# Changelog

The themes and the tool that builds them. The app's side of the contract is
versioned separately — the payload is `v2` there, and `v3` is drafted here.

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
