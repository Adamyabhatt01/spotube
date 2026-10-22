import 'dart:convert';
import 'dart:io';

/// The include directive the build understands.
///
/// Hetu plugins in this repo use no `import` statements, so includes are
/// resolved by the build instead: the SDK is plain Hetu source that gets
/// concatenated ahead of the theme. Keeping the directive out of the language
/// means the same source still compiles with a bare `hetu.compile`, and the
/// build has nothing to guess.
const includeDirective = '//#include';

/// A theme on disk: its directory, its manifest and its source.
///
/// The manifest is the plugin manifest the app installs (`plugin.json`), so a
/// theme directory is a complete plugin: the build turns it into a `.smplug`
/// without any other input.
class ThemeSource {
  ThemeSource({
    required this.id,
    required this.directory,
    required this.manifest,
    required this.manifestBytes,
    required this.source,
    required this.includes,
    this.publishPath,
  });

  /// Directory name under `themes/`, and the artifact prefix in `dist/`.
  final String id;

  final Directory directory;

  /// Parsed `plugin.json`.
  final Map<String, dynamic> manifest;

  /// The manifest file's own bytes.
  ///
  /// The build packages these verbatim: the manifest is authored, and
  /// re-encoding it would change bytes that the app and the pinned artifact
  /// tests compare against.
  final List<int> manifestBytes;

  /// The theme source with every include resolved (SDK first, theme last).
  final String source;

  /// Include paths that were resolved, in resolution order.
  final List<String> includes;

  /// Where the built artifact is published inside the repository, if at all.
  ///
  /// The install URLs people paste into the app are raw GitHub URLs, so the
  /// published path is part of the contract with whoever installed the
  /// theme: it cannot move without breaking their install.
  final String? publishPath;

  String get name => manifest['name'] as String? ?? id;

  String get author => manifest['author'] as String? ?? 'unknown';

  String get version => manifest['version'] as String? ?? '0.0.0';

  String get entryPoint => manifest['entryPoint'] as String? ?? 'Theme';

  List<String> get abilities => [
        for (final ability in (manifest['abilities'] as List? ?? const []))
          '$ability',
      ];

  /// The artifact file name, stable across builds so the host's pinned
  /// artifact tests keep pointing at the same file.
  String get artifactName => '$id-$version.smplug';

  /// The theme's assets, if it ships any.
  ///
  /// Relative paths are preserved in the archive: the app's extractor writes
  /// entries relative to the plugin directory, so `fonts/x.ttf` stays
  /// `fonts/x.ttf`. (The app's own `scripts/plugin_zip.dart` flattens entry
  /// names, which is why this repo packages with its own zipper.)
  Map<String, File> get assets {
    final assetsDir = Directory('${directory.path}/assets');
    if (!assetsDir.existsSync()) return const {};
    final files = <String, File>{};
    for (final entity in assetsDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path
          .substring(assetsDir.path.length + 1)
          .replaceAll('\\', '/');
      files[relative] = entity;
    }
    return files;
  }
}

/// Every `asset://` path in a payload, wherever it is nested.
///
/// A theme references its own files by path; the host resolves them inside the
/// plugin's own directory. Collecting them is what lets the build check that
/// a theme ships what it points at.
Set<String> collectAssetPaths(Object? node) {
  final paths = <String>{};
  void walk(Object? value) {
    if (value is String) {
      if (value.startsWith('asset://')) paths.add(value.substring(8));
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        walk(entry.value);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  walk(node);
  return paths;
}

/// Every theme directory under `themes/`, sorted by id.
List<ThemeSource> loadThemes(String repoRoot) {
  final themesDir = Directory('$repoRoot/themes');
  if (!themesDir.existsSync()) return const [];

  final themes = <ThemeSource>[];
  for (final entity in themesDir.listSync()) {
    if (entity is! Directory) continue;
    final manifestFile = File('${entity.path}/plugin.json');
    final sourceFile = File('${entity.path}/theme.ht');
    if (!manifestFile.existsSync() || !sourceFile.existsSync()) continue;

    final manifest = jsonDecode(manifestFile.readAsStringSync())
        as Map<String, dynamic>;
    final resolved = resolveIncludes(sourceFile.readAsStringSync(), repoRoot);

    // `build.json` is build configuration, not part of the plugin: the app
    // never sees it.
    String? publishPath;
    final buildFile = File('${entity.path}/build.json');
    if (buildFile.existsSync()) {
      final build = jsonDecode(buildFile.readAsStringSync())
          as Map<String, dynamic>;
      final publish = build['publish'];
      if (publish is String && publish.isNotEmpty) {
        publishPath = publish;
      }
    }

    themes.add(ThemeSource(
      id: entity.path.split(Platform.pathSeparator).last,
      directory: entity,
      manifest: manifest,
      manifestBytes: manifestFile.readAsBytesSync(),
      source: resolved.source,
      includes: resolved.includes,
      publishPath: publishPath,
    ));
  }

  themes.sort((a, b) => a.id.compareTo(b.id));
  return themes;
}

/// The resolved source plus the include list.
class ResolvedSource {
  const ResolvedSource(this.source, this.includes);

  final String source;
  final List<String> includes;
}

/// Inlines `//#include "path"` directives.
///
/// Paths are relative to the repository root. An include is inlined once —
/// the second request for the same file is a no-op, so two themes can both
/// pull in the SDK without it appearing twice in the compiled source.
ResolvedSource resolveIncludes(String source, String repoRoot) {
  final included = <String>{};
  final order = <String>[];

  String expand(String text, String origin) {
    final buffer = StringBuffer();
    for (final line in text.split('\n')) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith(includeDirective)) {
        buffer.writeln(line);
        continue;
      }

      final target = _includeTarget(trimmed);
      if (target == null) {
        buffer.writeln(line);
        continue;
      }

      final path = target.startsWith('/')
          ? target.substring(1)
          : '$origin/$target';
      if (!included.add(path)) continue;

      final file = File('$repoRoot/$path');
      if (!file.existsSync()) {
        throw FileSystemException('Included file not found', path);
      }
      order.add(path);
      buffer.writeln('// --- begin $path ---');
      buffer.write(expand(file.readAsStringSync(), path));
      buffer.writeln('// --- end $path ---');
    }
    return buffer.toString();
  }

  return ResolvedSource(expand(source, ''), order);
}

/// The path inside a `//#include "..."` directive, or null when the line is
/// not a usable include.
String? _includeTarget(String line) {
  final rest = line.substring(includeDirective.length).trim();
  if (!rest.startsWith('"') && !rest.startsWith("'")) return null;
  final quote = rest[0];
  final end = rest.indexOf(quote, 1);
  if (end < 0) return null;
  return rest.substring(1, end);
}
