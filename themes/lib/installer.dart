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

/// SharedPreferences file of the same profile.
///
/// The theme definition cache, the selected-theme identity key and every
/// `theme.<author>.<name>.*` setting live here, so an uninstall that leaves it
/// alone keeps a warm-start cache pointing at files that no longer exist.
String pluginPreferencesFile(String profile) => p.join(
  profile,
  '.local',
  'share',
  'oss.krtirtho.spotube',
  'shared_preferences.json',
);

/// Keys [pluginPreferencesFile] stores the resolved theme and its identity
/// under. Mirrors `lib/services/theme_definition_cache.dart` in the app.
const _themeCacheKey = 'spotube.theme_definition_cache.v3';
const _themePluginKeyKey = 'spotube.theme_default_plugin_key.v1';

/// Entry count and total size an archive may claim before the host refuses it.
///
/// Both limits are the app's (`PluginStorage`), mirrored here so a theme that
/// installs from the command line passes the same gate it will meet inside the
/// app: an author who hits them locally never ships something the app silently
/// rejects later.
const maxArchiveEntries = 2000;
const maxArchiveBytes = 50 * 1024 * 1024;

/// True when [name] cannot escape the plugin extraction directory.
///
/// Mirrors `PluginStorage.isSafePluginEntryPath` in the app: both separator
/// styles normalize first, so a Windows-style `..\evil` entry is rejected on
/// every platform, `a/../../b` is caught by normalization rather than by a
/// substring scan, and a drive letter is refused even when extracting on Linux.
bool isSafePluginEntryPath(String name) {
  final normalized = p.normalize(name.replaceAll('\\', '/'));
  if (p.isAbsolute(normalized)) return false;
  if (normalized == '..' || normalized.startsWith('../')) return false;
  if (RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) return false;
  return true;
}

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
  PluginArchive({
    required this.manifest,
    required this.entries,
    this.symlinkNames = const [],
    this.entryCount = 0,
  });

  final Map<String, dynamic> manifest;

  /// The archive's regular files, by entry name.
  final Map<String, List<int>> entries;

  /// Entry names the archive claims are symbolic links. The extractors write
  /// files only, so these cannot redirect an extraction, but a theme that
  /// ships one is malformed and no other unzipper is that careful.
  final List<String> symlinkNames;

  /// Every entry in the archive, including directories and links.
  final int entryCount;

  String get name => manifest['name'] as String? ?? '';

  String get author => manifest['author'] as String? ?? '';

  String get version => manifest['version'] as String? ?? '';

  String get entryPoint => manifest['entryPoint'] as String? ?? '';

  List<String> get abilities => [
    for (final ability in (manifest['abilities'] as List? ?? const []))
      '$ability',
  ];

  List<String> get apis => [
    for (final api in (manifest['apis'] as List? ?? const [])) '$api',
  ];

  /// Total bytes the archive claims once unpacked — what the size cap is about.
  int get totalBytes =>
      entries.values.fold<int>(0, (total, bytes) => total + bytes.length);

  /// The directory the host extracts this plugin into.
  String get extractionDirName =>
      '${sanitizeFilename(author)}-${sanitizeFilename(name)}-$version';

  /// Everything that makes this archive uninstallable, empty when it is fine.
  ///
  /// Checked before a single byte is written, and the same rules the app's
  /// extractor applies: `manifest` fields the host reads as required, entry
  /// names that stay inside the extraction directory, and the entry/size caps.
  /// A crafted `version` decides where every entry lands, so it is validated
  /// like an entry name rather than trusted as a string.
  List<String> get problems {
    final issues = <String>[];

    for (final field in const ['name', 'author', 'version', 'entryPoint']) {
      final value = manifest[field];
      if (value is! String || value.trim().isEmpty) {
        issues.add('plugin.json: "$field" must be a non-empty string');
      } else if (value.length > 128) {
        issues.add('plugin.json: "$field" is longer than 128 characters');
      }
    }

    // The directory name is built from the sanitized author and name: a value
    // made only of forbidden characters would extract into `-<version>`.
    for (final field in const ['name', 'author']) {
      final value = manifest[field];
      if (value is String && value.trim().isNotEmpty) {
        if (sanitizeFilename(value).isEmpty) {
          issues.add('plugin.json: "$field" has no characters a path can use');
        }
      }
    }

    final version = manifest['version'];
    if (version is String &&
        version.trim().isNotEmpty &&
        !isSafePluginEntryPath(version)) {
      issues.add('plugin.json: "version" must not contain a path');
    }

    for (final field in const ['description', 'pluginApiVersion']) {
      final value = manifest[field];
      if (value != null && value is! String) {
        issues.add('plugin.json: "$field" must be a string');
      }
    }

    final abilities = manifest['abilities'];
    if (abilities != null && abilities is! List) {
      issues.add('plugin.json: "abilities" must be a list');
    } else if (!this.abilities.contains('theme')) {
      issues.add('plugin.json: "abilities" must contain "theme"');
    }

    final apis = manifest['apis'];
    if (apis != null && apis is! List) {
      issues.add('plugin.json: "apis" must be a list');
    } else {
      for (final api in this.apis) {
        if (!_knownApis.contains(api)) {
          issues.add('plugin.json: unknown api "$api"');
        }
      }
    }

    if (!entries.containsKey('plugin.out')) {
      issues.add('archive has no plugin.out — the host cannot load it');
    }

    if (entryCount > maxArchiveEntries) {
      issues.add(
        'archive has $entryCount entries, over the $maxArchiveEntries the host extracts',
      );
    }
    if (totalBytes > maxArchiveBytes) {
      issues.add(
        'archive unpacks to ${totalBytes} bytes, over the $maxArchiveBytes the host extracts',
      );
    }
    for (final entry in entries.keys) {
      if (!isSafePluginEntryPath(entry)) {
        issues.add('entry "$entry" would land outside the plugin directory');
      }
    }
    for (final link in symlinkNames) {
      issues.add(
        'entry "$link" is a symbolic link, which a theme may not ship',
      );
    }

    return issues;
  }

  /// Reads an archive from disk.
  static PluginArchive read(File file) {
    final zip = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final manifestEntry = zip.firstWhere(
      (entry) => entry.isFile && entry.name == 'plugin.json',
      orElse: () => throw StateError('${file.path} has no plugin.json'),
    );
    final decoded = jsonDecode(utf8.decode(manifestEntry.content as List<int>));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('${file.path}: plugin.json is not a JSON object');
    }

    return PluginArchive(
      manifest: decoded,
      entries: {
        for (final entry in zip)
          if (entry.isFile && !entry.isSymbolicLink)
            entry.name: entry.content as List<int>,
      },
      symlinkNames: [
        for (final entry in zip)
          if (entry.isSymbolicLink) entry.name,
      ],
      entryCount: zip.length,
    );
  }
}

