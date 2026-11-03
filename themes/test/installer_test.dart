import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/installer.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _themeName = 'Caelestia Shell Theme';
const _themeAuthor = 'Adamya Bhatt';
const _themeVersion = '1.2.0';

/// An archive built in memory, so a test can hand the installer exactly the
/// malformed manifest or entry it is about, without a zip encoder that cannot
/// express a symbolic link.
PluginArchive archive({
  String name = _themeName,
  String author = _themeAuthor,
  String version = _themeVersion,
  String? bytecode = 'fake-bytecode',
  String pluginApiVersion = '2.0.0',
  List<String> abilities = const ['theme'],
  List<String> apis = const [],
  Map<String, String> extraEntries = const {},
  List<String> symlinkNames = const [],
  int? entryCount,
}) {
  final manifest = <String, dynamic>{
    'name': name,
    'description': 'test',
    'version': version,
    'author': author,
    'entryPoint': 'plugin.out',
    'pluginApiVersion': pluginApiVersion,
    'abilities': abilities,
    'apis': apis,
  };
  final entries = <String, List<int>>{
    'plugin.json': utf8.encode(jsonEncode(manifest)),
    if (bytecode != null) 'plugin.out': utf8.encode(bytecode),
    for (final entry in extraEntries.entries)
      entry.key: utf8.encode(entry.value),
  };
  return PluginArchive(
    manifest: manifest,
    entries: entries,
    symlinkNames: symlinkNames,
    entryCount: entryCount ?? entries.length,
  );
}

