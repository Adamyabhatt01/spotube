import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// The fixed timestamp every archive entry gets.
///
/// Reproducible builds: the same source produces the same bytes, so a
/// rebuilt artifact can be compared to the committed one instead of trusted.
final _fixedTimestamp = DateTime.utc(2020, 1, 1);

/// Writes a `.smplug` archive.
///
/// Entry names are preserved exactly as given — `plugin.json`, `plugin.out`
/// and `assets/<relative path>` — because the app's extractor writes entries
/// relative to the plugin directory. (The app's own `scripts/plugin_zip.dart`
/// flattens names to basenames, which is why this repo does its own
/// packaging.)
File packageTheme({
  required String outputPath,
  required Map<String, Uint8List> entries,
}) {
  final archive = Archive();
  final names = entries.keys.toList()..sort();
  for (final name in names) {
    final bytes = entries[name]!;
    final entry = ArchiveFile(name, bytes.length, bytes);
    // A fixed timestamp is what makes the build reproducible: the same
    // source has to produce the same bytes, so a rebuilt artifact can be
    // compared to the committed one instead of merely trusted.
    entry.lastModTime = _fixedTimestamp.millisecondsSinceEpoch ~/ 1000;
    archive.addFile(entry);
  }

  final encoded = ZipEncoder().encode(archive);
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(Uint8List.fromList(encoded));
  return file;
}

/// The SHA-256 of a file, for the build index.
String sha256OfFile(File file) {
  final digest = sha256.convert(file.readAsBytesSync());
  return digest.toString();
}

/// The bytes of a JSON map, encoded the way the plugin manifest expects.
///
/// Compact, one line: the manifests that ship today are one line each, and
/// keeping the encoding stable means a rebuilt artifact's manifest is
/// byte-identical to the committed one.
Uint8List jsonBytes(Map<String, dynamic> map) =>
    Uint8List.fromList(utf8.encode(jsonEncode(map)));
