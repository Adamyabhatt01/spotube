import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:spotube_themes/compile.dart';
import 'package:spotube_themes/theme_source.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

final repoRoot = Directory.current.path;

/// The payload of a built artifact, read the way the app reads it.
Future<Map<String, dynamic>> payloadOfArtifact(File archive) async {
  final zip = ZipDecoder().decodeBytes(archive.readAsBytesSync());
  final entry = zip.firstWhere(
    (file) => file.isFile && file.name == 'plugin.out',
    orElse: () => throw StateError('${archive.path} has no plugin.out'),
  );
  final manifestEntry = zip.firstWhere(
    (file) => file.isFile && file.name == 'plugin.json',
    orElse: () => throw StateError('${archive.path} has no plugin.json'),
  );
  final manifest = jsonDecode(
    utf8.decode(manifestEntry.content as List<int>),
  ) as Map<String, dynamic>;

  final compiled = await evaluateTheme(
    Uint8List.fromList(entry.content as List<int>),
    entryPoint: manifest['entryPoint'] as String,
  );
  return compiled.payload;
}

void main() {
  group('every theme', () {
    test('compiles, runs and validates', () async {
      for (final theme in loadThemes(repoRoot)) {
        final byteCode = compileThemeSource(
          theme.source,
          sourceName: '${theme.id}_theme',
        );
        expect(byteCode, isNotEmpty, reason: theme.id);

        final compiled = await evaluateTheme(
          byteCode,
          entryPoint: theme.entryPoint,
        );

        final report = validateThemePayload(compiled.payload);
        expect(report.hasErrors, isFalse, reason: theme.id);
        expect(report.warningCount, 0, reason: theme.id);
      }
    });

    test('declares the theme ability and an entry point', () {
      for (final theme in loadThemes(repoRoot)) {
        expect(theme.abilities, contains('theme'), reason: theme.id);
        expect(theme.entryPoint, isNotEmpty, reason: theme.id);
        expect(theme.version, isNotEmpty, reason: theme.id);
      }
    });
  });

  group('the committed artifacts', () {
    test('exist for every theme', () {
      for (final theme in loadThemes(repoRoot)) {
        expect(
          File('$repoRoot/dist/${theme.artifactName}').existsSync(),
          isTrue,
          reason: '${theme.artifactName} is missing — run the build',
        );
      }
    });

    test('produce the payload the theme produces today', () async {
      for (final theme in loadThemes(repoRoot)) {
        final artifact = File('$repoRoot/dist/${theme.artifactName}');
        if (!artifact.existsSync()) continue;

        final byteCode = compileThemeSource(
          theme.source,
          sourceName: '${theme.id}_theme',
        );
        final compiled = await evaluateTheme(
          byteCode,
          entryPoint: theme.entryPoint,
        );

        expect(
          await payloadOfArtifact(artifact),
          equals(compiled.payload),
          reason: '${theme.artifactName} is stale — rebuild it',
        );
      }
    });

    test('carry the manifest and the bytecode the app looks for', () async {
      for (final theme in loadThemes(repoRoot)) {
        final artifact = File('$repoRoot/dist/${theme.artifactName}');
        if (!artifact.existsSync()) continue;

        final zip = ZipDecoder().decodeBytes(artifact.readAsBytesSync());
        expect(
          zip.map((file) => file.name),
          containsAll(<String>['plugin.json', 'plugin.out']),
          reason: theme.id,
        );

        final manifest = jsonDecode(
          utf8.decode(
            zip.firstWhere((file) => file.name == 'plugin.json').content
                as List<int>,
          ),
        ) as Map<String, dynamic>;

        expect(manifest['entryPoint'], theme.entryPoint, reason: theme.id);
        expect(manifest['version'], theme.version, reason: theme.id);
        expect(manifest['abilities'], contains('theme'), reason: theme.id);
      }
    });
  });
}
