// Regression tests for plugin update identity and registration.
//
// The bundled update path used to compare pluginApiVersion only, so a normal
// release that bumped `version` but kept the API version was extracted and
// then silently ignored. Updates also used to remove the old row before
// inserting the new one; a failure in between left the plugin undiscoverable.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

PluginConfiguration _config({
  String name = 'update-plugin',
  String version = '1.0.0',
  String description = 'old',
  String pluginApiVersion = '2.0.0',
  List<PluginApis> apis = const [PluginApis.webview],
  List<PluginAbilities> abilities = const [
    PluginAbilities.metadata,
    PluginAbilities.radio,
  ],
  String? repository = 'https://example.invalid/old',
}) {
  return PluginConfiguration(
    name: name,
    description: description,
    version: version,
    author: 'tester',
    entryPoint: 'plugin.out',
    pluginApiVersion: pluginApiVersion,
    apis: apis,
    abilities: abilities,
    repository: repository,
  );
}

/// `isPluginUpdate` needs a database and nothing else from the notifier.
class _TestPluginNotifier extends MetadataPluginNotifier {
  _TestPluginNotifier(this._db);

  final AppDatabase _db;

  @override
  AppDatabase get database => _db;
}

void main() {
  group('shouldUpdatePlugin', () {
    test('a version bump is an update even when the API is unchanged', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: '1.0.0',
          oldPluginApiVersion: '2.0.0',
          newVersion: '1.0.1',
          newPluginApiVersion: '2.0.0',
        ),
        isTrue,
      );
    });

    test('an API bump at the same version is still an update', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: '1.0.0',
          oldPluginApiVersion: '2.0.0',
          newVersion: '1.0.0',
          newPluginApiVersion: '2.1.0',
        ),
        isTrue,
      );
    });

    test('a downgrade is not an update', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: '1.0.1',
          oldPluginApiVersion: '2.0.0',
          newVersion: '1.0.0',
          newPluginApiVersion: '2.0.0',
        ),
        isFalse,
      );
    });

    test('an identical plugin is not an update', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: '1.0.0',
          oldPluginApiVersion: '2.0.0',
          newVersion: '1.0.0',
          newPluginApiVersion: '2.0.0',
        ),
        isFalse,
      );
    });

    test('a non-semver version change is treated as an update', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: 'build-a',
          oldPluginApiVersion: '2.0.0',
          newVersion: 'build-b',
          newPluginApiVersion: '2.0.0',
        ),
        isTrue,
      );
    });

    test('a build-metadata-only version change is an update', () {
      expect(
        MetadataPluginNotifier.shouldUpdatePlugin(
          oldVersion: '1.0.0',
          oldPluginApiVersion: '2.0.0',
          newVersion: '1.0.0+1',
          newPluginApiVersion: '2.0.0',
        ),
        isTrue,
      );
    });
  });

  group('replacePluginRow', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<PluginsTableData> insertOld() async {
      await db.pluginsTable.insertOne(
        PluginsTableCompanion.insert(
          name: 'update-plugin',
          description: 'old',
          version: '1.0.0',
          author: 'tester',
          entryPoint: 'plugin.out',
          apis: const ['webview'],
          abilities: const ['metadata', 'radio'],
          selectedForMetadata: const Value(true),
          selectedForAudioSource: const Value(true),
          selectedForTheme: const Value(true),
          selectedForRadio: const Value(true),
          repository: const Value('https://example.invalid/old'),
          pluginApiVersion: const Value('2.0.0'),
        ),
      );
      return (await db.pluginsTable.select().get()).single;
    }

    test('updates in place and preserves id and selection flags', () async {
      final before = await insertOld();
      final updated = _config(
        version: '1.0.1',
        description: 'new',
        pluginApiVersion: '2.0.0',
        apis: const [],
        abilities: const [PluginAbilities.metadata],
        repository: null,
      );

      final oldRow = await MetadataPluginNotifier.replacePluginRow(
        database: db,
        plugin: updated,
      );

      expect(oldRow, isNotNull);
      expect(oldRow!.version, '1.0.0');

      final after = (await db.pluginsTable.select().get()).single;
      expect(after.id, before.id, reason: 'the row is updated, not replaced');
      expect(after.version, '1.0.1');
      expect(after.description, 'new');
      expect(after.apis, isEmpty);
      expect(after.abilities, ['metadata']);
      expect(after.repository, isNull);
      expect(after.selectedForMetadata, isTrue);
      expect(after.selectedForAudioSource, isTrue);
      expect(after.selectedForTheme, isTrue);
      expect(after.selectedForRadio, isTrue);
    });

    test('isPluginUpdate treats a version-only bump as an update', () async {
      await insertOld();
      final notifier = _TestPluginNotifier(db);

      expect(
        await notifier.isPluginUpdate(_config(version: '1.0.1')),
        isTrue,
        reason: 'bundled releases bump version without the plugin API',
      );
      expect(
        await notifier.isPluginUpdate(_config(version: '1.0.0')),
        isFalse,
      );
      expect(
        await notifier.isPluginUpdate(_config(version: '0.9.0')),
        isFalse,
      );
    });

    test('a missing identity returns null and inserts nothing', () async {
      final result = await MetadataPluginNotifier.replacePluginRow(
        database: db,
        plugin: _config(name: 'not-installed'),
      );

      expect(result, isNull);
      expect(await db.pluginsTable.select().get(), isEmpty);
    });
  });
}
