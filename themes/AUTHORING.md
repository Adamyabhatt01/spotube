# Authoring a theme

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
`lead` `large` `small` `muted` `xSmall` `xLarge` `x2Large` … `x9Large`.

A colour is a hex value or a `@role` reference (`@primary`, `@cardForeground`,
`@chart3`, …).

### 3. Components

Every shadcn component the app draws with may be restyled, and the buttons may
be restyled per variant:

```json
"components": {
  "buttons": {
    "primary": {"radius": 10, "padding": 12, "fontWeight": 600, "iconSize": 18},
    "ghost": {"radius": 10, "padding": 8},
    "destructive": {"background": "@destructive", "foreground": "@destructiveForeground"}
  },
  "card": {"radius": 16, "padding": 16, "surfaceOpacity": 0.9, "surfaceBlur": 12},
  "input": {"radius": 8, "height": 36, "borderColor": "@input"},
  "dialog": {"radius": 16, "padding": 24}
}
```

The groups are `card`, `input`, `tabs`, `nav`, `tooltip`, `badge`, `select`,
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
  "navItems": ["home", "radio", "stats", "search"],
  "navbarItems": ["home", "search", "radio", "library", "stats"],
  "libraryItems": ["playlists", "artists", "albums", "local_library"],
  "player": {
    "dock": "full",
    "showTrackDetails": true, "showActions": true,
    "showVolume": true, "showLyrics": true, "showProgress": true
  },
  "home": {"sections": ["recent", "featured", "new_releases", "browse"]},
  "settings": {"sections": ["accounts", "appearance", "playback", "about"]},
  "titlebar": {"height": 40, "padding": 12, "showBack": true},
  "splash": {"logo": "asset://images/splash.png", "text": "My Theme"},
  "enforce": ["playerDock"],
  "responsive": {"compact": {"nav": "rail", "player": {"showVolume": false}}}
}
```

**The user's own settings win by default.** A theme takes the layout over
only where it says so in `enforce`: `nav`, `navItems`, `libraryItems`,
`navOrder`, `player`, `playerDock`, `volume`, `home`, `settings`, `titlebar`,
`splash`. Without `enforce`, a theme that hides the volume control cannot
override a user who chose to keep it.

`responsive` holds up to four variants (`compact`, `medium`, `expanded`, or
any name), each overriding the same fields.

### 5. Branding

```json
"branding": {
  "appName": "Aurora",
  "shortName": "Aurora",
  "tagline": "Your music, your shell",
  "wordmark": {"text": "Aurora", "fontFamily": "Cookie"},
  "logo": "asset://images/logo.png",
  "titlebarTitle": "Aurora",
  "windowTitle": "Aurora",
  "aboutName": "Aurora",
  "notificationName": "Aurora",
  "showHostAttribution": true
}
```

The host always keeps its name, version and licence on the About page,
whatever a theme says.

### 6. Content

A theme may put content in the app's surfaces. The UI is a tree of nodes:

```json
"ui": {
  "specVersion": 1,
  "slots": {
    "sidebar.footer": {
      "children": [
        {
          "type": "row",
          "gap": 8,
          "children": [
            {"type": "text", "bind": "player.title", "maxLines": 1},
            {
              "type": "button",
              "label": "Lyrics",
              "icon": "lyrics",
              "action": {"type": "navigate", "args": {"target": "lyrics"}}
            }
          ]
        }
      ]
    }
  },
  "screens": {
    "now-playing": {
      "title": "Now playing",
      "showBack": true,
      "children": [
        {"type": "image", "src": "albumArt", "width": 220, "height": 220},
        {"type": "text", "bind": "player.title", "size": "xl"}
      ]
    }
  },
  "templates": {
    "trackRow": {"params": ["title"], "children": [{"type": "text", "bind": "player.title"}]}
  }
}
```

**Nodes:** `row`, `column`, `stack`, `wrap`, `padding`, `align`, `expanded`,
`scroll`, `text`, `icon`, `image`, `button`, `card`, `divider`, `spacer`,
`gap`, `conditional`, `template`. There is no text input: a theme renders and
reacts, it does not collect.

**Bindings:** `player.title`, `player.artist`, `player.album`,
`player.artwork`, `player.playing`, `player.loop`, `player.shuffled`,
`player.position`, `player.duration`, `player.volume`, `user.name`,
`user.avatar`, `app.version`, `app.brightness`, `app.themeMode`,
`clock.now`.

**Actions:** `navigate`, `playPause`, `next`, `previous`, `seek`,
`setVolume`, `setShuffle`, `setLoopMode`, `like`, `download`, `openSettings`,
`openLyrics`, `openQueue`, `openDownloads`, `toast`, `plugin`.

**Slots** (the only names a theme may use): `sidebar.header`,
`sidebar.footer`, `sidebar.nav.before`, `sidebar.nav.after`,
`sidebar.library.before`, `sidebar.library.after`, `sidebar.pins.before`,
`sidebar.pins.after`, `player.leading`, `player.controls`, `player.trailing`,
`player.progress`, `app.overlay`, `shell.before`, `shell.after`,
`home.before_sections`, `home.after_sections`, `lyrics.header`,
`lyrics.after_tabs`, `settings.before`, `settings.after`.

### 7. A theme's own UI

A theme may answer with its UI instead of carrying it in the payload:

```hetu
class MyThemeApi {
  fun getTheme() { /* the colours */ }

  fun getUi() {
    return {'specVersion': 1, 'slots': { /* … */ }}
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

### 8. Assets

The files a theme ships live inside the plugin's own directory and are named
with `asset://` paths:

```json
"assets": {
  "images": [{"path": "asset://images/aurora.png", "kind": "image", "role": "branding.logo"}]
}
```

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
  `layout.progress`: `inline` or `below`
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
- a UI tree: 12 levels deep, 200 nodes per slot, 1000 in total, 4 actions per
  node, 500 characters of text

## What a theme cannot do

- It cannot read files or reach the network. The app's VM has no bindings for
  either. `asset://` paths are resolved by the app, inside the plugin's own
  directory.
- It cannot change the app's package id, launcher name or icon.
- It cannot collect text. There is no input in a theme's UI.
- It cannot take the user's settings away, unless it lists the key in
  `layout.enforce`.
- It cannot remove the host's name, version or licence from the About page.
