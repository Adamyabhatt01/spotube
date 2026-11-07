# Theme v4 — Fresh opinion (code-grounded)

Grounded in: `themes/schemas/theme.v4.schema.json` (v4 contract), `themes/conformance/spotify-shell-v4.json`, `lib/modules/theme_ui/theme_ui_host.dart`, `theme_ui_node*.dart` (renderer parts), `theme_ui_bindings.dart`/`theme_ui_binding_registry.dart`, `theme_ui_action.dart`/`theme_ui_action_dispatcher.dart`, `theme_ui_items.dart`, and the static-theme path (`provider/metadata_plugin/plugin_providers.dart` + `services/metadata/static_theme.dart` + `plugin_assets.dart` as noted in recent commits/context). No upstream/other opinions assumed.

## What v4 already gets right

- **A real, bounded UI contract**: v4 is not “arbitrary code draws UI”. It’s a typed node graph (`_uiTypes` in `theme_ui_node.dart`), named render points, shell/pages/components, and a small action/binding vocabulary. `additionalProperties`/caps/regexes in the schema + host-side parsing (`ThemeUiAction.knownTypes`/`maxPerNode`, item-template resolution) give the host room to reject/ignore rather than execute surprises.
- **Static fast path**: shipping build-time `theme.json` lets the host boot the theme without the Hetu VM when no declared optional methods are needed, while keeping VM for optional methods/capability-gated behavior (recent `29042fee` direction). That’s the right split for perf and determinism.
- **Perf-aware rendering primitives exist**: page bodies render as slivers (`theme_ui_host.dart`), top-level vertical/non-filtered/single-column `list` (or `padding`-wrapped) can become `SliverList.builder` (`theme_ui_node_layout.dart`), palette demand is scoped (`_subtreeWantsPalette`/`_walkPalette` path), and `virtualList`/caps exist. Item bindings flatten typed models (`theme_ui_items.dart`) so rows don’t re-resolve by id.

## Gaps / limits to prioritize

### 1) Virtualization is uneven (the biggest practical ceiling)

- **`list` laziness has narrow eligibility**: only the specific sliver path above becomes lazy. Horizontal lists, filtered lists, `columns > 1`/responsive multi-column, and non-top-level/list-in-box contexts still materialize eagerly. For real libraries (playlists/tracks/search/downloads) this means perf depends on authors hitting the exact pattern; the lazy path additionally hard-caps rows (`limit` fallback 200, max 500 — `_listSliver`, `theme_ui_node_layout.dart:764`). Note: the named conformance fixture `spotify-shell-v4.json` contains zero `virtualList` nodes (it uses `list`); `virtualList` appears in other themes (e.g. `neon-cabinet.json`, `neon-maximalist.json`).
- **`virtualList` is a box widget, not a sliver, and is rigid** (`_virtualList` in `theme_ui_node_data.dart`): returns `ListView.builder` directly (no `SizedBox` wrapper, no `GridView.builder` — multi-column is `ListView` + `Row` cells), with a fixed `itemExtent` (optional in schema, `minimum: 8` when present; impl fallback 56, clamp 8–400), caps `overscan`/`limit` (`_themeUiMaxVirtualItems=10000`). It can’t participate in the page’s sliver scroll, doesn’t support variable-height rows, and “infinite/paged” loading isn’t modeled (no `loadMore`/`hasMore`/`onEndReached` action/binding/threshold anywhere in schema or `knownTypes`).
- **`table`/`tree` are hard-bounded (not meaningfully virtualized)**: `table` renders at most 500 rows with `_themeUiMaxStaticRows`, raised to 10000 when `stickyHeader: true` (which does use slivers internally, but still builds a fixed bounded set); `tree` walks with `_themeUiMaxTreeNodes=500`; schema already advertises `stickyHeader`/`sortable` and `table` impl supports them, but large datasets will still build too much. Good for settings/small data, not for library-scale data.
- **Impact**: themes can look complete in conformance-sized fixtures yet regress badly on real collections unless every heavy surface is hand-authored around the lazy/virtual constraints.

### 2) Interactivity is bounded, but “local UI state” is underpowered

