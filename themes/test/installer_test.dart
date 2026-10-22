import 'dart:io';

import 'package:spotube_themes/installer.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

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
      expect(File('${result.extractionDir.path}/plugin.json').existsSync(), isTrue);
      expect(File('${result.extractionDir.path}/plugin.out').existsSync(), isTrue);
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

    test('installing the same theme twice replaces it rather than duplicating',
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
    });

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
}
