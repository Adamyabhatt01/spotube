// Lifecycle of a theme plugin uninstall from the host side.
//
// The CLI mirror is covered in `themes/test/installer_test.dart`; this pins
// the app's own removal path: the version directory, the `plugins_table` row,
// the theme's KV namespace and the warm-start cache all go with it, and the
// theme UI falls back to the built-in one when the active theme disappears.
// Removing a non-active theme must leave the active identity, its settings and
// its screens alone.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_screen_stack.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/plugin_storage.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/theme_definition_cache.dart';

import 'support/common_fakes.dart';

const _cacheKey = 'spotube.theme_definition_cache.v3';

PluginConfiguration _config(String name, {String version = '1.0.0'}) =>
    PluginConfiguration(
      name: name,
      description: '$name theme',
      version: version,
      author: 'tester',
      entryPoint: 'Theme',
      pluginApiVersion: '2.0.0',
      abilities: const [PluginAbilities.theme],
    );

/// A notifier whose state is fixed at construction: removal reads the state to
/// decide whether the plugin owned the active theme, and the database watcher
/// is irrelevant to that decision.
class _FixedThemeNotifier extends MetadataPluginNotifier {
  _FixedThemeNotifier(this.initialState);

  final MetadataPluginState initialState;

  @override
  Future<MetadataPluginState> build() async => initialState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('spotube-theme-uninstall');
    PathProviderPlatform.instance = FakePathProvider(support.path);
    SharedPreferences.setMockInitialValues({});
    await KVStoreService.initialize();
    db = newMemoryDatabase();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await support.delete(recursive: true);
  });

  Future<void> insert(
    PluginConfiguration config, {
    required bool selected,
  }) async {
    await db.pluginsTable.insertOne(
      PluginsTableCompanion.insert(
        name: config.name,
        author: config.author,
        description: config.description,
        version: config.version,
        entryPoint: config.entryPoint,
        apis: config.apis.map((api) => api.name).toList(),
        abilities: config.abilities.map((ability) => ability.name).toList(),
        selectedForTheme: Value(selected),
      ),
    );
  }

  Future<void> writeFiles(PluginConfiguration config) async {
    final directory = await PluginStorage().extractionDir(config);
    await directory.create(recursive: true);
    await File('${directory.path}/plugin.json')
        .writeAsString(jsonEncode(config.toJson()));
    await File('${directory.path}/plugin.out').writeAsString('bytecode');
  }

  Future<void> start({
    required List<PluginConfiguration> plugins,
    required int defaultTheme,
  }) async {
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metadataPluginsProvider.overrideWith(
          () => _FixedThemeNotifier(
            MetadataPluginState(
              plugins: plugins,
              defaultThemePlugin: defaultTheme,
            ),
          ),
        ),
      ],
    );
    await container.read(metadataPluginsProvider.future);
  }

  test(
    'removing the active theme deletes its files, row, settings and cache '
    'and falls back to the built-in UI',
    () async {
      final active = _config('Active Theme');
      final inactive = _config('Inactive Theme');
      await insert(active, selected: true);
      await insert(inactive, selected: false);
      await writeFiles(active);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'spotube.theme_default_plugin_key.v1',
        themePluginKey(active),
      );
      await prefs.setString(
        _cacheKey,
        jsonEncode({'v': 3, 'pluginKey': themePluginKey(active)}),
      );
      await prefs.setBool(
          'theme.${active.author}.${active.name}.compact', true);
      await prefs.setBool(
        'theme.${inactive.author}.${inactive.name}.compact',
        true,
      );
      await prefs.setString('locale', 'en');

      await start(plugins: [active, inactive], defaultTheme: 0);

      final directory = await PluginStorage().extractionDir(active);
      container.read(themeUiOverrideProvider.notifier).state =
          const ThemeUiDocument();
      container.read(themeUiScreenStackProvider.notifier).state = const [
        'now-playing',
      ];

      await container
          .read(metadataPluginsProvider.notifier)
          .removePlugin(active);

      expect(await directory.exists(), isFalse);
      final rows = await db.pluginsTable.select().get();
      expect(rows.map((row) => row.name), [inactive.name]);
      expect(
        rows.single.selectedForTheme,
        isFalse,
        reason: 'removing the active theme must not promote another one',
      );

      expect(
        prefs.getBool('theme.${active.author}.${active.name}.compact'),
        isNull,
      );
      expect(
        prefs.getBool('theme.${inactive.author}.${inactive.name}.compact'),
        isTrue,
        reason: "another theme's namespace must survive",
      );
      expect(prefs.getString('spotube.theme_default_plugin_key.v1'), isNull);
      expect(
        prefs.getString(_cacheKey),
        isNull,
        reason: 'nothing may warm-start from a removed theme',
      );
      expect(prefs.getString('locale'), 'en');

      expect(container.read(themeUiOverrideProvider), isNull);
      expect(container.read(themeUiScreenStackProvider), isEmpty);
    },
  );

  test('a row whose version fails the path guard is still removable', () async {
    // An install from before the extraction-directory guard, or a hand-edited
    // database, must not leave the user with a plugin they cannot delete.
    final unsafe = _config('Unsafe Theme', version: '../escape');
    await insert(unsafe, selected: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'spotube.theme_default_plugin_key.v1',
      themePluginKey(unsafe),
    );
    await prefs.setBool('theme.${unsafe.author}.${unsafe.name}.compact', true);

    await start(plugins: [unsafe], defaultTheme: 0);

    await container.read(metadataPluginsProvider.notifier).removePlugin(unsafe);

    expect(await db.pluginsTable.select().get(), isEmpty);
    expect(
      prefs.getBool('theme.${unsafe.author}.${unsafe.name}.compact'),
      isNull,
    );
    expect(prefs.getString('spotube.theme_default_plugin_key.v1'), isNull);
  });

  test(
    'removing a non-active theme leaves the active identity, UI and settings '
    'alone',
    () async {
      final active = _config('Active Theme');
      final inactive = _config('Inactive Theme');
      await insert(active, selected: true);
      await insert(inactive, selected: false);
      await writeFiles(active);
      await writeFiles(inactive);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'spotube.theme_default_plugin_key.v1',
        themePluginKey(active),
      );
      await prefs.setBool(
          'theme.${active.author}.${active.name}.compact', true);
      await prefs.setBool(
        'theme.${inactive.author}.${inactive.name}.compact',
        true,
      );

      await start(plugins: [active, inactive], defaultTheme: 0);

      const control = ThemeUiDocument(capabilities: ['ui.hostWidgets']);
      container.read(themeUiOverrideProvider.notifier).state = control;
      container.read(themeUiScreenStackProvider.notifier).state = const [
        'library',
      ];

      final removedDirectory = await PluginStorage().extractionDir(inactive);
      await container
          .read(metadataPluginsProvider.notifier)
          .removePlugin(inactive);

      expect(await removedDirectory.exists(), isFalse);
      final rows = await db.pluginsTable.select().get();
      expect(rows.map((row) => row.name), [active.name]);

      expect(
        prefs.getBool('theme.${inactive.author}.${inactive.name}.compact'),
        isNull,
      );
      expect(
        prefs.getBool('theme.${active.author}.${active.name}.compact'),
        isTrue,
      );
      expect(
        prefs.getString('spotube.theme_default_plugin_key.v1'),
        themePluginKey(active),
      );

      expect(
        container.read(themeUiOverrideProvider),
        same(control),
        reason: 'the active theme still owns its overrides',
      );
      expect(container.read(themeUiScreenStackProvider), ['library']);
    },
  );
}