- **No generic ephemeral state channel**: actions/bindings cover navigation, playback, audio FX, settings, queries, pins, playlist CRUD, page/region toggles, copy/refresh/scroll/dismiss (`theme_ui_action.dart`/dispatcher shows `setBass/Treble/Normalization/Crossfade/SleepTimer/Speed/Muted`, playlist CRUD, `setQuery/clearQuery`, `setSetting/toggleSetting`, `toggleSidebar/Aside/Region`, `openPage/closePage`, `dismiss`, etc.). What’s missing is a first-class transient state namespace (e.g., page-local/dialog-local key-values) that isn’t persisted as `setting.*` and isn’t limited to query text.
- **`openBind`-driven overlays are one-way in practice**: `dialog`/`sheet` take `openBind` and open on a false→true edge (`theme_ui_node_overlays.dart`: controlled by `openBind`, reopens only on edge; dismissal doesn’t inherently write the bind back). `collapsible` reads `openBind`/`boundOpen`. But binds are host snapshots; a theme can’t generically set an arbitrary bind. Closing a controlled overlay cleanly often means routing state through `setting.*`/`setSetting` or carefully using `dismiss` — workable, but awkward and easy to get “stuck open/closed” semantics.
- **No form submission/value model beyond individual controls**: `textField/select/checkbox/radioGroup/segmented` exist, and `$value` interpolation is supported for control actions (checkbox/switch state reaches actions as a bool through `$value` — `$checked` does not exist), but there’s no grouped form state/validation/submit payload pattern. Complex flows (multi-step dialogs, filters with apply/reset distinct from live query) push themes toward persistence hacks.

### 3) The binding/action surface is strong for playback+library, thinner for “system truth”

- **Registry is explicit and finite** (`theme_ui_binding_registry.dart`/`theme_ui_bindings.dart`): covers player (`player.*`), queue snapshot (`queue.tracks/currentIndex/next/count`), saved library lists/counts, audio effects/settings, queries, pins, navigation/app context etc. (per examined registry/bindings).
- **Notably absent as first-class reactive bindings (from examined surfaces)**: player **buffering/loading/error** state, network/connectivity/connect device state, radio state, lyrics state/progress, and **download progress** (queue/download lists are exposed via `queue.*`/host widgets/items; `DownloadTask` item maps `status`/`size` in `theme_ui_items.dart` but not a progress fraction/speed). Themes can show lists and trigger `openLyrics/openDownloads/openQueue`, but can’t render rich status UIs (buffering spinner tied to truth, download bars, connect badge, radio “now playing context”) purely from bindable state.
- **Queue is readable, not deeply mutable as data**: `openQueue` and `queue.*` exist; schema/known actions don’t expose fine-grained queue reorder/remove/jump-to-index as general actions. `queue.list` is also a host widget — which is fine, but limits fully custom queue UIs.

### 4) Schema expressiveness vs generic enforcement

- **`hiddenWhen`/`disabledWhen` are schema-wide, but enforcement is far weaker than the schema implies**: the schema attaches `hiddenWhen`/`disabledWhen` to many node types and defines `uiCondition` (truthy binding or `!binding`). In the v4 renderer (`theme_ui_node.dart:148-258`), `hiddenWhen` is **never evaluated** — zero references in `theme_ui_*`; it’s dead schema surface for UI nodes (live only for shell nodes, via `shell_layout_host.dart:110-152`, which even has a small comparison vocabulary the v4 renderer could reuse). `disabledWhen` is handled, but only per-node-hand-built: `button` (`theme_ui_node_content.dart:203`) and input controls (`_inputDisabled`, `theme_ui_node_inputs.dart:43`). So a theme author who writes `hiddenWhen` on a `row`/`card`/`list` gets no behavior at all — surprising inconsistencies (“why does this node ignore `hiddenWhen`?”) are guaranteed. Worth making enforcement uniform in the base node wrapper, or removing `hiddenWhen` from `uiNode` until it’s real.
- **Conditions are intentionally simple — with one escape hatch**: `uiCondition` is truthy / negated binding only, with no comparison or `and`/`or` composition there (good for safety/determinism, but range checks like “count > 0” and multi-condition gates have no expression). The `conditional` node type does carry inline `bind` + `equals` + `invert` (schema lines 1969-1984), rendered via `ThemeUiBindings.matches` (bool/num/string equality), so “selected tab == id” IS achievable via `conditional` — but `hiddenWhen`/`disabledWhen` stay truthy-only and there’s no numeric-range or composition anywhere, so harder gates still push authors into bespoke host bindings or more `conditional` nesting.

