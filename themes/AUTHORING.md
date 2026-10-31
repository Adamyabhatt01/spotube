# Authoring a theme

> **v4 status:** the authoritative contract is
> `/home/adamya/.opencode/plan/v4-theme-contract.md`; Phases 0–5 are
> implemented (spec foundation, kits, layout nodes, inputs and overlays,
> render points, bindings/palette, and layout regions). v4 is breaking: v2
> payloads remain, `specVersion: 3` is rejected with
> `specVersion 3 is not supported; migrate to 4`, and
> `themes/tools/migrate_v3.dart` is the migration path. This document
> describes the v3 blocks where noted and the v4 nodes that exist today; the
> full v4 rewrite is Phase 11.

## A theme is a plugin

Spotube loads a theme the same way it loads a metadata plugin: a `.smplug`
archive with a `plugin.json` and a compiled `plugin.out`. The manifest names
the entry point and declares the `theme` ability:

```json
{
  "name": "My Theme",
  "description": "What it does.",
  "version": "1.0.0",
  "author": "Your Name",
  "entryPoint": "MyTheme",
  "pluginApiVersion": "2.0.0",
  "apis": [],
  "abilities": ["theme"]
}
```

The source is Hetu. A theme is a class whose `theme` member answers
`getTheme()`:

```hetu
class MyThemeApi {
  fun getTheme() {
    return {
      'light': { /* 17 roles */ },
      'dark':  { /* 17 roles */ },
    };
  }
}

class MyTheme {
  var theme = MyThemeApi();
}
```

## The seventeen roles

Both schemes need all of them; a missing role makes the app throw and throws
away the whole theme.

| Role | What it paints |
|---|---|
| `background` | the page |
| `foreground` | text on the page |
| `card` | surfaces: cards, panels, the player bar |
| `cardForeground` | text on a surface |
| `primary` | the accent: active states, links, the brand |
| `primaryForeground` | text on the accent |
| `secondary` | the quieter accent |
| `secondaryForeground` | text on it |
| `muted` | disabled and recessed surfaces |
| `mutedForeground` | secondary text |
| `accent` | the highlight behind an active item |
| `accentForeground` | text on it |
| `destructive` | errors, and the delete action |
| `destructiveForeground` | text on it |
| `border` | outlines |
| `input` | input outlines |
| `ring` | the focus ring |

Colours are `#RRGGBB` or `#AARRGGBB`.

## Let the SDK do the work

`sdk/palette.ht` derives both schemes from one seed colour:

```hetu
//#include "sdk/palette.ht"

class MyThemeApi {
  fun getTheme() {
    var schemes = ThemePalette.fromSeed('#3f7ae0')
    return {
      'light': schemes['light'],
      'dark': schemes['dark'],
    }
  }
}
```

`fromSeed` returns the seventeen roles a v2 host reads. `fromSeedFull` returns
those plus the v3 roles — popover, sidebar, the status colours and a
categorical chart palette — and is what a theme declaring `specVersion: 3`
wants.

`sdk/defaults.ht` holds the neutral palette and a merge, for a theme that
changes two roles and leaves the rest:

```hetu
//#include "sdk/defaults.ht"

var light = ThemeDefaults.merge(ThemeDefaults.light(), {'primary': '#3f7ae0'})
```

## Build it

```bash
fvm dart run tools/build.dart -t my-theme        # build one theme
fvm dart run tools/build.dart --check            # validate every theme
fvm dart run tools/inspect.dart -f dist/my-theme-1.0.0.smplug --json
```

The build runs the theme before it packages it, so a theme that returns
nothing, or a colour the app cannot parse, fails the build.

## Preview it

```bash
fvm dart run tools/export.dart
fvm dart run tools/preview.dart my-theme
```

`preview.dart` reads the exported payload and writes
`dist/preview/my-theme.html`: one file with both schemes, the palette, the
component samples and the theme's screens, plus the stage if it has one. Fonts
and images are inlined, so it opens offline. The top bar switches scheme and
play/pause; the URL carries the state (`#mode=light`, `#screen=palette`).

The preview is obsidian-shaped: its sample track, pixel CSS and font allow-list
assume that theme, and it does not draw `home.content` or `list` nodes. It is
a quick palette/stage check, not a full renderer; the app is the reference for
the whole v3 tree.

## Ship it

Add a `build.json` next to the theme:

```json
{ "publish": "my-theme/plugin.smplug" }
```

The build then also writes the artifact to that path, which is the path the
install URL in the README points at. A published path is part of the contract
with whoever installed the theme — moving it breaks their install.

## v3: what a theme may decide

`specVersion: 3` adds four kinds of decision. Everything a v2 host reads stays
exactly as it was, so a v3 theme still works on an older app — it draws as a
palette there.

### 1. More roles

The two schemes may define roles the v2 seventeen do not have. Each falls
back to the role it aliases, so a theme can set only the ones it cares about:

| Role | Falls back to |
|---|---|
| `popover`, `popoverForeground` | `card`, `cardForeground` |
| `sidebar`, `sidebarForeground` | `muted`, `foreground` |
| `sidebarPrimary`, `sidebarPrimaryForeground` | `primary`, `primaryForeground` |
| `sidebarAccent`, `sidebarAccentForeground` | `accent`, `accentForeground` |
| `sidebarBorder`, `sidebarRing` | `border`, `ring` |
| `success`, `warning`, `info` (+ foregrounds) | the host's status colours |
| `chart1` … `chart6` | the derived chart palette |

### 2. Tokens

```json
"typography": {
  "family": "Inter",
  "monoFamily": "JetBrains Mono",
  "brandFamily": "Cookie",
  "styles": {
    "h1": {"fontSize": 36, "fontWeight": 700, "height": 1.1, "letterSpacing": -0.5},
    "p": {"fontSize": 14, "height": 1.5, "color": "@mutedForeground"}
  },
  "fonts": [{"family": "Inter", "asset": "asset://fonts/inter.ttf", "weight": 400}]
},
"spacing": {"xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24, "page": 24, "section": 40,
            "custom": {"playerHeight": 72}},
"motion": {"fast": 110, "normal": 200, "slow": 340, "easing": "easeOutCubic",
           "custom": {"hover": 90}},
"scale": {"size": 1.0, "text": 1.0, "radius": 1.0, "icon": 1.0, "spacing": 1.0},
"icons": {"sm": 16, "md": 20, "lg": 24, "xl": 32,
          "overrides": {"home": {"asset": "asset://icons/home.png", "size": 20}}}
```

