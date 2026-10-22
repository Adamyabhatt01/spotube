import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/compile.dart';
import '../lib/packager.dart';
import '../lib/theme_source.dart';
import '../lib/v3_validator.dart';
import '../lib/validator.dart';

/// Builds the theme plugins.
///
/// One command compiles every theme, runs it, validates the payload it
/// produces, packages it and writes an index. The point of running the theme
/// at build time is that a theme which compiles but returns nothing — or
/// returns a color the host cannot parse — is now a build failure instead of a
/// user's blank app.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption(
      'theme',
      help: 'Build only these theme ids (repeatable).',
      abbr: 't',
    )
    ..addFlag(
      'check',
      help: 'Validate only; write nothing. Exits non-zero on an error.',
      negatable: false,
    )
    ..addFlag(
      'watch',
      help: 'Rebuild when a theme source changes.',
      negatable: false,
    )
    ..addOption(
      'out',
      help: 'Output directory (default: dist).',
      defaultsTo: 'dist',
    )
    ..addFlag(
      'skip-validate',
      help: 'Skip payload validation.',
      negatable: false,
    )
    ..addFlag('quiet', help: 'Only print problems.', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final repoRoot = p.dirname(p.dirname(p.absolute(Platform.script.toFilePath())));
  final outDir = Directory(p.join(repoRoot, options['out'] as String));

  final selected = options['theme'] as List<String>;
  final check = options['check'] as bool;
  final watch = options['watch'] as bool;
  final quiet = options['quiet'] as bool;
  final skipValidate = options['skip-validate'] as bool;
  if (watch && selected.isEmpty) {
    stderr.writeln('--watch needs at least one --theme');
    exitCode = 64;
    return;
  }

  var failed = false;
  var index = <String, dynamic>{};

  Future<void> buildOnce() async {
    final themes = loadThemes(repoRoot)
        .where((theme) => selected.isEmpty || selected.contains(theme.id))
        .toList();

    if (themes.isEmpty) {
      stderr.writeln(selected.isEmpty
          ? 'no themes found under themes/'
          : 'no theme matched ${selected.join(', ')}');
      failed = true;
      return;
    }

    final entries = <Map<String, dynamic>>[];

    for (final theme in themes) {
      final result = await _buildTheme(
        theme: theme,
        outDir: outDir,
        check: check,
        skipValidate: skipValidate,
        quiet: quiet,
      );

      if (result.error != null) {
        stderr.writeln('${theme.id}: ${result.error}');
        failed = true;
        continue;
      }

      for (final issue in result.issues) {
        if (issue.severity == Severity.error) {
          stderr.writeln('${theme.id}: $issue');
        } else if (!quiet) {
          stdout.writeln('${theme.id}: $issue');
        }
      }

      if (result.report?.hasErrors ?? false) {
        failed = true;
      }

      if (!quiet) {
        stdout.writeln(result.summary);
      }

      if (result.indexEntry != null) {
        entries.add(result.indexEntry!);
      }
    }

    if (!check) {
      entries.sort((a, b) =>
          (a['id'] as String).compareTo(b['id'] as String));
      index = {
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'themes': entries,
      };
      final indexFile = File(p.join(outDir.path, 'index.json'));
      indexFile.parent.createSync(recursive: true);
      indexFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(index),
      );
    }
  }

  await buildOnce();

  if (watch) {
    stdout.writeln('watching ${p.join(repoRoot, 'themes')} — Ctrl-C to stop');
    final seen = _sourceStamps(repoRoot, selected);
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final now = _sourceStamps(repoRoot, selected);
      if (_sameStamps(seen, now)) continue;
      seen.clear();
      seen.addAll(now);
      stdout.writeln('--- change detected');
      await buildOnce();
    }
  }

  if (failed) exitCode = 1;
}

/// The repository root a theme lives in.
String repoRootOf(ThemeSource theme) =>
    p.dirname(p.dirname(p.absolute(theme.directory.path)));

/// The modification time of every theme source, keyed by path.
///
/// Polling instead of a file-system watcher: the tool has no watch
/// dependency, and a theme source is a handful of files that change while
/// somebody is editing them.
Map<String, int> _sourceStamps(String repoRoot, List<String> selected) {
  final stamps = <String, int>{};
  for (final theme in loadThemes(repoRoot)) {
    if (selected.isNotEmpty && !selected.contains(theme.id)) continue;
    for (final file in theme.directory.listSync(recursive: true)) {
      if (file is! File) continue;
      stamps[file.path] = file.statSync().modified.millisecondsSinceEpoch;
    }
  }
  return stamps;
}

