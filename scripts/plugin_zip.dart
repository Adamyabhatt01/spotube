// Package a Hetu plugin directory into the `.smplug` archive the app ships
// and auto-installs. Used by scripts/build-radio-plugin.sh after the Hetu
// compiler has produced `build/plugin.out`.
//
//   fvm dart run scripts/plugin_zip.dart <out.smplug> <file>...
//
// Written with `package:archive` rather than the `zip` binary so the build has
// no external tool dependency.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: plugin_zip.dart <out.smplug> <file>...');
    exitCode = 64;
    return;
  }

  final outPath = args.first;
  final archive = Archive();

  for (final path in args.skip(1)) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('missing $path');
      exitCode = 66;
      return;
    }
    // Entry names are what the extractor resolves, so they stay plain.
    final name = file.uri.pathSegments.last;
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final encoded = ZipEncoder().encode(archive);
  await File(outPath).writeAsBytes(Uint8List.fromList(encoded));
  stdout.writeln('zipped ${archive.length} entries -> $outPath (${encoded.length} bytes)');
}