Map<String, dynamic> _preferences(String profile) =>
    jsonDecode(File(pluginPreferencesFile(profile)).readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late Directory profile;

  setUp(() {
    profile = Directory.systemTemp.createTempSync('spotube-theme-profile');
  });

  tearDown(() {
    if (profile.existsSync()) profile.deleteSync(recursive: true);
  });

  group('installing a built theme', () {
    test('writes the plugin where the app looks for it', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));

      final artifact = File('dist/caelestia-1.2.0.smplug');
      expect(artifact.existsSync(), isTrue, reason: 'build the themes first');

      final result = installPlugin(
        archive: PluginArchive.read(artifact),
        profile: profile.path,
      );

      expect(result.registered, isTrue);
      expect(
        result.extractionDir.path,
        endsWith('metadata-plugins/Adamya Bhatt-Caelestia Shell Theme-1.2.0'),
      );
      expect(
        File('${result.extractionDir.path}/plugin.json').existsSync(),
        isTrue,
      );
      expect(
        File('${result.extractionDir.path}/plugin.out').existsSync(),
        isTrue,
      );
    });

    test('registers it in the profile database', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));

      installPlugin(
        archive: PluginArchive.read(File('dist/caelestia-1.2.0.smplug')),
        profile: profile.path,
        select: true,
      );

      final database = sqlite3.open(pluginDatabaseFile(profile.path));
      try {
        final rows = database.select(
          'SELECT name, author, version, abilities, selected_for_theme '
          'FROM plugins_table',
        );
        expect(rows, hasLength(1));
        expect(rows.first['name'], 'Caelestia Shell Theme');
        expect(rows.first['author'], 'Adamya Bhatt');
        expect(rows.first['version'], '1.2.0');
        expect(rows.first['abilities'], contains('theme'));
        expect(rows.first['selected_for_theme'], 1);
      } finally {
        database.dispose();
      }
    });

    test(
      'installing the same theme twice replaces it rather than duplicating',
      () {
        createPluginTable(File(pluginDatabaseFile(profile.path)));

        installPlugin(
          archive: PluginArchive.read(File('dist/caelestia-1.2.0.smplug')),
          profile: profile.path,
        );
        installPlugin(
          archive: PluginArchive.read(File('dist/caelestia-1.2.0.smplug')),
          profile: profile.path,
        );

        final database = sqlite3.open(pluginDatabaseFile(profile.path));
        try {
          final rows = database.select('SELECT id FROM plugins_table');
          expect(rows, hasLength(1));
        } finally {
          database.dispose();
        }
      },
    );

    test('says what it would do without touching anything', () {
      final result = installPlugin(
        archive: PluginArchive.read(File('dist/caelestia-1.2.0.smplug')),
        profile: profile.path,
        dryRun: true,
      );

      expect(result.registered, isFalse);
      expect(result.message, contains('would write'));
      expect(profile.listSync(), isEmpty);
    });
  });

  group('the extraction directory name', () {
    test('is the one the host computes', () {
      final archive = PluginArchive.read(File('dist/caelestia-1.2.0.smplug'));
      expect(
        archive.extractionDirName,
        'Adamya Bhatt-Caelestia Shell Theme-1.2.0',
      );
    });

    test('cannot escape the plugin directory', () {
      // The host's rule: the illegal characters go, a whole name of dots
      // goes, and what is left can never be a path segment of its own.
      for (final name in ['../../etc', 'a/b', '..', '.', 'C:\\windows']) {
        final sanitized = sanitizeFilename(name);
        expect(sanitized.contains('/'), isFalse, reason: name);
        expect(sanitized.split('/'), isNot(contains('..')), reason: name);
      }
      expect(sanitizeFilename('normal name'), 'normal name');
    });
  });

  group('an archive the app would reject', () {
    test('lists every problem and writes nothing at all', () {
      final result = installPlugin(
        archive: archive(
          version: '../../etc',
          abilities: ['metadata'],
          apis: ['filesystem'],
          extraEntries: {'../escape.bin': 'pwn'},
          symlinkNames: ['assets/logo.png'],
          entryCount: maxArchiveEntries + 1,
        ),
        profile: profile.path,
      );

      expect(result.registered, isFalse);
      expect(result.message, contains('is not installable'));
      for (final problem in [
        '"version" must not contain a path',
        'must contain "theme"',
        'unknown api "filesystem"',
        '../escape.bin',
        'symbolic link',
        'over the $maxArchiveEntries',
      ]) {
        expect(result.message, contains(problem), reason: problem);
      }
      expect(Directory(pluginRootDir(profile.path)).existsSync(), isFalse);
      expect(profile.listSync(), isEmpty);
    });

    test('a manifest missing a required field is reported, not crashed on', () {
      final result = installPlugin(
        archive: archive(name: ''),
        profile: profile.path,
      );

      expect(result.registered, isFalse);
      expect(result.message, contains('"name" must be a non-empty string'));
    });

    test('an unparseable pluginApiVersion is refused', () {
      final result = installPlugin(
        archive: archive(pluginApiVersion: 'v2'),
        profile: profile.path,
      );

      expect(result.registered, isFalse);
      expect(result.message, contains('"pluginApiVersion" is not a version'));
    });

    test('an archive without bytecode is refused before the files land', () {
      final result = installPlugin(
        archive: archive(
          bytecode: null,
          extraEntries: {'assets/bg.png': 'png'},
        ),
        profile: profile.path,
      );

      expect(result.message, contains('no plugin.out'));
      expect(Directory(pluginRootDir(profile.path)).existsSync(), isFalse);
    });
  });

  group('staged install', () {
    test('reinstalling swaps the directory and leaves no siblings behind', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));

      final first = installPlugin(
        archive: archive(bytecode: 'one'),
        profile: profile.path,
      );
      expect(first.registered, isTrue);

      final second = installPlugin(
        archive: archive(bytecode: 'two'),
        profile: profile.path,
      );
      expect(second.registered, isTrue);
      expect(
        File('${second.extractionDir.path}/plugin.out').readAsStringSync(),
        'two',
      );
      expect(
        Directory('${first.extractionDir.path}.tmp').existsSync(),
        isFalse,
      );
      expect(
        Directory('${first.extractionDir.path}.backup').existsSync(),
        isFalse,
      );
    });
  });

  group('uninstalling', () {
    /// A preferences file shaped like a real one: the theme's own settings,
    /// the selected-theme identity, a warm-start definition, and unrelated keys.
    void writePreferences(String profile) {
      final file = File(pluginPreferencesFile(profile))
        ..createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'spotube.theme_default_plugin_key.v1':
              '$_themeAuthor::$_themeName::$_themeVersion',
          'spotube.theme_definition_cache.v3': jsonEncode({
            'v': 3,
            'pluginKey': '$_themeAuthor::$_themeName::$_themeVersion',
          }),
          'theme.$_themeAuthor.$_themeName.compact': true,
          'theme.$_themeAuthor.Other Theme.compact': false,
          'locale': 'en',
        }),
      );
    }

    test(
      'removes the files, the row and the profile records of that theme',
      () {
        createPluginTable(File(pluginDatabaseFile(profile.path)));
        final installed = installPlugin(
          archive: archive(),
          profile: profile.path,
          select: true,
        );
        writePreferences(profile.path);

        final result = uninstallPlugin(
          name: _themeName,
          author: _themeAuthor,
          profile: profile.path,
        );

        expect(result.removedDirs, [installed.extractionDir.path]);
        expect(result.removedRow, isTrue);
        expect(result.wasSelectedForTheme, isTrue);
        expect(result.message, contains('falls back to the built-in one'));
        expect(installed.extractionDir.existsSync(), isFalse);

        final database = sqlite3.open(pluginDatabaseFile(profile.path));
        try {
          expect(database.select('SELECT id FROM plugins_table'), isEmpty);
        } finally {
          database.dispose();
        }

        final kept = _preferences(profile.path);
        expect(
          kept.containsKey('theme.$_themeAuthor.$_themeName.compact'),
          isFalse,
        );
        expect(
          kept.containsKey('spotube.theme_default_plugin_key.v1'),
          isFalse,
        );
        expect(kept.containsKey('spotube.theme_definition_cache.v3'), isFalse);
        // Another theme's setting and the user's own preferences survive.
        expect(kept['theme.$_themeAuthor.Other Theme.compact'], false);
        expect(kept['locale'], 'en');
      },
    );

    test('says what it would remove and changes nothing', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));
      final installed = installPlugin(
        archive: archive(),
        profile: profile.path,
        select: true,
      );
      writePreferences(profile.path);
      final before = File(
        pluginPreferencesFile(profile.path),
      ).readAsStringSync();

      final result = uninstallPlugin(
        name: _themeName,
        author: _themeAuthor,
        profile: profile.path,
        dryRun: true,
      );

      expect(result.message, contains('would remove'));
      expect(result.removedRow, isFalse);
      expect(result.clearedPreferences, isFalse);
      expect(installed.extractionDir.existsSync(), isTrue);
      expect(
        File(pluginPreferencesFile(profile.path)).readAsStringSync(),
        before,
      );
    });

    test('names the plugin it could not find instead of claiming success', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));

      final result = uninstallPlugin(
        name: 'Never Installed',
        author: _themeAuthor,
        profile: profile.path,
      );

      expect(result.removedDirs, isEmpty);
      expect(result.removedRow, isFalse);
      expect(result.message, contains('no row'));
    });

    test('one version can go while another stays installed', () {
      createPluginTable(File(pluginDatabaseFile(profile.path)));
      installPlugin(
        archive: archive(version: '1.2.0'),
        profile: profile.path,
      );
      installPlugin(
        archive: archive(version: '1.3.0'),
        profile: profile.path,
      );
      File(pluginPreferencesFile(profile.path))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'theme.$_themeAuthor.$_themeName.compact': true,
            'spotube.theme_default_plugin_key.v1':
                '$_themeAuthor::$_themeName::1.3.0',
          }),
        );

      final result = uninstallPlugin(
        name: _themeName,
        author: _themeAuthor,
        version: '1.2.0',
        profile: profile.path,
      );

      expect(result.removedDirs, hasLength(1));
      expect(
        Directory(
          p.join(
            pluginRootDir(profile.path),
            '$_themeAuthor-$_themeName-1.3.0',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        Directory(
          p.join(
            pluginRootDir(profile.path),
            '$_themeAuthor-$_themeName-1.2.0',
          ),
        ).existsSync(),
        isFalse,
      );

      // The row names 1.3.0, so it stays: the settings namespace is keyed by
      // author and name only, and the theme that is still installed owns it.
      expect(result.removedRow, isFalse);
      final kept = _preferences(profile.path);
      expect(kept['theme.$_themeAuthor.$_themeName.compact'], isTrue);
      expect(
        kept['spotube.theme_default_plugin_key.v1'],
        '$_themeAuthor::$_themeName::1.3.0',
      );

      final database = sqlite3.open(pluginDatabaseFile(profile.path));
      try {
        expect(
          database
              .select('SELECT version FROM plugins_table')
              .single['version'],
          '1.3.0',
        );
      } finally {
        database.dispose();
      }
    });

    test(
      'cleared preferences leave a profile with nothing to warm-start from',
      () {
        createPluginTable(File(pluginDatabaseFile(profile.path)));
        installPlugin(archive: archive(), profile: profile.path, select: true);
        writePreferences(profile.path);

        clearThemePreferences(
          profile: profile.path,
          author: _themeAuthor,
          name: _themeName,
          version: _themeVersion,
        );

        final kept = _preferences(profile.path);
        expect(kept.keys, [
          'theme.$_themeAuthor.Other Theme.compact',
          'locale',
        ]);
      },
    );
  });
}
