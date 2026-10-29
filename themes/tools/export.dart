import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/compile.dart';
import '../lib/theme_source.dart';
import '../lib/validator.dart';

/// Writes each theme's payload to `conformance/`.
///
/// The golden payloads are generated, not written by hand: a hand-written
/// golden drifts from the theme it claims to describe, and the drift is
/// invisible until the app draws something nobody expected. Regenerating is
/// one command, and the test suite fails when a committed golden does not
/// match the theme it came from.
Future<void> main(List<String> arguments) async {
  final repoRoot = p.dirname(p.dirname(p.absolute(Platform.script.toFilePath())));
  final outDir = Directory(p.join(repoRoot, 'conformance'));

  var failed = false;

  for (final theme in loadThemes(repoRoot)) {
    final byteCode = compileThemeSource(theme.source, sourceName: '${theme.id}_theme');
    final compiled = await evaluateTheme(byteCode, entryPoint: theme.entryPoint);

    final report = compiled.payload['specVersion'] == 3
        ? validateLegacyThemePayload(compiled.payload)
        : validateThemePayload(compiled.payload);
    if (report.hasErrors) {
      stderr.writeln('${theme.id}: the payload does not validate');
      for (final issue in report.issues) {
        stderr.writeln('  $issue');
      }
      failed = true;
      continue;
    }

    final file = File(p.join(outDir.path, '${theme.id}.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(compiled.payload)}\n',
    );
    stdout.writeln('${theme.id} → ${p.relative(file.path, from: repoRoot)}');
  }

  if (failed) exitCode = 1;
}
