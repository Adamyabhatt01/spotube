// Regression tests for the one-time metadata-default handover that makes the
// bundled Spotify plugin the recommendation on installs that predate it.
//
// `addPlugin` claims a default slot only while nothing else holds it, so on an
// existing install the newly bundled plugin would land as merely available and
// Musicbrainz/Listenbrainz would keep the recommendation.
// `handOverDefaultMetadata` is the correction, and its two guards are the
// contract under test: it must fire when the current default is another
// *bundled seed*, and must not fire when the default is a plugin the user
// installed themselves from the index.
//
// The real archives are parsed rather than hand-written configs, so the test
// breaks if a bundled name or author changes out from under the identity match.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/plugin_storage.dart';

import 'support/common_fakes.dart';

void main() {
  PluginConfiguration readConfig(String slug) =>
      PluginStorage.readArchiveConfig(
        ZipDecoder().decodeBytes(
          File('assets/plugins/$slug/plugin.smplug').readAsBytesSync(),
        ),
      );

  final seedConfigs = bundledPlugins.map(readConfig).toList();
  final spotify = readConfig('spotube-plugin-spotify');
  final musicbrainz = readConfig('spotube-plugin-musicbrainz-listenbrainz');

  late AppDatabase db;
  late ProviderContainer container;
  late MetadataPluginNotifier notifier;

  setUp(() {
    db = newMemoryDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
      ],
    );
    notifier = container.read(metadataPluginsProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> insert(
    PluginConfiguration config, {
    required bool metadataDefault,
  }) {
    return db.pluginsTable.insertOne(
      PluginsTableCompanion.insert(
        name: config.name,
        author: config.author,
        description: config.description,
        version: config.version,
        entryPoint: config.entryPoint,
        apis: config.apis.map((e) => e.name).toList(),
        abilities: config.abilities.map((e) => e.name).toList(),
        selectedForMetadata: Value(metadataDefault),
      ),
    );
  }

  Future<Set<String>> metadataDefaults() async {
    final rows = await (db.pluginsTable.select()
          ..where((tbl) => tbl.selectedForMetadata.equals(true)))
        .get();
    return rows.map((row) => '${row.name}|${row.author}').toSet();
  }

  /// Identity as the handover matches it: name plus author, never the slug.
  String identity(PluginConfiguration config) =>
      '${config.name}|${config.author}';

  group('handOverDefaultMetadata', () {
    test('moves the default off the previous bundled seed', () async {
      // What a pre-Spotify install looks like after the seed pass: Musicbrainz
      // holds the metadata slot, Spotify was inserted behind it and so did not
      // claim anything.
      await insert(musicbrainz, metadataDefault: true);
      await insert(spotify, metadataDefault: false);

      await notifier.handOverDefaultMetadata(
        recommended: spotify,
        seedConfigs: seedConfigs,
      );

      expect(await metadataDefaults(), {identity(spotify)});
    });

    test('leaves a default the user chose from the plugin index alone',
        () async {
      final userInstalled = PluginConfiguration(
        name: 'Some Other Metadata Source',
        author: 'Someone Else',
        description: 'Installed by hand from the plugin index',
        version: '1.0.0',
        entryPoint: 'OtherMetadataProviderPlugin',
        pluginApiVersion: '2.0.0',
        abilities: const [PluginAbilities.metadata],
      );
      await insert(userInstalled, metadataDefault: true);
      await insert(spotify, metadataDefault: false);

      await notifier.handOverDefaultMetadata(
        recommended: spotify,
        seedConfigs: seedConfigs,
      );

      expect(
        await metadataDefaults(),
        {identity(userInstalled)},
        reason: 'a deliberate choice must not be overwritten by a seed',
      );
    });

    test('is a no-op when the bundled plugin already holds the default',
        () async {
      await insert(musicbrainz, metadataDefault: false);
      await insert(spotify, metadataDefault: true);

      await notifier.handOverDefaultMetadata(
        recommended: spotify,
        seedConfigs: seedConfigs,
      );

      expect(await metadataDefaults(), {identity(spotify)});
    });

    test('does nothing when nothing was newly installed', () async {
      // The steady state: every later launch finds the seeds already present,
      // so `recommended` is null and the pass must not touch the database.
      await insert(musicbrainz, metadataDefault: true);

      await notifier.handOverDefaultMetadata(
        recommended: null,
        seedConfigs: seedConfigs,
      );

      expect(await metadataDefaults(), {identity(musicbrainz)});
    });

    test('does nothing when no row claims the metadata slot', () async {
      // There is nothing to hand over *from*. The unclaimed-default case is
      // already handled by addPlugin during the seed pass; this guard is what
      // keeps a corrupted or half-seeded table from being written blind.
      await insert(spotify, metadataDefault: false);

      await notifier.handOverDefaultMetadata(
        recommended: spotify,
        seedConfigs: seedConfigs,
      );

      expect(await metadataDefaults(), isEmpty);
    });
  });
}