/// Whether two stamp maps describe the same state.
bool _sameStamps(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// What one theme produced.
class _BuildResult {
  _BuildResult({
    this.error,
    this.issues = const [],
    this.report,
    this.summary = '',
    this.indexEntry,
  });

  final String? error;
  final List<Issue> issues;
  final ValidationReport? report;
  final String summary;
  final Map<String, dynamic>? indexEntry;
}

/// Compiles, runs, validates and packages one theme.
Future<_BuildResult> _buildTheme({
  required ThemeSource theme,
  required Directory outDir,
  required bool check,
  required bool skipValidate,
  required bool quiet,
}) async {
  if (!theme.abilities.contains('theme')) {
    return _BuildResult(
      error: 'manifest does not declare the "theme" ability',
    );
  }

  final issues = <Issue>[];

  final Uint8List byteCode;
  try {
    byteCode = compileThemeSource(theme.source, sourceName: '${theme.id}_theme');
  } catch (error) {
    return _BuildResult(error: 'compile failed: $error');
  }

  final CompiledTheme compiled;
  try {
    compiled = await evaluateTheme(byteCode, entryPoint: theme.entryPoint);
  } catch (error) {
    return _BuildResult(error: 'the theme did not run: $error');
  }

  ValidationReport? report;
  if (!skipValidate) {
    report = validateThemePayload(compiled.payload);
  }

  // A theme may answer `getUi()` with its own UI specification instead of
  // carrying it in the payload. Same document, same rules.
  if (compiled.uiSpec != null) {
    for (final issue in validateUiSpec(compiled.uiSpec!)) {
      (report ??= validateThemePayload(compiled.payload)).issues.add(issue);
    }
  }

  // The files a theme points at have to exist: a theme that references an
  // asset it does not ship renders an empty space and says nothing.
  final declared = collectAssetPaths(compiled.payload);
  if (compiled.uiSpec != null) {
    declared.addAll(collectAssetPaths(compiled.uiSpec));
  }
  final shipped = theme.assets.keys.toSet();
  for (final path in declared) {
    if (!shipped.contains(path)) {
      issues.add(Issue(
        Severity.error,
        'assets',
        'points at $path, which the theme does not ship',
      ));
    }
  }
  for (final path in shipped) {
    if (!declared.contains(path)) {
      issues.add(Issue(
        Severity.warning,
        'assets/$path',
        'shipped but never referenced — the host has no reason to load it',
      ));
    }
  }

  if (check) {
    return _BuildResult(
      issues: [...?report?.issues, ...issues],
      report: report,
      summary: '${theme.id}: ${theme.version} — checked',
    );
  }

  final entries = <String, Uint8List>{
    'plugin.json': Uint8List.fromList(theme.manifestBytes),
    'plugin.out': byteCode,
  };
  for (final entry in theme.assets.entries) {
    entries['assets/${entry.key}'] = entry.value.readAsBytesSync();
  }

  final outputFile = packageTheme(
    outputPath: p.join(outDir.path, theme.artifactName),
    entries: entries,
  );

  // The published path is the install URL: the app is handed a raw GitHub
  // URL, so the artifact has to sit exactly where the README says it does.
  String? publishedPath;
  if (theme.publishPath != null) {
    publishedPath = p.join(repoRootOf(theme), theme.publishPath!);
    final published = File(publishedPath);
    published.parent.createSync(recursive: true);
    published.writeAsBytesSync(outputFile.readAsBytesSync());
  }

  return _BuildResult(
    issues: [...?report?.issues, ...issues],
    report: report,
    summary: '${theme.id}: ${theme.version} — ${theme.artifactName} '
        '(${outputFile.lengthSync()} bytes)',
    indexEntry: {
      'id': theme.id,
      'name': theme.name,
      'author': theme.author,
      'version': theme.version,
      'entryPoint': theme.entryPoint,
      'abilities': theme.abilities,
      'file': theme.artifactName,
      'bytes': outputFile.lengthSync(),
      'sha256': sha256OfFile(outputFile),
      'optionalMethods': compiled.optionalMethods,
      'hasUiSpec': compiled.uiSpec != null,
      if (publishedPath != null)
        'published': p.relative(publishedPath, from: repoRootOf(theme)),
    },
  );
}
