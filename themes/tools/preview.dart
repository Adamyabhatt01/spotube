import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Renders a theme payload to one standalone HTML file.
///
/// The host has no v3 renderer yet, so a theme author otherwise writes a
/// layout blind. This is not the host: it is a faithful-enough reader of the
/// same contract — same bindings, same node props, same tokens — that turns a
/// payload and its assets into something a person can look at. Buttons call a
/// preview stub; the play button really does start and stop the record.
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('payload', help: 'Read this payload instead of conformance/<id>.json.')
    ..addOption('out', help: 'Write here instead of dist/preview/<id>.html.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }
  if (options['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final id = (options.rest.isEmpty ? 'obsidian' : options.rest.first);
  final repoRoot =
      p.dirname(p.dirname(p.absolute(Platform.script.toFilePath())));
  final themeDir = Directory(p.join(repoRoot, 'themes', id));
  final payloadFile = File(
    (options['payload'] as String?) ??
        p.join(repoRoot, 'conformance', '$id.json'),
  );
  if (!payloadFile.existsSync()) {
    stderr.writeln(
      'no payload at ${payloadFile.path} — run tools/export.dart first',
    );
    exitCode = 66;
    return;
  }
  if (!themeDir.existsSync()) {
    stderr.writeln('no theme directory at ${themeDir.path}');
    exitCode = 66;
    return;
  }

  final payload =
      jsonDecode(payloadFile.readAsStringSync()) as Map<String, dynamic>;
  final html = PreviewBuilder(id: id, themeDir: themeDir.path, payload: payload)
      .build();
  final out = File(
    (options['out'] as String?) ??
        p.join(repoRoot, 'dist', 'preview', '$id.html'),
  );
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(html);
  stdout.writeln('${out.path}  (${(html.length / 1024).round()} kB)');
}

/// The sample state the preview resolves bindings against.
const _sample = <String, Object?>{
  'player.title': 'OBSIDIAN HEARTS',
  'player.artist': 'The Endermen',
  'player.album': 'Deep Dark',
  'player.playing': true,
  'player.loop': 'all',
  'player.shuffled': false,
  'player.position': 83.0,
  'player.duration': 214.0,
  'player.volume': 0.72,
  'user.name': 'Steve',
  'app.version': '4.6.0',
  'app.brightness': 'dark',
  'app.themeMode': 'dark',
  'clock.now': '23:58',
};

class PreviewBuilder {
  PreviewBuilder({
    required this.id,
    required this.themeDir,
    required this.payload,
  });

  final String id;
  final String themeDir;
  final Map<String, dynamic> payload;

  late final Map<String, dynamic> _ui =
      (payload['ui'] as Map?)?.cast<String, dynamic>() ?? const {};
  late final Map<String, dynamic> _light =
      (payload['light'] as Map).cast<String, dynamic>();
  late final Map<String, dynamic> _dark =
      (payload['dark'] as Map).cast<String, dynamic>();
  late final Map<String, String> _assets = _loadAssets();
  late final Map<String, String> _fonts = _loadFonts();

  String build() {
    final brand = (payload['branding'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final name = (brand['appName'] as String?) ?? id;
    final version = _manifestVersion();

    return '''<!doctype html>
<html lang="en" data-mode="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$name — theme preview</title>
<style>
${_fontFaces()}
${_variables()}
${_baseCss()}
${_shellCss()}
${_nodeCss()}
${_componentCss()}
</style>
</head>
<body class="is-playing">
<header class="preview-bar">
  <div class="preview-title">
    <span class="preview-mark">${_img('asset://images/logo.png', '24px', 'preview-mark-img')}</span>
    <span><strong>$name</strong> <span class="dim">theme preview · v$version</span></span>
  </div>
  <div class="preview-actions">
    <button class="chip active" data-screen-button="stage" onclick="showScreen('stage')">Stage</button>
    ${_screenButtons()}
    <button class="chip" onclick="togglePlay()" id="play-button">PAUSE RECORD</button>
    <button class="chip" onclick="toggleMode()" id="mode-button">MODE: END STONE</button>
  </div>
</header>

<div class="shell">
  <aside class="sidebar">
    ${_slot('sidebar.header')}
    <nav class="mock-nav">
      ${_slot('sidebar.nav.before')}
      ${_navItems()}
      ${_slot('sidebar.library.before')}
      ${_libraryItems()}
    </nav>
    <div class="sidebar-footer">${_slot('sidebar.footer')}</div>
  </aside>

  <main class="page">
    <section class="screen" data-screen="stage">
      <div class="page-top">
        <div class="page-crumb">HOME <span class="dim">/ STAGE</span></div>
        <div class="mock-dots"><span></span><span></span><span></span></div>
      </div>
      ${_slot('home.before_sections')}
      <div class="stage">
        <div class="stage-center">${_slot('stage.center')}</div>
        <div class="stage-below">${_slot('stage.below')}</div>
      </div>
      ${_slot('home.after_sections')}
      ${_componentSheet()}
    </section>

    ${_screens()}

    <section class="screen" data-screen="palette">
      <div class="page-top">
        <div class="page-crumb">THEME <span class="dim">/ PALETTE</span></div>
        <div class="mock-dots"><span></span><span></span><span></span></div>
      </div>
      <div class="section-head">PALETTE</div>
      <div class="palettes">
        ${_palette('dark', _dark)}
        ${_palette('light', _light)}
      </div>
      <div class="section-head">TOKENS</div>
      ${_tokens()}
    </section>
  </main>
</div>

<div id="toast" class="toast"></div>
<script>
${_script()}
</script>
</body>
</html>
''';
  }

  // ---------------------------------------------------------------- assets

  Map<String, String> _loadAssets() {
    final dir = Directory(p.join(themeDir, 'assets'));
    if (!dir.existsSync()) return const {};
    final assets = <String, String>{};
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final relative =
          p.relative(file.path, from: dir.path).replaceAll(r'\', '/');
      assets['asset://$relative'] = _dataUri(file);
    }
    return assets;
  }

  Map<String, String> _loadFonts() {
    final fonts = <String, String>{};
    final entries = ((payload['typography'] as Map?)?['fonts'] as List?) ??
        const [];
    for (final entry in entries.cast<Map>()) {
      final asset = entry['asset'];
      if (asset is! String) continue;
      final uri = _assets[asset];
      if (uri != null) {
        fonts['${entry['family']}|${entry['weight'] ?? 400}|${entry['style'] ?? 'normal'}'] =
            uri;
      }
    }
    return fonts;
  }

  String _dataUri(File file) {
    final ext = p.extension(file.path).toLowerCase();
    final mime = switch (ext) {
      '.png' => 'image/png',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.svg' => 'image/svg+xml',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.txt' => 'text/plain;charset=utf-8',
      _ => 'application/octet-stream',
    };
    return 'data:$mime;base64,${base64Encode(file.readAsBytesSync())}';
  }

  String _manifestVersion() {
    final file = File(p.join(themeDir, 'plugin.json'));
    if (!file.existsSync()) return '?';
    try {
      final manifest =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (manifest['version'] as String?) ?? '?';
    } on FormatException {
      return '?';
    }
  }

  // ------------------------------------------------------------------- css

  String _fontFaces() {
    final buffer = StringBuffer();
    for (final entry in _fonts.entries) {
      final parts = entry.key.split('|');
      buffer.writeln('''
@font-face {
  font-family: '${_escape(parts[0])}';
  src: url('${entry.value}') format('truetype');
  font-weight: ${parts[1]};
  font-style: ${parts[2]};
  font-display: swap;
}''');
    }
    return buffer.toString();
  }

  String _variables() {
    final buffer = StringBuffer();
    void vars(Map<String, dynamic> palette) {
      for (final entry in palette.entries) {
        buffer.writeln('  --${entry.key}: ${_cssColor(entry.value.toString())};');
      }
    }

    buffer.writeln(':root, [data-mode="dark"] {');
    vars(_dark);
    buffer.writeln('  --font-body: ${_family((payload['typography'] as Map?)?['family'])};');
    buffer.writeln('  --font-brand: ${_family((payload['typography'] as Map?)?['brandFamily'])};');
    buffer.writeln('}');
    buffer.writeln('[data-mode="light"] {');
    vars(_light);
    buffer.writeln('}');
    return buffer.toString();
  }

  String _baseCss() {
    final background = (payload['background'] as Map?) ?? const {};
    final scale = (background['scale'] as num?)?.toInt() ?? 1;
    final tile = background['source'] == 'asset' && background['asset'] is String
        ? _assets[background['asset']] ?? ''
        : '';
    final tileSize = 32 * scale;
    return '''
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; }
body {
  font-family: var(--font-body), monospace;
  background-color: var(--background);
  background-image: ${tile.isEmpty ? 'none' : "url('$tile')"};
  background-size: ${tileSize}px ${tileSize}px;
  background-repeat: repeat;
  color: var(--foreground);
  font-size: 16px;
  line-height: 1.35;
  -webkit-font-smoothing: none;
  font-smooth: never;
}
.dim { opacity: .62; }
.preview-bar {
  position: sticky; top: 0; z-index: 20;
  display: flex; align-items: center; justify-content: space-between; gap: 16px;
  padding: 10px 16px;
  background: color-mix(in srgb, var(--background) 88%, transparent);
  border-bottom: 2px solid var(--border);
  backdrop-filter: blur(6px);
}
.preview-title { display: flex; align-items: center; gap: 10px; }
.preview-title strong { font-family: var(--font-brand), monospace; letter-spacing: 1px; }
.preview-mark { display: inline-flex; width: 24px; height: 24px; }
.preview-mark-img { width: 24px; height: 24px; image-rendering: pixelated; }
.preview-actions { display: flex; gap: 6px; flex-wrap: wrap; }
.chip {
  font-family: var(--font-brand), monospace;
  font-size: 11px; letter-spacing: .5px;
  color: var(--foreground); background: var(--card);
  border: 2px solid var(--border); border-radius: 0;
  padding: 6px 10px; cursor: pointer;
  box-shadow: inset 2px 2px 0 rgba(255,255,255,.10), inset -2px -2px 0 rgba(0,0,0,.35);
}
.chip:hover { border-color: var(--primary); color: var(--primary); }
.chip.active { border-color: var(--primary); color: var(--primary); }
@media (max-width: 900px) {
  .preview-bar { align-items: flex-start; flex-direction: column; }
}
''';
  }

  String _shellCss() => '''
.shell { display: grid; grid-template-columns: 248px minmax(0, 1fr); min-height: calc(100vh - 47px); }
.sidebar {
  display: flex; flex-direction: column; gap: 16px;
  padding: 18px 14px;
  background: var(--sidebar);
  color: var(--sidebarForeground);
  border-right: 2px solid var(--sidebarBorder);
}
.mock-nav { display: flex; flex-direction: column; gap: 8px; flex: 1; }
.sidebar-footer { margin-top: auto; }
.mock-item {
  display: flex; align-items: center; gap: 10px;
  padding: 7px 8px;
  font-size: 18px;
  border: 2px solid transparent;
  cursor: default;
}
.mock-item.active { background: var(--sidebarAccent); color: var(--sidebarAccentForeground); border-color: var(--sidebarBorder); }
.mock-item img { width: 18px; height: 18px; image-rendering: pixelated; }
.page { padding: 18px 26px 60px; min-width: 0; }
.page-top { display: flex; align-items: center; justify-content: space-between; border-bottom: 2px solid var(--border); padding-bottom: 10px; margin-bottom: 20px; }
.page-crumb { font-family: var(--font-brand), monospace; letter-spacing: 1.5px; font-size: 13px; }
.mock-dots { display: flex; gap: 5px; }
.mock-dots span { width: 8px; height: 8px; background: var(--primary); display: block; }
.stage { display: flex; flex-direction: column; align-items: center; gap: 22px; padding: 26px 12px 34px; }
.stage-center { display: flex; align-items: center; justify-content: center; min-height: 360px; }
.stage-below { display: flex; flex-direction: column; align-items: center; gap: 8px; text-align: center; }
.screen[hidden] { display: none; }
.section-head {
  font-family: var(--font-brand), monospace;
  font-size: 12px; letter-spacing: 2px; color: var(--primary);
  border-bottom: 2px solid var(--border); padding-bottom: 6px; margin: 28px 0 14px;
}
.palettes { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }
.palette { border: 2px solid var(--border); background: var(--card); }
.palette h3 { margin: 0; padding: 10px 12px; font-family: var(--font-brand), monospace; font-size: 12px; letter-spacing: 1.5px; border-bottom: 2px solid var(--border); }
.swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(118px, 1fr)); gap: 1px; background: var(--border); }
.swatch { padding: 7px 8px; font-size: 11px; font-family: var(--font-brand), monospace; line-height: 1.25; min-height: 48px; overflow-wrap: anywhere; }
.swatch small { display: block; opacity: .75; font-size: 9px; }
.tokens { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 10px; }
.token { border: 2px solid var(--border); background: var(--card); padding: 10px; font-size: 13px; }
.token code { color: var(--primary); font-family: var(--font-brand), monospace; font-size: 11px; }
.toast {
  position: fixed; left: 50%; bottom: 22px; transform: translateX(-50%) translateY(20px);
  background: var(--popover); color: var(--popoverForeground);
  border: 2px solid var(--primary); padding: 9px 14px;
  font-family: var(--font-brand), monospace; font-size: 11px; letter-spacing: .5px;
  opacity: 0; pointer-events: none; transition: opacity .12s steps(2), transform .12s steps(2);
  z-index: 50;
}
.toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
@media (max-width: 900px) {
  .shell { grid-template-columns: 1fr; }
  .sidebar { display: none; }
  .palettes { grid-template-columns: 1fr; }
}
''';

  String _nodeCss() => '''
.node-row { display: flex; flex-direction: row; }
.node-column { display: flex; flex-direction: column; }
.node-wrap { display: flex; flex-wrap: wrap; }
.node-stack { display: grid; place-items: center; position: relative; }
.node-stack > * { grid-area: 1 / 1; }
.node-padding { display: block; }
.node-align { display: flex; }
.node-expanded { display: flex; flex: 1 1 0; min-width: 0; min-height: 0; }
.node-scroll { overflow: auto; }
.node-text { white-space: pre-wrap; line-height: 1.25; }
.node-divider-h { width: 100%; }
.node-divider-v { align-self: stretch; height: 100%; }
.node-img { display: block; max-width: 100%; }
.node-icon { display: block; image-rendering: pixelated; }
.node-button {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  cursor: pointer; border-style: solid; font-family: var(--font-body), monospace;
  line-height: 1; white-space: nowrap;
  box-shadow: inset 2px 2px 0 rgba(255,255,255,.12), inset -2px -2px 0 rgba(0,0,0,.42);
  transition: transform .06s steps(1);
}
.node-button:active { transform: translate(1px, 1px); }
.node-button img { image-rendering: pixelated; }
.node-card { display: block; }
.card-pixel { box-shadow: inset 2px 2px 0 rgba(255,255,255,.10), inset -2px -2px 0 rgba(0,0,0,.45); }
.node-spacer { flex: 1 1 auto; }
.node-gap { flex: 0 0 auto; }
.spin { animation: obsidian-spin var(--dur, 24s) linear infinite; }
.gated { animation-play-state: paused; }
body.is-playing .gated { animation-play-state: running; }
.anim-pulse { animation: obsidian-pulse var(--dur, 2.4s) ease-in-out infinite; }
.anim-float { animation: obsidian-float var(--dur, 3s) ease-in-out infinite; }
.anim-fade { animation: obsidian-fade var(--dur, 3s) ease-in-out infinite; }
@keyframes obsidian-spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
@keyframes obsidian-pulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.035); } }
@keyframes obsidian-float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-7px); } }
@keyframes obsidian-fade { 0%,100% { opacity: .55; } 50% { opacity: 1; } }
@media (prefers-reduced-motion: reduce) {
  .spin, .anim-pulse, .anim-float, .anim-fade { animation: none !important; }
}
''';

  String _componentCss() => '''
.sheet { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; }
.sheet-box { border: 2px solid var(--border); background: var(--card); padding: 14px; }
.sheet-box h4 { margin: 0 0 10px; font-family: var(--font-brand), monospace; font-size: 11px; letter-spacing: 1.5px; color: var(--primary); }
.sheet-row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.sample-input {
  width: 100%; padding: 9px 10px; font: inherit; color: var(--foreground);
  background: var(--input); border: 2px solid var(--border); border-radius: 0;
}
.sample-badge { display: inline-block; padding: 3px 6px; border: 2px solid var(--border); background: var(--secondary); color: var(--secondaryForeground); font-family: var(--font-brand), monospace; font-size: 10px; letter-spacing: .5px; }
.sample-progress { height: 8px; background: var(--muted); border: 1px solid var(--border); }
.sample-progress span { display: block; width: 62%; height: 100%; background: var(--primary); }
''';

  // ------------------------------------------------------------------ html

  String _slot(String name) {
    final slots = (_ui['slots'] as Map?)?.cast<String, dynamic>();
    final body = slots?[name];
    if (body is! Map) return '';
    final children = body['children'];
    if (children is! List) return '';
    return children.map(_node).join('\n');
  }

  String _screens() {
    final screens = (_ui['screens'] as Map?)?.cast<String, dynamic>();
    if (screens == null) return '';
    final buffer = StringBuffer();
    for (final entry in screens.entries) {
      final screen = (entry.value as Map).cast<String, dynamic>();
      final title = _escape((screen['title'] as String?) ?? entry.key);
      buffer.writeln('''
<section class="screen" data-screen="${_escape(entry.key)}" hidden>
  <div class="page-top">
    <div class="page-crumb">${_escape(title.toUpperCase())}</div>
    <button class="chip" onclick="showScreen('stage')">BACK TO STAGE</button>
  </div>
  ${(screen['children'] as List?)?.map(_node).join('\n') ?? ''}
</section>''');
    }
    return buffer.toString();
  }

  String _screenButtons() {
    final screens = (_ui['screens'] as Map?)?.cast<String, dynamic>();
    if (screens == null) return '';
    return screens.entries
        .map((entry) =>
            '<button class="chip" data-screen-button="${_escape(entry.key)}" '
            'onclick="showScreen(\'${_js(entry.key)}\')">'
            '${_escape(((entry.value as Map)['title'] as String?) ?? entry.key)}</button>')
        .join('\n    ');
  }

  String _navItems() {
    final items = ((payload['layout'] as Map?)?['navItems'] as List?) ??
        const ['home', 'search', 'radio', 'stats'];
    return items.map((item) {
      final name = item.toString();
      final label = name[0].toUpperCase() + name.substring(1);
      final icon = _icon(name, 18);
      return '<div class="mock-item${name == 'home' ? ' active' : ''}">$icon<span>$label</span></div>';
    }).join('\n');
  }

  String _libraryItems() {
    final items = ((payload['layout'] as Map?)?['libraryItems'] as List?) ??
        const ['playlists', 'artists', 'albums'];
    return items.map((item) {
      final label = item
          .toString()
          .split('_')
          .map((part) => part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
          .join(' ');
      return '<div class="mock-item">${_icon('library', 18)}<span>$label</span></div>';
    }).join('\n');
  }

  // ------------------------------------------------------------------ node

  String _node(Object? raw) {
    if (raw is! Map) return '';
    final node = raw.cast<String, dynamic>();
    final props = <String, dynamic>{};
    final legacy = node['props'];
    if (legacy is Map) props.addAll(legacy.cast<String, dynamic>());
    for (final entry in node.entries) {
      if (entry.key == 'type' ||
          entry.key == 'children' ||
          entry.key == 'props' ||
          entry.key == 'action' ||
          entry.key == 'actions') {
        continue;
      }
      props[entry.key] = entry.value;
    }
    final children = (node['children'] as List?) ?? const [];
    final type = node['type'];

    switch (type) {
      case 'row':
        return '<div class="node-row" style="gap:${_px(props['gap'])};align-items:${_align(props['align'])};justify-content:${_justify(props['justify'])}">${children.map(_node).join()}</div>';
      case 'column':
        return '<div class="node-column" style="gap:${_px(props['gap'])};align-items:${_align(props['align'])};justify-content:${_justify(props['justify'])}">${children.map(_node).join()}</div>';
      case 'wrap':
        return '<div class="node-wrap" style="gap:${_px(props['gap'])};row-gap:${_px(props['runGap'] ?? props['gap'])};align-items:${_align(props['align'])};justify-content:${_justify(props['justify'])}">${children.map(_node).join()}</div>';
      case 'stack':
        return '<div class="node-stack" style="place-items:${_place(props['align'])};${props['fit'] == 'expand' ? 'width:100%;height:100%;' : ''}">${children.map(_node).join()}</div>';
      case 'padding':
        return '<div class="node-padding" style="padding:${_px(props['all'] ?? props['vertical'] ?? 0)} ${_px(props['all'] ?? props['horizontal'] ?? 0)}">${children.map(_node).join()}</div>';
      case 'align':
        return '<div class="node-align" style="align-items:${_align(props['align'])};justify-content:${_justify(props['align'])};${_pxPair('width', props['widthFactor'])}${_pxPair('height', props['heightFactor'])}">${children.map(_node).join()}</div>';
      case 'expanded':
        return '<div class="node-expanded" style="flex:${(props['flex'] as num?)?.toInt() ?? 1} 1 0">${children.map(_node).join()}</div>';
      case 'scroll':
        return '<div class="node-scroll" style="max-height:380px;max-width:100%;overflow-${props['direction'] == 'horizontal' ? 'x' : 'y'}:auto;padding:${_px(props['padding'])}">${children.map(_node).join()}</div>';
      case 'text':
        return _text(props);
      case 'icon':
        return _icon((props['icon'] as String?) ?? 'play', (props['size'] as num?)?.toInt() ?? 18, props['color']);
      case 'image':
        return _image(props);
      case 'button':
        return _button(props, node);
      case 'card':
        return _card(props, children);
      case 'divider':
        return props['orientation'] == 'vertical'
            ? '<div class="node-divider-v" style="border-left:${_px(props['thickness'] ?? 1)} solid ${_color(props['color'] ?? '@border')};min-height:16px"></div>'
            : '<div class="node-divider-h" style="border-top:${_px(props['thickness'] ?? 1)} solid ${_color(props['color'] ?? '@border')}"></div>';
      case 'spacer':
        return '<div class="node-spacer"></div>';
      case 'gap':
        return '<div class="node-gap" style="width:${_px(props['size'])};height:${_px(props['size'])}"></div>';
      case 'conditional':
        return _conditional(props, children);
      case 'template':
        return children.map(_node).join();
      case 'animate':
        return _animate(props, children);
      default:
        return '';
    }
  }

  String _text(Map<String, dynamic> props) {
    final bind = props['bind'];
    final value = bind is String
        ? (_sample[bind]?.toString() ?? '')
        : (props['text']?.toString() ?? '');
    final size = switch (props['size']) {
      'xs' => 11,
      'small' || 'sm' => 13,
      'md' => 16,
      'lg' => 19,
      'xl' => 24,
      '2xl' => 30,
      '3xl' => 38,
      _ => 16,
    };
    final weight = switch (props['weight']) {
      'thin' => 100,
      'light' => 300,
      'normal' => 400,
      'medium' => 500,
      'semibold' => 600,
      'bold' => 700,
      'black' => 900,
      num() => props['weight'],
      _ => 400,
    };
    final family = props['family'] == 'Silkscreen' || props['family'] == 'VT323'
        ? props['family']
        : 'var(--font-body)';
    final maxLines = props['maxLines'] as num?;
    final overflow = props['overflow'];
    final style = StringBuffer()
      ..write('font-size:${size}px;')
      ..write('font-weight:$weight;')
      ..write('font-family:$family, monospace;')
      ..write('color:${_color(props['color'] ?? '@foreground')};')
      ..write('text-align:${props['align'] ?? 'left'};')
      ..write('letter-spacing:${props['letterSpacing'] ?? 0}px;');
    if (props['uppercase'] == true) style.write('text-transform:uppercase;');
    if (maxLines != null) {
      style.write('display:-webkit-box;-webkit-box-orient:vertical;'
          '-webkit-line-clamp:${maxLines.toInt()};overflow:hidden;');
    }
    if (overflow == 'ellipsis') style.write('text-overflow:ellipsis;');
    return '<div class="node-text" style="$style">${_escape(value)}</div>';
  }

  String _image(Map<String, dynamic> props) {
    final src = props['src'] ?? props['bind'];
    final width = props['width'];
    final height = props['height'];
    final radius = props['radius'];
    final shape = props['shape'];
    final filter = props['filter'];
    final opacity = props['opacity'];
    final fit = props['fit'] ?? 'cover';
    final style = StringBuffer();
    if (width is num) style.write('width:${width.toInt()}px;');
    if (height is num) style.write('height:${height.toInt()}px;');
    if (width is num && height is num) style.write('max-width:100%;');
    if (radius is num) style.write('border-radius:${radius.toInt()}px;');
    if (shape == 'circle') style.write('border-radius:50%;');
    if (opacity is num) style.write('opacity:$opacity;');
    if (filter == 'nearest') style.write('image-rendering:pixelated;');
    final uri = _imageUri(src);
    if (uri.isEmpty) {
      return '<div class="node-img" style="$style background:var(--muted);"></div>';
    }
    if (props['tile'] == true) {
      style.write("background-image:url('$uri');background-repeat:repeat;image-rendering:pixelated;");
      return '<div class="node-img" style="$style"></div>';
    }
    return '<img class="node-img" src="$uri" alt="" style="$style;object-fit:$fit;">';
  }

  String _imageUri(Object? src) {
    if (src is! String) return '';
    if (src.startsWith('asset://')) return _assets[src] ?? '';
    if (src == 'player.artwork' || src == 'albumArt') return _coverSvg();
    if (src == 'user.avatar') return _avatarSvg();
    return '';
  }

  String _button(Map<String, dynamic> props, Map<String, dynamic> node) {
    final variant = (props['variant'] as String?) ?? 'primary';
    final style = (((payload['components'] as Map?)?['buttons'] as Map?)
            ?[variant] as Map?)
        ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final scale = switch (props['size']) {
      'small' => 0.85,
      'lg' => 1.2,
      _ => 1.0,
    };
    final iconSize = ((style['iconSize'] as num?) ?? 20) * scale;
    final background = _color(style['background'] ?? '@primary');
    final foreground = _color(style['foreground'] ?? '@primaryForeground');
    final border = _color(style['borderColor'] ?? '@primary');
    final borderWidth = (style['borderWidth'] as num?) ?? 0;
    final radius = (style['radius'] as num?) ?? 0;
    final padding = ((style['padding'] as num?) ?? 10) * scale;
    final fontSize = ((style['fontSize'] as num?) ?? 18) * scale;
    final family = style['fontFamily'] == 'Silkscreen' ? 'Silkscreen' : 'VT323';
    final action = node['action'] is Map
        ? node['action'] as Map
        : (node['actions'] is List && (node['actions'] as List).isNotEmpty
            ? (node['actions'] as List).first as Map
            : null);
    final actionType = (action?['type'] as String?) ?? '';
    final target = action?['args'] is Map
        ? ((action!['args'] as Map)['target']?.toString() ?? '')
        : '';
    final label = props['label'];
    final icon = props['icon'];
    final iconHtml = icon is String ? _icon(icon, iconSize.round(), foreground) : '';
    final labelHtml = label is String
        ? '<span>${_escape(label)}</span>'
        : '';
    return '<button class="node-button" style="background:$background;color:$foreground;'
        'border-color:$border;border-width:${borderWidth.toInt()}px;border-radius:${radius.toInt()}px;'
        'padding:${padding.round()}px ${(padding * 1.2).round()}px;font-size:${fontSize.round()}px;'
        "font-family:'$family', monospace;letter-spacing:${style['letterSpacing'] ?? 0}px;"
        'min-height:${(iconSize + padding).round()}px;" '
        'onclick="act(\'${_js(actionType)}\',\'${_js(target)}\')">$iconHtml$labelHtml</button>';
  }

  String _card(Map<String, dynamic> props, List children) {
    final style = StringBuffer()
      ..write('padding:${_px(props['padding'] ?? 0)};')
      ..write('border-radius:${_px(props['radius'] ?? 0)};')
      ..write('background:${_color(props['background'] ?? '@card')};')
      ..write('color:${_color(props['foreground'] ?? '@cardForeground')};')
      ..write('border:${_px(props['borderWidth'] ?? 0)} solid ${_color(props['borderColor'] ?? 'transparent')};')
      ..write('opacity:${props['opacity'] ?? 1};');
    final classes = (props['borderWidth'] as num? ?? 0) > 0 ? 'node-card card-pixel' : 'node-card';
    return '<div class="$classes" style="$style">${children.map(_node).join()}</div>';
  }

  String _conditional(Map<String, dynamic> props, List children) {
    final bind = props['bind'];
    final actual = _sample[bind as String?];
    final expected = props['equals'];
    var pass = actual == expected;
    if (props['invert'] == true) pass = !pass;
    final chosen = children.whereType<Map>().toList();
    if (chosen.isEmpty) return '';
    final node = pass
        ? chosen.first
        : (chosen.length > 1 ? chosen[1] : null);
    return node == null ? '' : _node(node);
  }

  String _animate(Map<String, dynamic> props, List children) {
    final kind = (props['kind'] as String?) ?? 'rotate';
    final duration = (props['duration'] as num?)?.toInt() ??
        (kind == 'rotate' ? 24000 : 2400);
    final curve = switch (props['curve']) {
      'linear' => 'linear',
      'ease' => 'ease',
      'easeIn' => 'ease-in',
      'easeOut' => 'ease-out',
      'easeInOut' => 'ease-in-out',
      'easeOutCubic' => 'cubic-bezier(0.33, 1, 0.68, 1)',
      'easeInOutCubic' => 'cubic-bezier(0.65, 0, 0.35, 1)',
      _ => 'ease-in-out',
    };
    final className = switch (kind) {
      'pulse' => 'anim-pulse',
      'float' => 'anim-float',
      'fade' => 'anim-fade',
      _ => 'spin',
    };
    final gated = props['bind'] == 'player.playing';
    final reverse = props['reverse'] == true ? 'animation-direction:reverse;' : '';
    final style = '--dur:${(duration / 1000).toStringAsFixed(2)}s;'
        'animation-duration:${(duration / 1000).toStringAsFixed(2)}s;'
        'animation-timing-function:$curve;'
        'animation-name:obsidian-${kind == 'rotate' ? 'spin' : kind};$reverse';
    return '<div class="$className${gated ? ' gated' : ''}" style="$style">${children.map(_node).join()}</div>';
  }

  String _icon(String name, int size, [Object? color]) {
    final overrides = (_darkIconOverrides())?[name];
    final asset = overrides?['asset'];
    if (asset is String) {
      final uri = _assets[asset] ?? '';
      return '<img class="node-icon" src="$uri" width="$size" height="$size" '
          'alt="${_escape(name)}" style="width:${size}px;height:${size}px;image-rendering:pixelated;">';
    }
    final glyph = switch (name) {
      'play' => '▶',
      'pause' => '❚❚',
      'previous' => '⏮',
      'next' => '⏭',
      'shuffle' => '⤨',
      'repeat' => '↻',
      'like' => '♥',
      'lyrics' => '♪',
      'queue' => '≡',
      'volume' => '◖',
      'settings' => '⚙',
      'search' => '⌕',
      'library' => '▤',
      'download' => '↓',
      'back' => '←',
      'close' => '×',
      'plus' => '+',
      'home' => '⌂',
      'radio' => '◉',
      'stats' => '▥',
      _ => '•',
    };
    return '<span class="node-icon" style="width:${size}px;height:${size}px;'
        'display:inline-flex;align-items:center;justify-content:center;'
        'font-size:${(size * 0.9).round()}px;color:${_color(color ?? '@primary')};">'
        '$glyph</span>';
  }

  Map<String, dynamic>? _darkIconOverrides() {
    final icons = payload['icons'] as Map?;
    final overrides = icons?['overrides'];
    return overrides is Map
        ? overrides.cast<String, dynamic>()
        : null;
  }

  // -------------------------------------------------------------- samples

  String _componentSheet() {
    final buttons = ((payload['components'] as Map?)?['buttons'] as Map?) ??
        const {};
    final buttonSamples = buttons.entries.map((entry) {
      final style = (entry.value as Map).cast<String, dynamic>();
      return _sampleButton(entry.key, style);
    }).join();

    final card = ((payload['components'] as Map?)?['card'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final input = ((payload['components'] as Map?)?['input'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final badge = ((payload['components'] as Map?)?['badge'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return '''
<div class="section-head">COMPONENTS</div>
<div class="sheet">
  <div class="sheet-box">
    <h4>BUTTONS</h4>
    <div class="sheet-row">$buttonSamples</div>
  </div>
  <div class="sheet-box">
    <h4>CARD</h4>
    <div style="${_cardStyle(card)}">A card, with the theme's own border, radius, padding and pixel bevel.</div>
  </div>
  <div class="sheet-box">
    <h4>INPUT / BADGE / PROGRESS</h4>
    <input class="sample-input" placeholder="Search the deep dark" style="background:${_color(input['background'] ?? '@input')};border-color:${_color(input['borderColor'] ?? '@border')};font-family:${input['fontFamily'] ?? 'VT323'}, monospace;">
    <div style="height:10px"></div>
    <span class="sample-badge" style="background:${_color(badge['background'] ?? '@secondary')};color:${_color(badge['foreground'] ?? '@secondaryForeground')};border-color:${_color(badge['borderColor'] ?? '@border')}">PIXEL</span>
    <div style="height:12px"></div>
    <div class="sample-progress"><span></span></div>
  </div>
  <div class="sheet-box">
    <h4>TYPE</h4>
    <div style="font-family:'Silkscreen',monospace;font-size:26px;letter-spacing:1px;">SILKSCREEN 26</div>
    <div style="font-family:'VT323',monospace;font-size:20px;">VT323 20 — The record turns while the track plays.</div>
    <div style="font-family:'Silkscreen',monospace;font-size:12px;letter-spacing:1.5px;color:var(--primary);">LABEL 12 / AMETHYST</div>
  </div>
</div>''';
  }

  String _sampleButton(String label, Map<String, dynamic> style) {
    final background = _color(style['background'] ?? '@primary');
    final foreground = _color(style['foreground'] ?? '@primaryForeground');
    final border = _color(style['borderColor'] ?? '@primary');
    final width = (style['borderWidth'] as num?) ?? 0;
    final radius = (style['radius'] as num?) ?? 0;
    final padding = (style['padding'] as num?) ?? 10;
    final size = (style['fontSize'] as num?) ?? 18;
    return '<button class="node-button" style="background:$background;color:$foreground;'
        'border-color:$border;border-width:${width.toInt()}px;border-radius:${radius.toInt()}px;'
        'padding:${padding.round()}px ${(padding * 1.2).round()}px;font-size:${size.round()}px;'
        "font-family:'${style['fontFamily'] ?? 'VT323'}', monospace;letter-spacing:${style['letterSpacing'] ?? 0}px;"
        'text-transform:uppercase;">${_escape(label)}</button>';
  }

  String _cardStyle(Map<String, dynamic> style) {
    return 'background:${_color(style['background'] ?? '@card')};'
        'color:${_color(style['foreground'] ?? '@cardForeground')};'
        'border:${_px(style['borderWidth'] ?? 0)} solid ${_color(style['borderColor'] ?? '@border')};'
        'border-radius:${_px(style['radius'] ?? 0)};'
        'padding:${_px(style['padding'] ?? 12)};'
        'box-shadow:inset 2px 2px 0 rgba(255,255,255,.10), inset -2px -2px 0 rgba(0,0,0,.45);';
  }

  String _palette(String name, Map<String, dynamic> palette) {
    final swatches = palette.entries.map((entry) {
      final hex = entry.value.toString();
      return '<div class="swatch" style="background:$hex;color:${_readableOn(hex)}">'
          '<div>${entry.key}</div><small>$hex</small></div>';
    }).join();
    return '<div class="palette"><h3>${name.toUpperCase()} · ${palette.length} ROLES</h3><div class="swatches">$swatches</div></div>';
  }

  String _tokens() {
    final tokens = <String>[
      if (payload['radius'] is Map) 'radius ${(payload['radius'] as Map).entries.map((e) => '${e.key}=${e.value}').join(' ')}',
      if (payload['spacing'] is Map) 'spacing ${(payload['spacing'] as Map).entries.map((e) => '${e.key}=${e.value}').join(' ')}',
      if (payload['motion'] is Map) 'motion ${(payload['motion'] as Map).entries.map((e) => '${e.key}=${e.value}').join(' ')}',
      if (payload['typography'] is Map) 'type ${(payload['typography'] as Map)['family']} / ${(payload['typography'] as Map)['brandFamily']}',
      'icons ${_darkIconOverrides()?.length ?? 0} overrides',
      'dock ${(payload['layout'] as Map?)?['player']?['dock'] ?? 'full'}',
      'background ${(payload['background'] as Map?)?['source'] ?? 'none'} · tile=${(payload['background'] as Map?)?['tile'] ?? false} · scale=${(payload['background'] as Map?)?['scale'] ?? 1}',
    ];
    return '<div class="tokens">${tokens.map((token) => '<div class="token"><code>$token</code></div>').join()}</div>';
  }

  // -------------------------------------------------------------- helpers

  String _color(Object? value) {
    if (value is! String) return 'currentColor';
    if (value.startsWith('@')) return 'var(--${value.substring(1)})';
    return _cssColor(value);
  }

  String _cssColor(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length == 8) {
      final a = int.parse(hex.substring(0, 2), radix: 16) / 255.0;
      final r = int.parse(hex.substring(2, 4), radix: 16);
      final g = int.parse(hex.substring(4, 6), radix: 16);
      final b = int.parse(hex.substring(6, 8), radix: 16);
      return 'rgba($r,$g,$b,${a.toStringAsFixed(3)})';
    }
    if (hex.length == 6) return '#$hex';
    return value;
  }

  String _readableOn(String value) {
    final hex = value.replaceFirst('#', '');
    if (hex.length < 6) return '#ffffff';
    final n = int.parse(hex.substring(hex.length - 6), radix: 16);
    final r = (n >> 16) & 0xff;
    final g = (n >> 8) & 0xff;
    final b = n & 0xff;
    final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
    return l > 0.55 ? '#120a1c' : '#fbf8ff';
  }

  String _family(Object? value) =>
      "'${value is String && value.isNotEmpty ? value : 'monospace'}'";

  String _px(Object? value) {
    if (value is num) return '${value.toInt()}px';
    if (value is String) return value;
    return '0px';
  }

  String _pxPair(String property, Object? factor) {
    if (factor is! num) return '';
    return '$property:${(factor * 100).round()}%;';
  }

  String _align(Object? value) => switch (value) {
        'center' => 'center',
        'end' => 'flex-end',
        'stretch' => 'stretch',
        'topLeft' || 'topCenter' || 'topRight' => 'flex-start',
        'bottomLeft' || 'bottomCenter' || 'bottomRight' => 'flex-end',
        'centerLeft' || 'centerRight' || 'center' => 'center',
        _ => 'flex-start',
      };

  String _justify(Object? value) => switch (value) {
        'center' => 'center',
        'end' => 'flex-end',
        'spaceBetween' => 'space-between',
        'spaceAround' => 'space-around',
        'spaceEvenly' => 'space-evenly',
        _ => 'flex-start',
      };

  String _place(Object? value) => switch (value) {
        'topLeft' => 'start start',
        'topCenter' => 'start center',
        'topRight' => 'start end',
        'centerLeft' => 'center start',
        'centerRight' => 'center end',
        'bottomLeft' => 'end start',
        'bottomCenter' => 'end center',
        'bottomRight' => 'end end',
        _ => 'center center',
      };

  String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  String _js(String value) => value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  String _img(String asset, String size, String className) {
    final uri = _assets[asset];
    if (uri == null) return '';
    return '<img class="$className" src="$uri" alt="" style="width:$size;height:$size;image-rendering:pixelated;">';
  }

  String _coverSvg() {
    final primary = _cssColor((_dark['primary'] as String?) ?? '#a855f7');
    final background = _cssColor((_dark['background'] as String?) ?? '#07060b');
    // A little end-stone night, 32 pixels square, so the record has something
    // worth turning. The host supplies real artwork; this is preview furniture.
    final svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="320" height="320" viewBox="0 0 32 32" shape-rendering="crispEdges">
<rect width="32" height="32" fill="$background"/>
<rect y="0" width="32" height="10" fill="#0d0914"/>
<rect y="10" width="32" height="8" fill="#140d1e"/>
<rect y="18" width="32" height="7" fill="#1c1229"/>
<rect x="4" y="4" width="1" height="1" fill="#c4b5fd"/>
<rect x="9" y="7" width="1" height="1" fill="#e9d5ff"/>
<rect x="14" y="3" width="1" height="1" fill="$primary"/>
<rect x="6" y="12" width="1" height="1" fill="#e9d5ff"/>
<rect x="3" y="9" width="1" height="1" fill="#c4b5fd"/>
<rect x="29" y="8" width="1" height="1" fill="#e9d5ff"/>
<rect x="25" y="4" width="1" height="1" fill="#c4b5fd"/>
<rect x="11" y="15" width="1" height="1" fill="#a855f7"/>
<rect x="20" y="5" width="7" height="1" fill="#f3e8ff"/>
<rect x="18" y="6" width="10" height="1" fill="#f3e8ff"/>
<rect x="18" y="7" width="10" height="1" fill="#f3e8ff"/>
<rect x="18" y="8" width="10" height="1" fill="#f3e8ff"/>
<rect x="18" y="9" width="10" height="1" fill="#f3e8ff"/>
<rect x="18" y="10" width="10" height="1" fill="#f3e8ff"/>
<rect x="20" y="11" width="7" height="1" fill="#f3e8ff"/>
<rect x="20" y="7" width="2" height="2" fill="#c4b5fd"/>
<rect x="24" y="9" width="2" height="1" fill="#c4b5fd"/>
<rect x="19" y="8" width="1" height="1" fill="#ddd6fe"/>
<rect x="22" y="10" width="1" height="1" fill="#ddd6fe"/>
<polygon points="0,25 4,20 8,24 12,19 17,25 21,21 26,26 32,22 32,32 0,32" fill="#241736"/>
<rect x="4" y="20" width="1" height="1" fill="$primary"/>
<rect x="12" y="19" width="1" height="1" fill="$primary"/>
<rect x="21" y="21" width="1" height="1" fill="$primary"/>
<polygon points="0,29 6,25 11,30 16,24 22,31 27,26 32,30 32,32 0,32" fill="#0a0710"/>
<rect x="6" y="25" width="1" height="1" fill="#a855f7"/>
<rect x="16" y="24" width="1" height="1" fill="#a855f7"/>
<rect x="27" y="26" width="1" height="1" fill="#a855f7"/>
<rect x="25" y="27" width="1" height="5" fill="#05030a"/>
<rect x="26" y="26" width="1" height="6" fill="#160f22"/>
<rect x="27" y="28" width="1" height="4" fill="#05030a"/>
</svg>''';
    return 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
  }

  String _avatarSvg() {
    const svg = '''<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 16 16" shape-rendering="crispEdges">
<rect width="16" height="16" fill="#1b1426"/>
<rect x="4" y="3" width="8" height="8" fill="#a855f7"/>
<rect x="5" y="5" width="2" height="2" fill="#0b0712"/>
<rect x="9" y="5" width="2" height="2" fill="#0b0712"/>
<rect x="6" y="9" width="4" height="1" fill="#0b0712"/>
<rect x="5" y="11" width="6" height="3" fill="#7c3aed"/>
</svg>''';
    return 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
  }

  // ------------------------------------------------------------------- js

  String _script() => '''
let mode = 'dark';
function setMode(next) {
  mode = next;
  document.documentElement.dataset.mode = mode;
  document.getElementById('mode-button').textContent =
    mode === 'dark' ? 'MODE: END STONE' : 'MODE: OBSIDIAN';
}
function toggleMode() {
  setMode(mode === 'dark' ? 'light' : 'dark');
}
function togglePlay() {
  const playing = document.body.classList.toggle('is-playing');
  document.getElementById('play-button').textContent =
    playing ? 'PAUSE RECORD' : 'PLAY RECORD';
  toast(playing ? 'player.playing = true' : 'player.playing = false');
}
function showScreen(id) {
  document.querySelectorAll('.screen').forEach((el) => {
    el.hidden = el.dataset.screen !== id;
  });
  document.querySelectorAll('[data-screen-button]').forEach((el) => {
    el.classList.toggle('active', el.dataset.screenButton === id);
  });
  window.scrollTo({ top: 0, behavior: 'instant' });
}
function act(type, target) {
  if (type === 'playPause') {
    togglePlay();
    return;
  }
  if (type === 'navigate' && target.startsWith('screen:')) {
    showScreen(target.slice(7));
    return;
  }
  toast(type + (target ? ' → ' + target : ''));
}
let toastTimer;
function toast(message) {
  const el = document.getElementById('toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 1600);
}
document.addEventListener('keydown', (event) => {
  if (event.key === ' ') {
    event.preventDefault();
    togglePlay();
  }
});
// Shareable states: #mode=light&screen=palette, plus the shorthand #light.
function applyHash() {
  if (location.hash === '#light') setMode('light');
  const params = new URLSearchParams(location.hash.replace(/^#/, ''));
  if (params.get('mode') === 'light') setMode('light');
  showScreen(params.get('screen') || 'stage');
}
applyHash();
''';
}
