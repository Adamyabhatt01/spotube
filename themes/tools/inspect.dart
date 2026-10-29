import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';

import '../lib/compile.dart';
import '../lib/validator.dart';

/// Inspects a built theme: what payload it produces, and whether two builds
/// agree.
///
/// The payload is what the host draws, so it — not the bytecode — is what two
/// builds have to match. The bytecode embeds the compile-time source name and
/// a timestamp, so two builds of the same source are rarely byte-identical;
/// two payloads always are.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('file', help: 'Theme archives to inspect.', abbr: 'f')
    ..addFlag('json', help: 'Print the payload as JSON.', negatable: false)
    ..addFlag('validate', help: 'Validate the payload.', negatable: false);

  final options = parser.parse(arguments);
  final files = options['file'] as List<String>;
  if (files.isEmpty) {
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final payloads = <String, Map<String, dynamic>>{};

  for (final path in files) {
    final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final entry = archive.firstWhere(
      (file) => file.isFile && file.name == 'plugin.out',
      orElse: () => throw StateError('$path has no plugin.out'),
    );
    final manifest = jsonDecode(
      utf8.decode(
        archive
            .firstWhere((file) => file.isFile && file.name == 'plugin.json')
            .content as List<int>,
      ),
    ) as Map<String, dynamic>;

    final compiled = await evaluateTheme(
      Uint8List.fromList(entry.content as List<int>),
      entryPoint: manifest['entryPoint'] as String,
    );

    payloads[path] = compiled.payload;

    stdout.writeln('$path — ${manifest['name']} ${manifest['version']}');
    if (options['validate'] as bool) {
      final report = compiled.payload['specVersion'] == 3
          ? validateLegacyThemePayload(compiled.payload)
          : validateThemePayload(compiled.payload);
      for (final issue in report.issues) {
        stdout.writeln('  $issue');
      }
      stdout.writeln('  ${report.errorCount} errors, ${report.warningCount} warnings');
    }
    if (options['json'] as bool) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(compiled.payload));
    }
  }

  // Files are compared in pairs: an old build and its rebuild. Comparing
  // everything against the first file would report differences that are just
  // different themes.
  final entries = payloads.entries.toList();
  var same = true;
  for (var i = 0; i + 1 < entries.length; i += 2) {
    final a = entries[i];
    final b = entries[i + 1];
    final equal = _deepEquals(a.value, b.value);
    if (!equal) same = false;
    stdout.writeln('${a.key} vs ${b.key}: '
        '${equal ? 'same payload' : 'DIFFERENT payloads'}');
  }
  if (!same) exitCode = 1;
}

/// Structural equality for decoded JSON.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