### 5) Motion/transition model is shallow relative to the “animate” surface

- Schema and tokens expose `motion` (durations/easing, page/sheet) and nodes carry an `animate` number, but v4 reads more like “timing hints + component transitions” than a composable motion system (no state-driven enter/exit/interrupt choreography, no shared element/keyed transition contract in the schema reviewed). That’s consistent with the perf/complexity budget, but it caps how “alive” a fully custom shell can feel without host-widget escapes. (This is a design tradeoff, not a bug.)

### 6) Accessibility/semantics are mostly implicit

- The schema has no semantic/label/hint/focus metadata fields, and in the examined renderer no `Semantics`/`semanticLabel`/focus-order contracts applied to custom nodes were found (text/icon/image/button/menu/overlays render visual widgets). `tooltip` exists, which helps, but screen readers/keyboard focus/accessible names for arbitrary theme-composed controls are not something a theme author can reliably specify. For a UI-replacement system, this is a real product gap.

### 7) Data widgets: capable but specialized

- **`carousel`/pagination/accordion** have fixed caps (`_themeUiMaxAccordionItems=32`, `_themeUiMaxCarouselItems=50`, breadcrumb 16) — sensible. **`pagination`** is schema’d, but useful pagination usually needs a coherent pattern with `setQuery`/`refresh`/paged bindings; without a data-fetch/page-state contract it’s mostly a control shell.
- **`filter` is host-side substring/diacritic-fold over declared fields** (schema `uiFilter`, debounced in renderer) — great for local lists, but not a substitute for backend/search filtering or sorted/remote datasets.
- **Item action injection covers the common media types** (`theme_ui_items.dart`: track/album/artist/playlist/download + map/string). Gaps show up as missing normalized fields (e.g., download progress, playlist track count for *both* playlist variants, richer radio/search-result shapes) rather than missing mechanics.

### 8) `hostWidget` escape hatches are necessary but reveal coverage edges

- Schema enumerates a fixed `hostWidget` set (`library.*`, `player.controls`, `audio.*`, `queue.list`, `search.field`, `theme.settings`). That’s pragmatic. It also signals where pure-node composition isn’t yet sufficient or ergonomic (queue UX, settings, search). Expanding v4 power means either growing bindable state + generic nodes, or growing host widgets — the latter is safer/faster but reduces theme uniqueness.

## How to improve it (highest leverage, in order)

1. **Make virtualization the default, not a special case.** Unify `list`/`virtualList` semantics: sliver-native virtual lists in page scroll, variable-extent support (or documented fixed-extent fast path), and a `loadMore`/pagination trigger (`onEndReached`-style action + `hasMore/loading` bindings). Keep hard caps (and raise/document the `limit` 200/500 lazy cap), but raise the ceiling safely.
2. **Add a small, explicit ephemeral state layer.** Page/dialog scope key-values with `setLocal`/`toggleLocal` (or a `state.*` bind namespace) that resets on navigation — separate from persisted `setting.*` and from `query.*`. Wire `openBind`-style controls to it so overlays/collapsibles are trivial to author correctly.
3. **Fix the condition/guard mismatch.** `hiddenWhen` is currently dead on `uiNode` — either enforce `hiddenWhen`/`disabledWhen` uniformly in the base node wrapper (with clear exceptions for overlays/self-managed controls; the v1 shell’s comparison evaluator at `shell_layout_host.dart:148` is a ready-made starting point) or remove them from the schema until implemented. Add lightweight range/composition to `uiCondition` (e.g. `gt`/`gte`/`lt`/`lte` on numerics, `and`/`or` lists) — still declarative, no expressions — and promote the `conditional` node’s `bind`/`equals`/`invert` pattern to guards too.
4. **Expose “system truth” bindings.** Buffering/error, download progress, connect state, radio/lyrics status — read-only, demand-scoped like existing bindings. This unlocks honest custom players/download/connect UIs without new host widgets.
5. **Accessibility pass.** Add optional `semanticsLabel`/`semanticsHint`/`excludeSemantics` (or `a11y` object) to interactive nodes and ensure focus traversal/roles are sensible for buttons, inputs, lists, dialogs/sheets. Keep it declarative.
6. **Keep the static/VM boundary crisp.** Any new capability should declare whether it’s static-payload expressible or requires an optional method/VM, so the fast path (`theme.json`) remains the common case.

