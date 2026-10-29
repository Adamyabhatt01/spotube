import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/compile.dart';
import 'package:spotube_themes/theme_source.dart';
import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

/// The repository root, from the test's own location.
final repoRoot = Directory.current.path;

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('the golden payloads', () {
    test('every theme has one', () {
      final themes = loadThemes(repoRoot);
      expect(themes, isNotEmpty);

      for (final theme in themes) {
        expect(
          File('$repoRoot/conformance/${theme.id}.json').existsSync(),
          isTrue,
          reason: '${theme.id} has no golden payload — run tools/export.dart',
        );
      }
    });

    test('they are what the themes actually produce', () async {
      for (final theme in loadThemes(repoRoot)) {
        final byteCode = compileThemeSource(
          theme.source,
          sourceName: '${theme.id}_theme',
        );
        final compiled = await evaluateTheme(
          byteCode,
          entryPoint: theme.entryPoint,
        );

        expect(
          compiled.payload,
          equals(readJson('$repoRoot/conformance/${theme.id}.json')),
          reason: '${theme.id} changed — regenerate with tools/export.dart',
        );
      }
    });

    test('they are payloads the app accepts', () {
      for (final file in Directory('$repoRoot/conformance').listSync()) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        final payload = readJson(file.path);
        // The bundled themes are still v3 until Phase 11 migrates them. The
        // host rejects v3, so the tooling validates them through the legacy
        // path; a v4 payload goes through the host's own entry point.
        final report = payload['specVersion'] == 3
            ? validateLegacyThemePayload(payload)
            : validateThemePayload(payload);
        expect(report.hasErrors, isFalse, reason: file.path);
        expect(report.warningCount, 0, reason: file.path);
      }
    });
  });

  group('the hand-written fixtures', () {
    test('the minimal payload is valid', () {
      final report =
          validateThemePayload(readJson('$repoRoot/conformance/handwritten/v2-minimal.json'));
      expect(report.hasErrors, isFalse);
      expect(report.warningCount, 0);
    });

    test('the out-of-range payload is clamped rather than rejected', () {
      final report =
          validateThemePayload(readJson('$repoRoot/conformance/broken/out-of-range.json'));
      expect(report.hasErrors, isFalse);
      expect(report.warningCount, greaterThan(0));
      expect((report.resolved!['radius'] as Map)['large'], 64.0);
    });

    test('the unknown-field payload is only a warning', () {
      final report =
          validateThemePayload(readJson('$repoRoot/conformance/broken/unknown-field.json'));
      expect(report.hasErrors, isFalse);
      expect(report.warningCount, 1);
    });
  });

  group('the v3 themes', () {
    test('the brand demo is inert on a v2 host and complete on a v3 one', () {
      final payload = readJson('$repoRoot/conformance/brand-demo.json');

      // As a v3 payload: complete, and every rule satisfied. The legacy entry
      // point exists for the migration tools; the host itself rejects v3.
      final v3 = validateLegacyThemePayload(payload);
      expect(v3.hasErrors, isFalse);
      expect(v3.warningCount, 0);

      // As a v2 payload: the colour schemes still carry the theme, and the
      // blocks a v2 host does not know are warnings rather than errors.
      final v2 = validateThemePayload(Map<String, dynamic>.from(payload)
        ..remove('specVersion'));
      expect(v2.hasErrors, isFalse);
      expect(v2.resolved, isNotNull);

      final unknown = {
        for (final issue in v2.issues)
          if (issue.severity == Severity.warning) issue.path
      };
      expect(unknown, containsAll(['branding', 'ui', 'typography', 'components']));
    });

    test('the host rejects them until they are migrated', () {
      final report = validateThemePayload(
        readJson('$repoRoot/conformance/brand-demo.json'),
      );
      expect(report.hasErrors, isTrue);
      expect(report.issues, hasLength(1));
      expect(
        report.issues.single.message,
        'specVersion 3 is not supported; migrate to 4',
      );
    });
  });

  group('the v3 draft', () {
    test('is a valid v3 payload for the legacy tooling', () {
      final report = validateLegacyThemePayload(
        readJson('$repoRoot/conformance/draft/v3-kitchen-sink.json'),
      );
      expect(report.hasErrors, isFalse);
      expect(report.warningCount, 0);
    });

    test('a v2 app can still read it — the new blocks are warnings there', () {
      // The compatibility rule, stated as a test: take the version line away
      // and the payload is still usable by an app that knows only v2. The v2
      // part has to be complete and valid, or the app would throw on the
      // whole payload instead of ignoring the blocks it does not know.
      final payload = readJson('$repoRoot/conformance/draft/v3-kitchen-sink.json')
        ..remove('specVersion');

      final report = validateThemePayload(payload);
      expect(report.hasErrors, isFalse);
      expect(report.resolved, isNotNull);

      final unknown = {
        for (final issue in report.issues)
          if (issue.severity == Severity.warning) issue.path
      };
      expect(
        unknown,
        containsAll([
          'typography',
          'spacing',
          'motion',
          'scale',
          'icons',
          'components',
          'branding',
          'ui',
        ]),
      );
    });
  });

  group('the v4 draft', () {
    test('is a clean v4 payload', () {
      final report = validateThemePayload(
        readJson('$repoRoot/conformance/draft/v4-kitchen-sink.json'),
      );
      expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
      expect(report.warningCount, 0, reason: report.issues.join('\n'));
    });
  });
}