The style keys are the app's own typography styles: `h1` `h2` `h3` `h4` `p`
`lead` `large` `small` `muted` `xSmall` `xLarge` `x2Large` … `x9Large`. A
style key the host does not have (`brand`, `label`) is carried for future
hosts and ignored today.

`family` is the ladder's default: it applies to every role the theme does not
give an explicit `fontFamily`, so naming Inter and overriding only `h1` still
draws the rest of the ladder in Inter. `monoFamily` applies to `mono` and
`inlineCode`.

The host applies these blocks: `typography` becomes shadcn's type ladder
(fields a style omits keep the host value), `icons` becomes the icon ladder,
and `scale` multiplies size, text, radius, icon and spacing independently.
`spacing.page` is the page surface padding and `spacing.cardGap` the
shelf/grid gap (it falls back to `tokens.gutter` when omitted); `pageHorizontal`,
`section` and `custom` are published on `AppLayout` for pages that draw their
own sections. `motion` feeds the durations and easing of the transitions the
host draws. Every number is clamped on read, so an out-of-range value degrades
to the nearest usable one instead of breaking layout.

A colour is a hex value or a `@role` reference (`@primary`, `@cardForeground`,
`@chart3`, …).

### 3. Components

Component groups are validated and carried by the contract. The host draws
`player` (the footer surface) and the node-scoped `card`/`buttons` styles
directly; the remaining groups are reserved for hosts that can express them,
and a theme may ship them without a host release. Buttons may be restyled per
variant:

```json
"components": {
  "buttons": {
    "primary": {"radius": 10, "padding": 12, "fontWeight": 600, "iconSize": 18},
    "ghost": {"radius": 10, "padding": 8},
    "destructive": {"background": "@destructive", "foreground": "@destructiveForeground"}
  },
  "card": {"radius": 16, "padding": 16, "surfaceOpacity": 0.9, "surfaceBlur": 12},
  "player": {"background": "@background", "borderColor": "@border", "borderWidth": 0},
  "input": {"radius": 8, "height": 36, "borderColor": "@input"},
  "dialog": {"radius": 16, "padding": 24}
}
```

The groups are `card`, `player`, `input`, `tabs`, `nav`, `tooltip`, `badge`, `select`,
`switch`, `slider`, `scrollbar`, `avatar`, `skeleton`, `progress`, `divider`,
`menu`, `dropdown`, `modal`, `dialog`, `sheet`, `table`, `checkbox`, `radio`,
`toggle`, `toggleGroup`, `accordion`, `alert`, `breadcrumb`, `carousel`,
`collapsible`, `command`, `contextMenu`, `drawer`, `hoverCard`, `pagination`,
`popover`, `resizable`, `sidebar`, `stepper`, `toast`, `tree` — and the button
variants `primary`, `secondary`, `outline`, `ghost`, `destructive`, `link`,
`fixed`, `muted`.

Each style may set `padding`, `margin`, `gap`, `radius`, `borderWidth`,
`height`, `width`, `background`, `foreground`, `borderColor`,
`surfaceOpacity`, `surfaceBlur`, `fontFamily`, `fontSize`, `fontWeight`,
`fontStyle`, `letterSpacing`, `iconSize`, `indicatorColor`, `thumbColor`,
`trackColor`.

### 4. The shell

```json
"layout": {
  "chrome": "inset",
  "nav": "labels",
  "progress": "inline",
  "sidebar": "theme",
  "sidebarWidth": 240,
  "aside": "none",
  "asideWidth": 320,
  "navItems": ["home", "radio", "stats", "search"],
  "navbarItems": ["home", "search", "radio", "library", "stats"],
  "libraryItems": ["playlists", "artists", "albums", "stations", "local_library"],
  "player": {
    "dock": "stage",
    "showTrackDetails": true, "showActions": true,
    "showVolume": true, "showLyrics": true, "showProgress": true
  },
  "home": {"sections": ["recent", "featured", "new_releases", "browse"]},
  "settings": {"sections": ["accounts", "appearance", "playback", "about"]},
  "titlebar": {"height": 40, "padding": 12, "showBack": true},
  "splash": {"logo": "asset://images/splash.png", "text": "My Theme"},
  "enforce": ["playerDock", "libraryItems"],
  "responsive": {"compact": {"nav": "rail", "player": {"showVolume": false}}}
}
```

`navItems` drives the sidebar's top entries, `navbarItems` the bottom bar and
`libraryItems` the library group. The host ids are `home`, `radio`, `stats`,
`search` (sidebar), `home`, `search`, `radio`, `library`, `stats` (bottom bar)
and `playlists`, `artists`, `albums`, `stations`, `local_library` (library).
An entry may also be `screen:<id>`, which links to one of the theme's own
`ui.screens` — that is how a theme adds a destination the host never shipped.