**Net:** v4’s foundation is solid — declarative, bounded, and now much faster on the main path. The main things it’s *missing* are (a) uniformly scalable data rendering, (b) ergonomic local state for real interactive UI, (c) a few high-value status bindings, and (d) consistent guard/semantics ergonomics. Those are the changes that would let themes move from “can restyle and recompose common screens” to “can build complex, reliable custom shells” without falling back to host widgets or fragile workarounds.

## Implementation status

Implemented (recommendations 1–6 in this file):

1. **Virtualization.** `_listSliver` now also lazily renders filtered,
   fixed-multi-column and breakpoint-responsive lists (rows of cells or a
   `SliverLayoutBuilder`; a `crossAxisAlignment.stretch` Row inside a sliver
   item forces an infinite height — cell rows use `start`). `virtualList`
   renders as a sliver in page slots (`_virtualListSliver` via `_asSliver`).
   `list`/`virtualList` accept `onEndReached` + `hasMoreBind` +
   `loadingBind` + `endThreshold` (items-from-the-end, default 5): a per-node
   latch fires the action once per visible-item count with `$value` the
   count. Horizontal shelves stay eager by design.
2. **Ephemeral state.** `themeUiLocalStateProvider` (per-theme scoped,
   session-only), `state.<key>` bindings, write/read-back via
   `setLocal`/`toggleLocal`/`clearLocal` (scalar values, key-validated like
   `setSetting`, no capability, no persistence).
3. **Guards/conditions.** `theme_ui_condition.dart` evaluates string,
   negated and object-form conditions (`equals`/`invert`/`gt`/`gte`/`lt`/
   `lte`/`allOf`/`anyOf` — named `allOf`/`anyOf` because bare `all` collides
   with the padding prop's name in the validator's prop table). `hiddenWhen`
   is enforced uniformly in `ThemeUiNodeView.build` (was dead schema
   surface); `disabledWhen` is enforced for every node as pointer inertness
   plus per-control visuals. `conditional` gained the list keys.
4. **System truth.** `player.buffering`/`completed`/`error`,
   `downloads.active|queued|failed|completed|progress`
   (fraction map, stream-fed per downloading task), `lyrics.available|synced|line`,
   `radio.active|playing|buffering|station|liveTitle|error`,
   `connect.available|clients|clientCount` — all demand-scoped, alongside
   registry entries and schema/validator bindings.
5. **Accessibility.** `semantics` envelope (`label`/`hint`/`value`/
   `excludeSemantics`) on every node, rendered as a `Semantics` container or
   `ExcludeSemantics`; schema + validator envelope include it.
6. **Static boundary.** Schema root description and `AUTHORING.md` document
   the additions as host-side and static-payload expressible.

Sync points updated with it: `themes/schemas/theme.v4.schema.json`
(bindings enum/patterns, object-form `uiCondition`, `uiSemantics`, paging
props, action verbs), `themes/lib/v4_validator.dart` (props, bindings,
capability checks that recurse into object conditions),
`themes/themes/kitchen-sink/theme.ht` + rebuilt golden + `.smplug`, and the
schema-test corpus of bindings. Tests: `test/theme_ui_condition_test.dart`
(13), `test/theme_ui_paging_test.dart` (9). Deliberately not done: queue
reorder/remove/jump actions (no recommendation asked for them; `openQueue`
plus `queue.list` host widget remain the story) and focus/keyboard delivery
of semantics (labels are now expressible; traversal is the host kit's
existing behavior).