/// The plugin APIs the host knows about (`PluginApis` in the app).
const _knownApis = {'webview', 'localstorage', 'timezone'};

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

  // Nothing is written for an archive the app would reject anyway: the
  // manifest is read and every entry name checked before the first byte.
  final problems = archive.problems;
  if (problems.isNotEmpty) {
    return InstallResult(
      extractionDir: target,
      registered: false,
      message:
          '${archive.name} ${archive.version} is not installable:\n'
          '${problems.map((issue) => '  - $issue').join('\n')}',
    );
  }

  if (dryRun) {
    return InstallResult(
      extractionDir: target,
      registered: false,
      message:
          'would write ${target.path} and register '
          '${archive.name} ${archive.version}',
    );
  }

  // Staged the way the host's own extractor stages: write beside the target,
  // then swap. A failed install leaves the working version untouched instead of
  // half-overwritten, and a running app never sees a plugin mid-copy.
  final staging = Directory('${target.path}.tmp');
  final backup = Directory('${target.path}.backup');
  var movedAside = false;
  try {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    for (final entry in archive.entries.entries) {
      final file = File(p.join(staging.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.value);
    }

    if (backup.existsSync()) backup.deleteSync(recursive: true);
    movedAside = target.existsSync();
    if (movedAside) target.renameSync(backup.path);
    staging.renameSync(target.path);
    if (movedAside) backup.deleteSync(recursive: true);
  } catch (error) {
    // Undo the swap: the profile ends exactly where it started.
    if (movedAside && !target.existsSync() && backup.existsSync()) {
      backup.renameSync(target.path);
    }
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {
        // An orphaned `.tmp` is never registered and the next install removes it.
      }
    }
    return InstallResult(
      extractionDir: target,
      registered: false,
      message: 'could not write ${target.path}: $error',
    );
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

/// What an uninstall removed.
class UninstallResult {
  UninstallResult({
    required this.removedDirs,
    required this.removedRow,
    required this.wasSelectedForTheme,
    required this.clearedPreferences,
    required this.message,
  });

  /// Plugin directories taken off the disk.
  final List<String> removedDirs;

  final bool removedRow;

  /// Whether this plugin was the active theme. When its row went with it, the
  /// profile has no theme left and the app starts on the built-in one.
  final bool wasSelectedForTheme;

  final bool clearedPreferences;

  final String message;
}

/// Removes a plugin from a profile: its files, its row, and the profile's own
/// records of it.
///
/// [version] takes one installed version off the disk. Without it every version
/// of `author`/`name` goes, because the row is keyed by that pair alone and a
/// directory whose row is gone is a plugin the app cannot load. With it, the row
/// goes only when it names that version — a newer one still registered would
/// otherwise lose its plugin.
UninstallResult uninstallPlugin({
  required String name,
  required String author,
  String? version,
  required String profile,
  bool dryRun = false,
}) {
  final root = Directory(pluginRootDir(profile));
  final slug = '${sanitizeFilename(author)}-${sanitizeFilename(name)}';
  final dirs = <Directory>[];
  if (root.existsSync()) {
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final base = p.basename(entity.path);
      if (version == null) {
        if (base.startsWith('$slug-')) dirs.add(entity);
      } else if (base == '$slug-$version') {
        dirs.add(entity);
      }
    }
  }

  String? rowVersion;
  var hadRow = false;
  var wasSelectedForTheme = false;
  var removedRow = false;
  // One row per author and name, holding the version the app loads. Removing a
  // different version's files must leave it alone: the plugin is still
  // installed, and deleting its row would take a working theme with it.
  var rowIsThisVersion = true;
  final dbFile = File(pluginDatabaseFile(profile));
  if (dbFile.existsSync()) {
    final database = sqlite3.open(dbFile.path);
    try {
      database.execute('PRAGMA busy_timeout = 2000');
      final rows = database.select(
        'SELECT version, selected_for_theme FROM plugins_table '
        'WHERE name = ? AND author = ?',
        [name, author],
      );
      if (rows.isNotEmpty) {
        hadRow = true;
        rowVersion = rows.first['version'] as String?;
        wasSelectedForTheme =
            (rows.first['selected_for_theme'] as int? ?? 0) == 1;
        rowIsThisVersion =
            version == null || rowVersion == null || rowVersion == version;
        if (!dryRun && rowIsThisVersion) {
          database.execute(
            'DELETE FROM plugins_table WHERE name = ? AND author = ?',
            [name, author],
          );
          removedRow = true;
        }
      }
    } finally {
      database.dispose();
    }
  }

  // Which identity the warm-start cache and the settings namespace are keyed
  // by. A row and a directory can disagree only on a half-finished install.
  final identity = version ?? rowVersion;

  if (dryRun) {
    final rowPhrase = !hadRow
        ? ''
        : rowIsThisVersion
        ? ' and the row'
        : ', keeping the row';
    return UninstallResult(
      removedDirs: [for (final dir in dirs) dir.path],
      removedRow: false,
      wasSelectedForTheme: wasSelectedForTheme,
      clearedPreferences: false,
      message:
          'would remove ${dirs.length} director'
          '${dirs.length == 1 ? 'y' : 'ies'}$rowPhrase '
          'for $author/$name${identity == null ? '' : ' $identity'}',
    );
  }

  final removed = <String>[];
  final failures = <String>[];
  for (final dir in dirs) {
    // `.backup` and `.tmp` siblings are what an interrupted swap leaves; the
    // app never serves them, and an uninstall that skips them keeps files
    // belonging to a plugin that no longer exists.
    for (final path in [dir.path, '${dir.path}.backup', '${dir.path}.tmp']) {
      if (!FileSystemEntity.isDirectorySync(path)) continue;
      try {
        Directory(path).deleteSync(recursive: true);
        if (path == dir.path) removed.add(path);
      } catch (error) {
        failures.add('$path: $error');
      }
    }
  }

  // The settings namespace is keyed by author and name only, so it belongs to
  // the theme rather than to one version's files. It goes with the row.
  final cleared = clearThemePreferences(
    profile: profile,
    author: author,
    name: name,
    version: identity,
    clearSettings: !hadRow || removedRow,
  );

  final rowOutcome = !hadRow
      ? 'no row'
      : removedRow
      ? 'deleted the row'
      : 'kept the row';
  final summary =
      'removed ${removed.length} director'
      '${removed.length == 1 ? 'y' : 'ies'}, '
      '$rowOutcome for $author/$name'
      '${wasSelectedForTheme && removedRow ? ' (was the active theme; the app falls back to the built-in one)' : ''}'
      '${cleared ? ', cleared its cached definition and settings' : ''}';

  return UninstallResult(
    removedDirs: removed,
    removedRow: removedRow,
    wasSelectedForTheme: wasSelectedForTheme,
    clearedPreferences: cleared,
    message: failures.isEmpty
        ? summary
        : '$summary\n  - ${failures.join('\n  - ')}',
  );
}