A non-empty list **is** the surface: the host shows exactly those entries, in
that order, dropping ids it does not implement (a list of only unknown ids
falls back to the host's own). An absent or empty list leaves the user's own
entries and order untouched. The same presence rule applies to `home.sections`
and `settings.sections`: a non-empty list replaces the group, anything else
keeps the host order.

`dock` is `full`, `compact`, `floating` or `stage`. `stage` turns the player
into the centre of the app: the record, its title and the transport, with the
theme filling `stage.center` and `stage.below` itself (see §6). Navigation
stays around it, so a stage theme is still a player, not a splash screen.
`compact` docks the bar under the content; `full` and `floating` describe the
host's default footer and defer to the user's own dock preference.

**The v4 host reads intent from what the theme sends, not from `enforce`.**
`enforce` was the v3 opt-in gate and is ignored by the v4 host; keep the list
if the same payload also ships to v3 hosts, and omit it from a v4-only build.
Two preferences still belong to the user: a theme can hide the volume control
with `"showVolume": false`, but cannot force it back onto a user who chose to
keep it hidden, and cannot take the footer dock away from a user who chose
`full` (only `compact` asks for the docked shape).

`responsive` holds up to four variants, each overriding the same fields. The
name selects the window tier: `compact` (with `xs`/`sm` aliases, up to
820 px), `medium` (`md`, up to 1024 px) and `expanded` (`lg`/`xl`/`2xl`).
Variants merge over the base layout, so a variant may override just
`player.showVolume` without restating anything else.

**Regions (v4).** `sidebar` is `host` (the default) or `theme`; `theme` hands
the sidebar body to the `sidebar.content` slot, while the host keeps the width
box, divider, bottom clearance and docked player. `sidebarWidth` is 0–1000
logical px (default 200) and rides the active scaling. A user who collapses the
sidebar narrows the theme body to the host rail width instead of hiding it, so
the theme can read `app.sidebarCollapsed` and draw a rail. `aside` is `none`
(default) or `theme`; a theme panel mounts only while the user has it open,
the window is wider than the compact tier (820 px), and `aside.content` is
filled. Its width is `asideWidth` (default 320). The host draws the close
control; `toggleAside`, the shortcut, and `app.asideOpen` share the persisted
state. Both keys and widths can be overridden per breakpoint in `responsive`.

**Shell descriptor (v4).** `layout.shell` rearranges the shell itself. A tree
is a container (`row`, `column`, `stack`, `grid`) or a region leaf; containers
carry `children`, gaps and the same size fields as leaves. `grid` is one row of
equal-width cells because the descriptor has no column count. Exactly one
`content` region is required and it is where the router outlet mounts; a
`slot` on `content` is ignored. `sidebar`, `aside`, `player`, `titlebar` and
`navbar` appear at most once each. `custom` regions repeat and require `id`,
`slot` and (for screen readers) `label`; their slot names are namespaced by
that id (`bar.bottom.secondary`). Trees are capped at depth 8 and 24 leaves.

```json
"shell": {
  "type": "row",
  "children": [
    {"region": "sidebar", "width": 280, "slot": "sidebar.content"},
    {"type": "column", "flex": 1, "children": [
      {"region": "content", "flex": 1},
      {"region": "player", "height": 88},
      {"region": "custom", "id": "bar.pins", "slot": "bar.pins", "label": "Pinned", "height": 72}
    ]}
  ]
}
```

Sizes are px numbers, `"30%"` of the parent, or `"auto"` for intrinsic size.
`flex` consumes the remaining space and turns the fixed size into the flex
basis; `min*`/`max*` clamp after flex distribution. Defaults when neither size
nor flex is given: sidebar 280, aside 320, player 88, titlebar 36, navbar 56,
custom 0. `resizable` adds a drag handle on the listed `edges` and persists the
drag under `storageKey` (double-click resets); `collapsible` adds a host toggle
that persists alongside it, with `collapsedSize` defaulting to 0 for
sidebar/aside/custom and 32 for bars. `hiddenWhen` takes a binding and removes
the region from layout entirely while false. `overflow: "scroll"` scrolls the
region; `clip` is the safe default for the other modes until their host chrome
ships. `safeArea`, `zIndex`, `focusOrder` and `label` are honoured; focus
follows tree order unless `focusOrder` overrides it.

A shell that fails parsing (wrong content count, duplicate ids, unknown region,
over-deep tree) reads as absent, so the legacy layout stands instead of a blank
window. Omitting `shell` keeps today's layout. `responsive.<tier>.shell`
replaces the whole tree for that breakpoint. On desktop, a tree without a
`titlebar` region gets a 28 px drag strip injected at the top when the system
titlebar is hidden; pages keep their own `TitleBar` either way. Region sizes and
collapse flags persist per theme identity and region id, and a region publishes
`region.<id>.width`, `region.<id>.height`, `region.<id>.collapsed` and
`region.<id>.visible` (omit `id` and the region name is used).

**Pin targets (v4).** `layout.pinTargets` declares where a playlist may be
pinned; `library.pinTargets` publishes the same list (defaulting to
`[{id: "sidebar", label: "Sidebar"}]`). A pin carries `target` and `library.pins`
entries include it. `pinItem`/`unpinItem` accept `{item, target?}`; an omitted
target means `sidebar`, but only while the theme declares it — a theme that
replaced the sidebar with custom bars must name one. Unknown targets are
ignored. Sidebar pins keep using the existing preference column; other targets
are stored per theme. `library.playlists` accepts `filter: "pins"` with
`pinTarget` (host-widget filtering lands with Phase 8/9).

### 5. Branding

```json
"branding": {
  "appName": "Aurora",
  "shortName": "Aurora",
  "tagline": "Your music, your shell",
  "wordmark": {"text": "Aurora", "fontFamily": "Cookie", "asset": "asset://images/wordmark.png"},
  "logo": "asset://images/logo.png",
  "titlebarTitle": "Aurora",
  "windowTitle": "Aurora",
  "aboutName": "Aurora",
  "notificationName": "Aurora",
  "showHostAttribution": true
}
```

The host always keeps its name, version and licence on the About page,
whatever a theme says. `wordmark` (text or asset) replaces the logo in the
sidebar and the home header; `logo` is also the splash fallback; `aboutName`
titles the About page and `windowTitle` the window.

### 6. Content

A theme may put content in the app's surfaces. The UI is a tree of nodes,
written **flat** — the props sit on the node:

```json
{
  "type": "animate",
  "kind": "rotate",
  "duration": 24000,
  "curve": "linear",
  "bind": "player.playing",
  "children": [
    {
      "type": "image",
      "src": "player.artwork",
      "width": 360,
      "height": 360,
      "shape": "circle",
      "filter": "nearest"
    },
    {"type": "text", "bind": "player.title", "size": "xl", "align": "center"}
  ]
}
```

That is a record that turns while the track plays and stops where it is when
it does not. (`props: {…}` is still read as the original shape, and is merged
into the flat one, but every theme in this repository writes the flat form.)

| Node | Props |
|---|---|
| `row`, `column` | `gap`, `align`, `justify` |
| `stack` | `align`, `fit` (`loose`, `expand`) |
| `wrap` | `gap`, `runGap`, `align`, `justify` |
| `padding` | `all`, `horizontal`, `vertical`, `top`, `right`, `bottom`, `left` |
| `align` | `align`, `widthFactor`, `heightFactor` |
| `expanded` | `flex` |
| `scroll` | `direction`, `padding` |
| `text` | `text`, `bind`, `size`, `weight`, `color`, `maxLines`, `align`, `overflow`, `family`, `letterSpacing`, `uppercase` |
| `icon` | `icon`, `size`, `color` |
| `image` | `src`, `bind`, `width`, `height`, `radius`, `shape`, `fit`, `filter`, `tile`, `opacity` |
| `button` | `label`, `icon`, `variant`, `size`, `disabledWhen`, plus `action`/`actions` |
| `card` | `padding`, `radius`, `background`, `hoverBackground`, `borderColor`, `borderWidth`, `opacity`, `width`, `height` |
| `search` | `placeholder` |
| `divider` | `orientation`, `thickness`, `color` |
| `spacer` | `flex` |
| `gap` | `size` |
| `conditional` | `bind`, `equals`, `invert` |
| `template` | `name`, `args` |
| `animate` | `kind`, `duration`, `curve`, `bind`, `reverse` |
| `progress` | `bind`, `maxBind`, `width`, `height`, `hitHeight`, `radius`, `borderWidth`, `borderColor`, `color`, `trackColor`, `thumbColor`, `thumbSize`, `interactive`, `style` (`linear`/`wavy`) |
| `list` | `bind`, `gap`, `limit`, `align`, `direction`, `filter`, plus `children` (the row template) |
| `virtualList` | `bind`, `itemTemplate` (or `children`), `itemExtent` (8..400), `overscan` (0..64), `limit` (1..10000), `filter` |
| `table` | `bind`, `columns: [{key, label, width, align}]` (1..32), `rowTemplate` (or `children`), `stickyHeader`, `sortable` |
| `tree` | `bind`, `labelKey`, `childrenKey`, `expandedKey` |
| `accordion` | `items: [{title, children}]` (max 32), `multiple` |
| `collapsible` | `title`, `openBind`, plus `children` |
| `carousel` | `bind`, `itemTemplate` (or `children`), `height` (40..800), `autoplay` |
| `badge` | `text`, `variant` |
| `chip` | `label`, `selectedBind` |
| `avatar` | `src`, `fallback`, `size` (8..256) |
| `skeleton` | `width`, `height`, `radius`, `count` (1..50) |
| `spinner` | `size` (8..256), `color` |
| `breadcrumb` | `items: [{label, id, action}]` (max 16) |
| `pagination` | `pageBind`, `pageCount` (1..1000), plus `action`/`actions` |
| `box` | `background`, `gradient`, `border`, `radius`, `width`, `height`, `clip`, `padding`, `opacity`, plus `children` |
| `grid` | `columns` (1..12), `gap`, plus `children` |
| `resizable` | `direction` (`horizontal`/`vertical`), `initial`, `min`, `max` (0..4000), `storageKey`, plus exactly two panes |
| `safeArea` | `edges` (`top`/`right`/`bottom`/`left`; omit for all four), plus `children` |
| `aspectRatio` | `ratio`, plus `children` |
| `kitScope` | no props of its own; sets `kit` for its subtree |
| `slider` | `min`, `max`, `step`, `label`, `showValue`, `orientation` (`horizontal`/`vertical`) |
| `switch`, `checkbox` | `label` |
| `radioGroup` | `options: [{value, label, icon}]` |
| `textField` | `placeholder`, `debounceMs` (0..5000), `clearable`, `icon` |
| `textArea` | the `textField` props plus `minLines`/`maxLines` (1..8) |
| `select` | `options: [{value, label, icon}]`, `placeholder` |
| `segmented` | `options` (a bare string or `{value, label, icon}`), `valueBind` |
| `tabs` | `items: [{id, label, icon}]`, `panels` (one node list per item) |
| `menu` | `items: [{label, icon, checked, disabled, action/actions}]` (max 32), `trigger`, `placement` |
| `contextMenu` | the `menu` item list; wraps its `children` |
| `popover` | `trigger`, `placement`, plus `children` |
| `tooltip` | `text`, `placement`, plus `children` |
| `dialog` | `title`, `description`, `openBind`, `actions: [{label, action/actions}]` (max 4), plus `children` |
| `sheet` | `side` (`bottom`/`top`/`left`/`right`/`start`/`end`), `width`, `openBind`, plus `children` |

An unknown prop is an error, not a silent no-op: the build fails rather than
shipping a theme that does not do what you wrote.

**Kits (v4).** Every node also accepts `kit` (`shadcn`, `material`,
`cupertino`) and `variant`. Resolution runs node `kit` → nearest `kitScope` →
theme `uiKit` → `shadcn`. The theme's `uiKit` only sets the default: a
`kitScope` or a node can override it, and an unknown name falls through to the
enclosing choice. A kit that does not implement a component falls back to the
theme kit and then `shadcn`; in a debug build `ThemeUiDiagnostics` logs each
fallback once per node/variant/kit. Today Material and Cupertino implement
`button`, `progress` and `slider`; those three get native controls, everything
else draws the shadcn node. Material/Cupertino colours and type come from the
plugin palette and typography, not from a separate theme block.

**Forms.** Inputs read their current value from `bind` and never write it:
the host's binding is the source of truth, and a control fires the node's
`action`/`actions` with `$value` replaced by the value the user chose. A slider
uses its local drag position until release and then fires once, so seeking does
not spam the host. A `textField`/`textArea` debounces typing by `debounceMs`
(0 fires on every edit), flushes immediately on submit, and a `clearable` field
adds a clear button that fires the empty value. `radioGroup`, `select` and
`segmented` take an option list; `switch`/`checkbox` fire a boolean. `tabs`
keeps its own selected item: `bind` may hold either the item id or an index,
its change action receives the item id as `$value`, and `panels` (when supplied)
must have one node list per item.

**Menus and overlays.** `menu` opens `items` from a text or node `trigger` and
closes after an item fires. `contextMenu` wraps its children and opens on
right-click (desktop) or long-press (touch). `popover` and `tooltip` wrap their
children too. An overlay's content is drawn in the kit that opened it, not the
kit at the root of the page. `dialog` and `sheet` open on mount when they have
no `openBind`; with `openBind` they follow that binding, close when it goes
false, and reopen only on a false→true edge. The host cannot write a binding
back, so dismissing a dialog or sheet is local: it stays closed until the
binding cycles. `dialog.actions` are footer buttons, not node actions — each is
`{label, action|actions}` and lacking a label is skipped.

**Boxes and grids.** `box.border` is a colour (`"@border"`, one logical pixel)
or `{"color": "@border", "width": 2}` (0..8). `box.gradient` is
`{"colors": [..2..8], "begin": "topCenter", "end": "bottomCenter", "stops":
[0.0, 1.0]}`; stops are optional and must not decrease. `grid` is a
fixed-column `Wrap`: cells take the width the columns leave and keep their
intrinsic height, so rows can differ in height. `aspectRatio` sizes its child
from the incoming width and `ratio`.

**Splits.** `resizable` takes exactly two children: a fixed first pane and a
second pane that takes the rest. `direction` defaults to `horizontal` (the
first pane's width is dragged) and `vertical` drags its height. `initial`
defaults to 240, `min` to 120 and `max` to 480, all in logical px; the second
pane keeps at least 120 px so a drag cannot hide it. `storageKey` is namespaced
by the host and persists the dragged size across launches; without one the
size lasts for the session.

**Seeking.** `progress` draws the current playhead from `player.position` /
`player.duration`; with `interactive: true` it is draggable and tappable. A
drag previews locally and commits on release; both paths dispatch `seek` with
a clamped `fraction`. `style: "wavy"` draws the filled part as an animated
sine ribbon (the flat bar stays the default); it keeps the same hit area,
seek gesture and thumb.
`width` fixes the bar's logical width when it sits in a footer that Flutter
measures intrinsically (put it inside `expanded` when the row should flex
instead); `hitHeight` controls the touch target independently of the painted
`height`.

**Sizes and colours.** `text.size` is `xs`, `small`, `sm`, `md`, `lg`, `xl`,
`2xl` or `3xl`; `text.weight` is `100`–`900` or `thin` … `black`. A colour is
`#RRGGBB`, `#AARRGGBB` or an `@role` reference. `icon.size` is in logical
pixels.

**Pixel work.** `image.filter: "nearest"` samples without smoothing — the
one prop that keeps pixel art crisp. `image.shape: "circle"` clips to the
short side, so a square cover becomes a record. `image.tile: true` repeats
instead of stretching. `card` with `width`, `height` and a pill `radius` is a
sized shape with no children — a mark, avatar or dot drawn from the palette
rather than shipped as a bitmap. `background.tile` and `background.scale`
(1–8, whole numbers) do the same for the app's own backdrop, and
`components.*.borderStyle: "pixel"` draws a two-tone bevel derived from
`borderColor`.

**Animation.** `animate` wraps one subtree. `kind` is `rotate`, `pulse`,
`float` or `fade`; `duration` is milliseconds for one cycle; `curve` uses the
motion easings; `bind` makes the loop conditional — it runs while that
binding is truthy and holds its position when it is not; `reverse` turns the
other way. `animate` needs `ui.specVersion: 2`; a v1 host draws the child
still, which is a graceful fallback rather than an error.

**Bindings:** `player.trackId`, `player.title`, `player.artist`,
`player.album`, `player.artwork`, `player.playing`, `player.loop`,
`player.shuffled`, `player.speed`, `player.position`, `player.duration`,
`player.volume`, `player.muted`, `user.name`, `user.avatar`, `app.version`,
`app.brightness`, `app.themeMode`, `app.greeting`, `app.sidebarCollapsed`,
`app.asideOpen`, `clock.now`,
`theme.id`, `theme.name`, `theme.version`, `queue.tracks`, `queue.count`,
`queue.currentIndex`, `queue.next`, `library.playlists`, `library.pinTargets`,
`library.pins`, `library.albums`, `library.artists`, `library.folders`,
`library.counts`, `region.<id>.width`, `region.<id>.height`,
`region.<id>.collapsed`, `region.<id>.visible`,
`audio.bass`, `audio.treble`, `audio.normalization`, `audio.crossfade`,
`audio.sleepTimer`, `audio.speed`, `search.query`, `search.hasQuery`, and
`setting.<key>` for a theme's own toggle. A document only subscribes to the
sources its bindings name, so a theme that never draws the library does not
open the user's saved lists.

**Palette bindings:** `palette.dominant`, `palette.vibrant`, `palette.muted`,
`palette.darkMuted`, `palette.lightMuted` and `palette.onDominant` hold the
colours of the nearest artwork — the item or page palette a slot supplied, then
the collection cover, then the playing track. Write `@palette.dominant` as a
`color` value to tint a node from the cover.

**Repeating collections.** `list` draws its single child (or its children as
a column) once per entry of a bound collection. `direction: "horizontal"`
draws the same entries as a sideways-scrolling shelf; the default is
vertical. The bound value must be a list of host objects, not display
strings:

```json
{
  "type": "list",
  "bind": "collection.tracks",
  "limit": 100,
  "gap": 4,
  "align": "stretch",
  "children": [
    {
      "type": "row",
      "gap": 12,
      "align": "center",
      "children": [
        {"type": "text", "bind": "item.number", "size": "sm", "color": "@mutedForeground"},
        {"type": "image", "src": "item.artwork", "width": 40, "height": 40, "radius": 4},
        {
          "type": "column",
          "gap": 2,
          "children": [
            {"type": "text", "bind": "item.title"},
            {"type": "text", "bind": "item.artist", "size": "sm", "color": "@mutedForeground"}
          ]
        },
        {
          "type": "button",
          "label": "Play",
          "action": {"type": "playItem"}
        }
      ]
    }
  ]
}
```

`limit` defaults to 200 and caps at 500; the collection is truncated, never
paged. Inside the template every `item.*` binding resolves against the current
entry. The host publishes `item.index` (0-based), `item.number` (1-based),
`item.kind` (`track`, `album`, `artist`, `playlist` or `download`) and
`item.playing`; the fields below are present when the entry's type has them:

| Entry | Fields |
|---|---|
| track / download | `id`, `title`, `name`, `artist`, `artistId`, `album`, `albumId`, `artwork`, `duration`, `uri`, `explicit`; downloads add `status`, `size` |
| album | `id`, `title`, `name`, `artist`, `artistId`, `artwork`, `uri`, `releaseDate`, `year`, `trackCount`, `label`, `genres` |
| artist | `id`, `title`, `name`, `artwork`, `uri`, `followers`, `genres` |
| playlist | `id`, `title`, `name`, `description`, `owner`, `ownerId`, `artwork`, `uri`, plus `collaborative`, `public` when full |

A map entry publishes its keys under `item.<key>`. Item actions receive the
entry itself: `playItem` queues the bound list and starts at the tapped row
(or jumps to a track already in the queue), `openItem` navigates to the
entry's page, `likeItem` toggles a track's favourite, and `downloadItem`
queues it for download. The host injects `item`, `index` and `items` into the
action's args; a theme does not write them.

**Filtering a collection.** `list` and `virtualList` take a `filter` spec:
`{"bind": "search.query", "fields": ["title", "artist"]}`. The host filters
rows itself — a case- and diacritic-insensitive substring match over the named
`item.*` fields; omit `fields` to match every display field. The query is
debounced by 150 ms, so a text field bound to the same value does not rebuild
the list on every keystroke. `limit` applies after filtering.

**Data display (v4).** `virtualList` is `list` with a lazy viewport: it takes
`itemExtent` (the fixed row height, so it measures without laying out every
row) and mounts `overscan` extra rows beyond the edge. Up to 10 000 rows are
addressable and only the visible window is built, so a long queue costs the
same as a short one. `table` draws `columns` from item fields (`title`,
`artist`, `duration`, …) unless a `rowTemplate` takes over the row;
`stickyHeader` pins the header inside the table's own scroll view and
`sortable` sorts host-side on a column key — one click ascending, the next
descending. `tree` reads nested entries from a binding through
`labelKey`/`childrenKey` and keeps its expand state in the host, seeded by
`expandedKey`. `accordion` holds titled sections (single-open unless
`multiple`), `collapsible` is one titled section that may follow `openBind`,
and `carousel` pages through a bound collection with dot indicators and
optional 5-second `autoplay`. All of them reuse the same `item.*` bindings and
item actions as `list`.

**Small displays (v4).** `badge` is a compact label whose `variant` picks
primary, secondary, outline or destructive; `chip` is a selectable pill filled
while `selectedBind` is truthy; `avatar` shows `src` or a `fallback` initial
at `size`. `skeleton` pulses `count` placeholder blocks, `spinner` turns a
ring, and both hold still when the platform asks for reduced motion.
`breadcrumb` draws `label` items separated by chevrons and fires each item's
`action`; `pagination` renders prev/next and nearby numbers around `pageBind`,
firing the node's actions with `$value` replaced by the chosen page.

**Page bindings.** The content slots below replace a page's body and publish
that page's data. These names are open-ended, like `item.*`, and resolve only
where the host publishes them:

| Slot | Bindings |
|---|---|
| `home.content` | `home.greeting`, `home.recent`, `home.newReleases`, `home.browse` |
| `collection.content`, `collection.header`, `collection.before_tracks`, `collection.after_tracks` | `collection.id`, `kind`, `title`, `description`, `owner`, `ownerImage`, `artwork`, `route`, `share`, `liked`, `tracks`, `trackCount` |
| `artist.content`, `artist.header` | `artist.id`, `name`, `artwork`, `followers`, `genres`, `topTracks`, `albums`, `related` |
| `search.content` | `search.query`, `tracks`, `albums`, `artists`, `playlists` |
| `library.content` | `library.playlists`, `albums`, `artists` |
| `library.local.content` | `library.folders` (`{path, name, type}`), `library.counts` (`folders`) |
| `queue.content` | `queue.tracks`, `currentIndex`, `count` |
| `downloads.content` | `downloads.items`, `count` |
| `stats.content` | `stats.period`, `minutes`, `tracks`, `artists`, `albums`, `playlists`, `fees`, `topTracks`, `topAlbums`, `topPlaylists` |

A page-level slot whose name is absent leaves the host's own body in place.
`collection.content` and `artist.content` replace only the scrolling body;
the host keeps its titlebar and back button. `collection.header`,
`collection.before_tracks` and `collection.after_tracks` are separate seams
for use alongside the host's body. `home.content` replaces the whole home
body (including the host's own search row), so a theme that fills it draws
its own top bar and links into search with `navigate`. `search.content`
replaces the result area only — the host keeps its scope chips, and a theme
that fills it can draw its own `textField` and `button` above the results.

**Image sources:** `player.artwork`, `user.avatar`, `albumArt` (the original
spelling, kept as an alias), an `asset://` path, or any binding that holds an
image URL (`item.artwork`, `collection.artwork`, `artist.artwork`, …).

**Actions:** `navigate`, `playPause`, `next`, `previous`, `seek`,
`setVolume`, `setShuffle`, `setLoopMode`, `like`, `download`, `openSettings`,
`openLyrics`, `openQueue`, `openDownloads`, `toast`, `plugin`, `playItem`,
`playCollection`, `openItem`, `likeItem`, `downloadItem`, `setQuery`,
`clearQuery`, `setSetting`, `toggleSetting`, `copy`, `refresh`,
`pinItem`, `unpinItem`,
`toggleSidebar`, `toggleAside`, `toggleRegion`, and the UI-local `dismiss`.
`toggleSidebar` flips `app.sidebarCollapsed` (Ctrl/Cmd+B); `toggleAside` flips
`app.asideOpen` (Ctrl/Cmd+Shift+B); `toggleRegion` takes `{id: "sidebar" |
"aside"}` and routes to the same two preferences so a theme's own chrome does
not need to know which region the user means. `pinItem`/`unpinItem` take
`{item, target?}` and follow the pin-target rules in §4. A node may carry one
`action` or a list under `actions` (up to four,
in order). `playCollection` plays the page's own track list
(`collection.tracks` or `artist.topTracks`), which is how a theme's content slot
keeps a working play button. `dismiss` closes the nearest dialog, sheet or
popover and never reaches the host; outside an overlay it is forwarded like any
other action, so a theme that relies on it should only place it inside one.

`setQuery`/`clearQuery` write a search scope (`{scope, value}`; the scope
defaults to `default`) published as `search.query` and `search.<scope>.query`,
so a theme can own its own search field and read it back with `bind`.
`setSetting`/`toggleSetting` write `{key, value}` and publish it as
`setting.<key>`, letting a theme keep a toggle across the rebuild its action
causes. `copy` puts `{text}` on the clipboard. `refresh` takes
`{scope: "library" | "theme" | "all"}` and re-reads the saved library or the
theme definition.

**Slots** (the only names a theme may use): `sidebar.content`,
`sidebar.library`, `sidebar.header`, `sidebar.footer`, `sidebar.nav.before`,
`sidebar.nav.after`, `sidebar.library.before`, `sidebar.library.after`,
`sidebar.pins.before`, `sidebar.pins.after`, `aside.content`,
`player.leading`, `player.controls`, `player.trailing`,
`player.progress`, `stage.center`, `stage.below`, `app.overlay`,
`shell.before`, `shell.after`, `home.before_sections`, `home.after_sections`,
`home.content`,
`lyrics.header`, `lyrics.after_tabs`, `settings.before`, `settings.after`,
`collection.content`, `collection.header`, `collection.before_tracks`,
`collection.after_tracks`, `artist.content`, `artist.header`,
`search.content`, `library.content`, `library.local.content`,
`queue.content`, `downloads.content`,
`stats.content`.
A shell that declares `custom` regions adds exactly those `slot` names to the
vocabulary (`bar.bottom`), never a wildcard. `sidebar.content` replaces the
whole sidebar body (host keeps the width,
divider, clearance and docked player) when `layout.sidebar` is `theme`;
`sidebar.library` replaces the label, tiles and trailing drop zone of the
library group while the before/after slots and pins stay host-owned. Both are
ignored in the icon-only rail. `aside.content` fills the host right panel.
`library.local.content` replaces the local-library body and its add/delete
controls, so a theme that fills it draws its own folder list.
The two `stage.*` slots are where a `dock: "stage"` player puts its content.

### 7. A theme's own UI

A theme may answer with its UI instead of carrying it in the payload:

```hetu
class MyThemeApi {
  fun getTheme() { /* the colours */ }

  fun getUi() {
    return {'specVersion': 2, 'slots': { /* … */ }}
  }

  fun onUiAction(id, payload) {
    if (id == 'refresh') { return this.getUi() }
    return null
  }
}
```

`getUi()` is the same document as the `ui` block. `onUiAction()` is how the
theme answers a button that carries a `plugin` action: the host hands over an
id and a payload, and the theme answers with a new UI specification or with
nothing.

#### Previewing a slot (v4)

A slot can be built outside the running app, with a fixed binding snapshot, so
the UI can be checked without the player, database or plugin stack:

```dart
ThemeSlot(
  'sidebar.content',
  bindings: const ThemeUiBindings({
    'theme.name': 'My Theme',
    'player.title': 'Sample track',
  }),
  fallback: const Text('Host sidebar'),
)
```

`ThemePageContent` takes the same snapshot through `liveBindings:` and still
merges the page's own bindings over it, which is how the per-page fixtures
(`test/user_local_library_slot_test.dart`, `test/theme_ui_phase5_test.dart`)
render a slot without the host page. The host renders live providers when the
snapshot is omitted. `conformance/draft/v4-layout-regions.json` is the
end-to-end fixture: it fills all three regions and the local library body, and
is validated by `themes/test/v4_layout_regions_test.dart`.

#### Render points (v4)

A slot replaces host chrome that has a name. A **render point** replaces the
pixels of a host widget that keeps its own behaviour — the search field,
dropdown rows, context-menu rows, and (as those surfaces ship) queue and table
rows. Map the point to a template in `ui.renderPoints`:

```json
{
  "ui": {
    "templates": {
      "searchRowTpl": {
        "children": [
          {"type": "image", "src": "item.artwork", "width": 32, "height": 32, "radius": 6},
          {"type": "text", "bind": "item.title", "size": "sm"}
        ]
      }
    },
    "renderPoints": {
      "search.suggestion.item": "searchRowTpl"
    }
  }
}
```

The host wraps the template in its own gesture, focus and keyboard handling.
A template is **visual only**: it cannot change what a row does, and it cannot
write the context bindings. `components.*` styles still apply underneath, so a
theme can restyle without replacing the row.

The v4.0 catalogue is closed:

| Render point | Context bindings | Host keeps |
|---|---|---|
| `search.field` | `search.query`, `search.loading`, `search.hasQuery` | controller, debounce, focus |
| `search.suggestions` | `search.suggestions`, `search.selectedIndex`, `search.loading` | anchor, width clamp, dismissal |
| `search.suggestion.item` | `item.*`, `search.selectedIndex` | activation, keyboard |
| `search.suggestion.group` | `group.*` | ordering |
| `search.empty` | `search.query` | — |
| `search.loading` | `search.query` | — |
| `search.recent` | `search.recent` | persistence |
| `contextMenu.container` | `menu.count` | position, dismissal |
| `contextMenu.item` | `menu.*` | activation, keyboard, submenu |
| `contextMenu.separator` | — | — |
| `contextMenu.submenu` | `menu.*` | position |
| `library.playlist.item` | `item.*` | activation, drag |
| `library.playlist.group` | `group.*` | grouping |
| `library.playlist.empty` | — | — |
| `queue.item` | `item.*` | reorder, activation |
| `table.header` | `column.*` | sort |
| `table.row` | `item.*`, `row.index` | selection |
| `player.trackDetails` | `player.*`, `palette.*` | — |
| `toast.item` | `toast.*` | lifetime |

Points whose host surface does not exist in this tree yet (`library.*`,
`queue.*`, `table.*`, `player.trackDetails`, `toast.item`, and the remaining
`contextMenu.*` points) are accepted and validated, but wiring lands with the
surface in a later phase.

Rules the host enforces:

1. The catalogue is closed and versioned. An id outside it is a validator
   warning and is ignored at runtime.
2. A render point names a template in `ui.templates`. A missing template warns
   and the host default is used.
3. A template the host cannot render — a reference cycle, nesting deeper than
   8 expansions, or a `hostWidget` anywhere inside — is an error in the build
   and falls back to the host default at runtime, logged once per point.
4. A template with zero children means "draw nothing"; it does **not** fall
   back. Use an empty template to remove a group header or an empty state.
5. Context bindings are read-only and supplied per point; the field, row and
   group stay host-owned.

For search specifically: `search.field` and `search.suggestions` are painted
as background chrome behind the real `TextField` and host rows, so typing and
pointer handling stay intact. `search.suggestion.item` replaces only the row
content inside the host button; the highlight, tap and keyboard selection
remain. `search.recent` is the recent-group header; the host keeps its
"Clear all" button and recent-query persistence. `search.empty` has no host
default (the see-all footer is separate), and `search.loading` falls back to
the host spinner when no template is set.

### 8. Assets

The files a theme ships live inside the plugin's own directory and are named
with `asset://` paths:

```json
"assets": {
  "images": [{"path": "asset://images/aurora.png", "kind": "image", "role": "branding.logo"}]
}
```

Fonts are assets too, and a theme may ship up to eight of them:

```json
"typography": {
  "fonts": [
    {"family": "Silkscreen", "asset": "asset://fonts/Silkscreen-Regular.ttf", "weight": 400}
  ],
  "family": "Silkscreen"
}
```

The host loads them under the family name the theme uses, so `fontFamily` in
a typography style or a component style resolves to the shipped file.

The build checks that every path a theme names is a file it ships, and warns
about files it ships but never uses. The host resolves the paths — never the
theme — and only inside the plugin's directory.

## Rules the app enforces

The app sanitizes what it receives, and a theme that leans on the clamps gets
a different theme than the one it wrote. The build reports every clamp:

- `surfaces.opacity` and `background.opacity`: 0..1
- `surfaces.blur` and `background.blur`: 0..100
- `radius.small` / `radius.medium`: 0..48, `radius.large`: 0..64
- `density`: 0.7..1.5, and 0 reads as 1.0
- `tokens.cardWidth`: 80..400, `cardHeight`: 120..600, `artistCardWidth`:
  80..480, `artistCardHeight`: 120..640, `gutter`: 0..40
- `tokens.fontFamily`: a family the platform already has; a theme cannot load
  a font file
- `background.source`: `none`, `albumArt` or `shell`
- `layout.chrome`: `flat` or `inset`, `layout.nav`: `labels` or `rail`,
  `layout.progress`: `inline` or `below`, `layout.sidebar`: `host` or `theme`,
  `layout.aside`: `none` or `theme`
- `sidebarWidth` / `asideWidth`: 0..1000 logical px, theme width only
- `resizable` panes: `initial`, `min`, `max` 0..4000; `storageKey` must match
  `^[a-z][a-z0-9_.-]{0,63}$`
- `background.transparent`: a boolean, and it is tri-state — `true` asks for
  the compositor, `false` vetoes it, absent leaves it to the host setting
- component `radius`: 0..999 (999 means "fully round", the host clamps it to
  the shorter side)
- component `padding` / `margin` / `gap`: 0..48, `borderWidth`: 0..8,
  `height` / `width`: 0..400, `surfaceOpacity`: 0..1, `surfaceBlur`: 0..64,
  `fontSize`: 8..48, `iconSize`: 8..64
- typography `fontSize`: 8..96, `fontWeight`: 100..900, `height`: 0.8..2.4,
  `letterSpacing`: -2..8
- spacing and motion tokens: 0..96 and 0..1000
- `scale`: 0.5..2
- icon sizes: 8..64
- a UI tree: 16 levels deep, 200 nodes per slot, 1000 in total, 4 actions per
  node, 500 characters of text; `list.limit`: 1..500 (200 when absent),
  `virtualList.limit`: 1..10000, table rows: 500 static / 10000 sticky,
  table columns: 32, tree nodes: 500, accordion items: 32, carousel items: 50,
  breadcrumb items: 16, skeleton blocks: 50
- up to 48 slots (a theme only names the ones it fills)

## What a theme cannot do

- It cannot read files or reach the network. The app's VM has no bindings for
  either. `asset://` paths are resolved by the app, inside the plugin's own
  directory.
- It cannot change the app's package id, launcher name or icon.
- It cannot collect text silently. `textField`/`textArea` exist, but every
  value leaves through an action the theme declares; the host never hands the
  field's contents to the theme as a stream, and the theme cannot read files or
  reach the network.
- It cannot force the volume control back on after the user hid it, and a
  `full`/`floating` dock never overrides a docked preference; only `compact`
  asks for the docked shape.
- It cannot remove the host's name, version or licence from the About page.
