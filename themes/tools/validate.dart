import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../lib/compile.dart';
import '../lib/validator.dart';

/// Validates a theme payload on its own.
///
/// Two sources: a `.smplug` (the payload is read out of the artifact and the
/// theme is run) or a raw JSON file (what a theme author edits by hand, or
/// what a generator emits).
///
/// The exit code is the answer a CI job wants: 0 when the payload is usable,
/// 1 when the app would reject it.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('file', help: 'Payload or artifact to validate.', abbr: 'f')
    ..addFlag('json', help: 'Print the payload as JSON.', negatable: false)
    ..addFlag(
      'explain',
      help: 'Print the payload as the app will use it.',
      negatable: false,
    )
    ..addFlag(
      'strict',
      help: 'Treat warnings as errors.',
      negatable: false,
    );

  final options = parser.parse(arguments);
  final files = options['file'] as List<String>;
  if (files.isEmpty) {
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  var failed = false;

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('$path: no such file');
      failed = true;
      continue;
    }

    final Map<String, dynamic> payload;
    if (p.extension(path) == '.smplug') {
      try {
        payload = await _payloadFromArchive(file);
      } catch (error) {
        stderr.writeln('$path: $error');
        failed = true;
        continue;
      }
    } else {
      try {
        payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (error) {
        stderr.writeln('$path: not valid JSON — $error');
        failed = true;
        continue;
      }
    }

    final report = validateThemePayload(payload);
    final version = payload['specVersion'];
    final versionLabel = version is num ? 'v${version.toInt()}' : 'v2';
    stdout.writeln(
      '$path — $versionLabel, ${report.errorCount} errors, '
      '${report.warningCount} warnings',
    );
    if (version == 4) {
      final capabilities = payload['capabilities'];
      stdout.writeln(
        '  capabilities: ${capabilities is List ? capabilities.join(', ') : 'default'}',
      );
    }
    for (final issue in report.issues) {
      stdout.writeln('  $issue');
    }

    if (options['json'] as bool) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
    }
    if (options['explain'] as bool && report.resolved != null) {
      stdout.writeln('  as the app will use it:');
      stdout.writeln(
        const JsonEncoder.withIndent('  ')
            .convert(report.resolved)
            .split('\n')
            .map((line) => '    $line')
            .join('\n'),
      );
    }

    if (report.hasErrors) {
      failed = true;
    } else if (options['strict'] as bool && report.warningCount > 0) {
      failed = true;
    }
  }

  if (failed) exitCode = 1;
}

/// The payload of a built theme, read out of its archive.
Future<Map<String, dynamic>> _payloadFromArchive(File archive) async {
  final zip = ZipDecoder().decodeBytes(archive.readAsBytesSync());
  final entry = zip.firstWhere(
    (file) => file.isFile && file.name == 'plugin.out',
    orElse: () => throw StateError('no plugin.out in the archive'),
  );
  final manifestEntry = zip.firstWhere(
    (file) => file.isFile && file.name == 'plugin.json',
    orElse: () => throw StateError('no plugin.json in the archive'),
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
