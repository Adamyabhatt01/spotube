import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/migrate_v3.dart';
import '../lib/validator.dart';

/// Migrates a v3 theme payload to v4.
///
/// This is the only supported path for a v3 theme: the v4 host rejects
/// `specVersion: 3` outright. The tool writes a best-effort payload and a
/// report; nodes such as `search` need a human decision about their bindings
/// and actions.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('file', help: 'v3 payload JSON to migrate.', abbr: 'f')
    ..addOption(
      'out',
      help: 'Output file (default: stdout).',
      abbr: 'o',
    )
    ..addOption(
      'report',
      help: 'Report file (default: stderr).',
    )
    ..addFlag('quiet', help: 'Write the report only.', negatable: false);

  final options = parser.parse(arguments);
  final files = options['file'] as List<String>;
  if (files.isEmpty) {
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }
  final out = options['out'] as String?;
  if (files.length > 1 && out != null) {
    stderr.writeln('--out takes one output file; migrate one theme at a time');
    exitCode = 64;
    return;
  }

  final reportSink = options['report'] as String?;
  final reportBuffer = StringBuffer();
  var failed = false;

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('$path: no such file');
      failed = true;
      continue;
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (error) {
      stderr.writeln('$path: not valid JSON — $error');
      failed = true;
      continue;
    }

    final migrated = migrateV3Theme(payload);
    final report = migrated.payload['specVersion'] == 4
        ? validateThemePayload(migrated.payload)
        : null;

    reportBuffer.writeln('$path');
    migrated.describe(reportBuffer);
    if (report != null) {
      reportBuffer.writeln(
        'v4 validation: ${report.errorCount} errors, '
        '${report.warningCount} warnings',
      );
      for (final issue in report.issues) {
        reportBuffer.writeln('  $issue');
      }
      if (report.hasErrors) {
        failed = true;
      }
    }

    if (out != null) {
      File(out).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(migrated.payload)}\n',
      );
    } else if (!(options['quiet'] as bool)) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(migrated.payload),
      );
    }
  }

  final reportText = reportBuffer.toString();
  if (reportSink != null) {
    File(reportSink).writeAsStringSync(reportText);
  } else {
    stderr.write(reportText);
  }

  if (failed) exitCode = 1;
}

/// The output path a caller most likely wants for [input].
String suggestedOutput(String input) {
  final dir = p.dirname(input);
  final name = p.basenameWithoutExtension(input);
  return p.join(dir, '$name.v4.json');
}