/// Drops a removed theme's records from a profile's preferences file.
///
/// A profile keeps three things about a theme beyond its files: which plugin is
/// the theme default, the warm-start definition cached for it, and whatever the
/// theme wrote through its own settings actions. Leaving them behind means a
/// cache naming a directory that no longer exists, and settings no theme will
/// ever read again.
///
/// [clearSettings] is false while another version of the same theme is still
/// installed: the namespace is keyed by author and name, so those values belong
/// to the theme that is staying.
bool clearThemePreferences({
  required String profile,
  required String author,
  required String name,
  String? version,
  bool clearSettings = true,
}) {
  final file = File(pluginPreferencesFile(profile));
  if (!file.existsSync()) return false;

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (_) {
    return false;
  }
  if (decoded is! Map<String, dynamic>) return false;

  final settingsPrefix = 'theme.$author.$name.';
  final identityPrefix = '$author::$name::';
  final exactIdentity = version == null ? null : '$identityPrefix$version';
  var changed = false;

  if (clearSettings) {
    for (final key in decoded.keys.toList()) {
      if (key.startsWith(settingsPrefix)) {
        decoded.remove(key);
        changed = true;
      }
    }
  }

  bool namesThisTheme(Object? raw) {
    if (raw is! String) return false;
    return exactIdentity == null
        ? raw.startsWith(identityPrefix)
        : raw == exactIdentity;
  }

  if (namesThisTheme(decoded[_themePluginKeyKey])) {
    decoded.remove(_themePluginKeyKey);
    changed = true;
  }

  final cached = decoded[_themeCacheKey];
  if (cached is String) {
    Object? parsed;
    try {
      parsed = jsonDecode(cached);
    } catch (_) {
      parsed = null;
    }
    if (namesThisTheme(parsed is Map ? parsed['pluginKey'] : null)) {
      decoded.remove(_themeCacheKey);
      changed = true;
    }
  }

  if (!changed) return false;

  final previous = file.readAsStringSync();
  try {
    file.writeAsStringSync(jsonEncode(decoded));
  } catch (_) {
    // Best effort: a half-written preferences file costs the user every
    // preference, so put back what it held before.
    try {
      file.writeAsStringSync(previous);
    } catch (_) {}
    return false;
  }
  return true;
}
