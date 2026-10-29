import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Where a plugin lives inside a profile.
///
/// The host's own rule: `<app support>/metadata-plugins`, and one directory
/// per plugin version, named `<author>-<name>-<version>`.
String pluginRootDir(String profile) => p.join(
  profile,
  '.local',
  'share',
  'oss.krtirtho.spotube',
  'metadata-plugins',
);

/// The database the host keeps its plugin list in.
String pluginDatabaseFile(String profile) =>
    p.join(profile, '.local', 'share', 'oss.krtirtho.spotube', 'db.sqlite');

/// The host's filename sanitizer, mirrored so the extraction directory name
/// matches what the host computes.
String sanitizeFilename(String input) {
  var result = input
      .replaceAll(RegExp(r'[\/\?<>\\:\*\|"]'), '')
      .replaceAll(RegExp(r'[\x00-\x1f\x80-\x9f]'), '')
      .replaceFirst(RegExp(r'^\.+$'), '')
      .replaceFirst(
        RegExp(
          r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(RegExp(r'[\. ]+$'), '');
  if (result.length > 255) result = result.substring(0, 255);
  return result;
}

/// A plugin archive, read into memory.
class PluginArchive {
  PluginArchive({required this.manifest, required this.entries});

  final Map<String, dynamic> manifest;

  /// The archive's files, by entry name.
  final Map<String, List<int>> entries;

  String get name => manifest['name'] as String;

  String get author => manifest['author'] as String;

  String get version => manifest['version'] as String;

  String get entryPoint => manifest['entryPoint'] as String;

  List<String> get abilities => [
    for (final ability in (manifest['abilities'] as List? ?? const []))
      '$ability',
  ];

  List<String> get apis => [
    for (final api in (manifest['apis'] as List? ?? const [])) '$api',
  ];

  /// The directory the host extracts this plugin into.
  String get extractionDirName =>
      '${sanitizeFilename(author)}-${sanitizeFilename(name)}-$version';

  /// Reads an archive from disk.
  static PluginArchive read(File file) {
    final zip = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final manifestEntry = zip.firstWhere(
      (file) => file.isFile && file.name == 'plugin.json',
      orElse: () => throw StateError('${file.path} has no plugin.json'),
    );
    final manifest =
        jsonDecode(utf8.decode(manifestEntry.content as List<int>))
            as Map<String, dynamic>;

    return PluginArchive(
      manifest: manifest,
      entries: {
        for (final entry in zip)
          if (entry.isFile) entry.name: entry.content as List<int>,
      },
    );
  }
}

/// What an install did.
class InstallResult {
  InstallResult({
    required this.extractionDir,
    required this.registered,
    required this.message,
  });

  final Directory extractionDir;

  /// Whether the database row was written.
  final bool registered;

  final String message;
}

/// Writes a plugin into a profile: its files, and its row in the database.
///
/// The app must not be running while this writes: the database is locked by
/// the app's own connection.
InstallResult installPlugin({
  required PluginArchive archive,
  required String profile,
  bool select = false,
  bool dryRun = false,
}) {
  final root = Directory(pluginRootDir(profile));
  final target = Directory(p.join(root.path, archive.extractionDirName));
  final dbFile = File(pluginDatabaseFile(profile));

  if (dryRun) {
    return InstallResult(
      extractionDir: target,
      registered: false,
      message:
          'would write ${target.path} and register '
          '${archive.name} ${archive.version}',
    );
  }

  target.createSync(recursive: true);
  for (final entry in archive.entries.entries) {
    final file = File(p.join(target.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.value);
  }

  if (!dbFile.existsSync()) {
    return InstallResult(
      extractionDir: target,
      registered: false,
      message:
          'no database at ${dbFile.path} — the files are in place, but '
          'the app will not list the plugin until it is registered',
    );
  }

  final database = sqlite3.open(dbFile.path);
  try {
    database.execute('PRAGMA busy_timeout = 2000');
    final existing = database.select(
      'SELECT id FROM plugins_table WHERE name = ? AND author = ?',
      [archive.name, archive.author],
    );

    final values = <String, Object?>{
      'name': archive.name,
      'description': archive.manifest['description'] as String? ?? '',
      'version': archive.version,
      'author': archive.author,
      'entry_point': archive.entryPoint,
      'apis': jsonEncode(archive.apis),
      'abilities': jsonEncode(archive.abilities),
      'selected_for_metadata': 0,
      'selected_for_audio_source': 0,
      'selected_for_theme': 0,
      'selected_for_radio': 0,
      'repository': archive.manifest['repository'],
      'plugin_api_version':
          archive.manifest['pluginApiVersion'] as String? ?? '2.0.0',
    };

    if (existing.isEmpty) {
      final columns = values.keys.toList();
      database.execute(
        'INSERT INTO plugins_table (${columns.join(', ')}) '
        'VALUES (${columns.map((_) => '?').join(', ')})',
        columns.map((column) => values[column]).toList(),
      );
    } else {
      final id = existing.first['id'];
      database.execute(
        'UPDATE plugins_table SET '
        '${values.keys.map((key) => '$key = ?').join(', ')} WHERE id = ?',
        [...values.values, id],
      );
    }

    if (select) {
      database.execute('UPDATE plugins_table SET selected_for_theme = 0');
      database.execute(
        'UPDATE plugins_table SET selected_for_theme = 1 '
        'WHERE name = ? AND author = ?',
        [archive.name, archive.author],
      );
    }

    return InstallResult(
      extractionDir: target,
      registered: true,
      message:
          'installed ${archive.name} ${archive.version} '
          '(${archive.author}) → ${target.path}',
    );
  } finally {
    database.dispose();
  }
}

/// The `plugins_table` the host keeps, for a profile that has none yet.
///
/// The host's own schema; a profile without a database gets one that looks
/// like it, so a theme can be installed into a scratch profile.
void createPluginTable(File dbFile) {
  dbFile.parent.createSync(recursive: true);
  final database = sqlite3.open(dbFile.path);
  try {
    database.execute('''
      CREATE TABLE IF NOT EXISTS plugins_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        version TEXT NOT NULL,
        author TEXT NOT NULL,
        entry_point TEXT NOT NULL,
        apis TEXT NOT NULL,
        abilities TEXT NOT NULL,
        selected_for_metadata INTEGER NOT NULL DEFAULT 0,
        selected_for_audio_source INTEGER NOT NULL DEFAULT 0,
        selected_for_theme INTEGER NOT NULL DEFAULT 0,
        selected_for_radio INTEGER NOT NULL DEFAULT 0,
        repository TEXT,
        plugin_api_version TEXT NOT NULL DEFAULT '2.0.0'
      )
    ''');
  } finally {
    database.dispose();
  }
}
