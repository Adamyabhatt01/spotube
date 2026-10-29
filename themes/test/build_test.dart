import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:spotube_themes/compile.dart';
import 'package:spotube_themes/packager.dart';
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

        // The bundled themes are v3 until Phase 11 migrates them. The build
        // tooling reads them through the legacy validator; the host rejects
        // them, which `v4_validator_test` covers.
        final report = compiled.payload['specVersion'] == 3
            ? validateLegacyThemePayload(compiled.payload)
            : validateThemePayload(compiled.payload);
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

  group('the built index', () {
    test('lists every theme and matches its artifact', () {
      final index = jsonDecode(
        File('$repoRoot/dist/index.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final entries = (index['themes'] as List).cast<Map<String, dynamic>>();

      expect(
        entries.map((entry) => entry['id']).toSet(),
        loadThemes(repoRoot).map((theme) => theme.id).toSet(),
        reason: 'the index is what the app lists; every theme has to be in it',
      );

      for (final entry in entries) {
        final artifact = File('$repoRoot/dist/${entry['file']}');
        expect(artifact.existsSync(), isTrue, reason: '${entry['id']}');
        expect(artifact.lengthSync(), entry['bytes'], reason: '${entry['id']}');
        expect(
          sha256OfFile(artifact),
          entry['sha256'],
          reason: '${entry['id']} changed — rebuild the index',
        );
      }
    });

    test('a subset build keeps the rest of the catalog', () async {
      final temp = Directory.systemTemp.createTempSync('spotube-index-');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}/index.json').writeAsStringSync(jsonEncode({
        'generatedAt': '1970-01-01T00:00:00.000Z',
        'themes': [
          {'id': 'keep-me', 'name': 'Keep Me', 'version': '0.0.1'},
        ],
      }));

      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'tools/build.dart',
          '-t',
          'minimal',
          '--out',
          p.relative(temp.path, from: repoRoot),
        ],
        workingDirectory: repoRoot,
      );
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );

      final index = jsonDecode(
        File('${temp.path}/index.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final ids = (index['themes'] as List)
          .map((entry) => (entry as Map)['id'])
          .toList();
      expect(ids, containsAll(<String>['keep-me', 'minimal']));
    });
  });
}
