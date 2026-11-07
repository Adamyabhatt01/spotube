// Regression tests for the plugin VM-cache lifecycle (audit C2/H6):
//  - a failed creation must not permanently poison the cache
//  - cache identity includes the plugin version so an update recompiles
//  - evictPlugin drops every entry for a slug (add/remove/update wiring)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';

PluginConfiguration config(String version) => PluginConfiguration(
      name: 'Test Plugin',
      description: 'd',
      version: version,
      author: 'tester',
      entryPoint: 'plugin.out',
      pluginApiVersion: '2.0.0',
);

void main() {
  group('PluginVmCache', () {
    test('failed creation is evicted and the next attempt can succeed',
        () async {
      final cache = PluginVmCache<String>();
      var attempt = 0;

      Future<String> factory() async {
        attempt++;
        if (attempt == 1) throw Exception('transient I/O error');
        return 'vm-2';
      }

      await expectLater(
        cache.getOrCreate('p@1:EngineA', factory),
        throwsA(isA<Exception>()),
      );
      expect(cache.length, 0, reason: 'poisoned future must not linger');

      final second = await cache.getOrCreate('p@1:EngineA', factory);
      expect(second, 'vm-2');
      expect(cache.length, 1);
    });

    test('concurrent attempts share one in-flight creation future', () async {
      final cache = PluginVmCache<String>();
      var created = 0;
      final gate = Completer<void>();

      final a = cache.getOrCreate('k', () async {
        created++;
        await gate.future;
        return 'vm';
      });
      final b = cache.getOrCreate('k', () async {
        created++;
        return 'other-vm';
      });
      gate.complete();

      expect(await a, 'vm');
      expect(await b, 'vm');
      expect(created, 1, reason: 'second caller must reuse the in-flight VM');
    });

    test('evictPlugin removes all engines and versions of the slug', () {
      final cache = PluginVmCache<String>();
      cache.getOrCreate('alpha@1.0.0:EngineA', () async => 'x');
      cache.getOrCreate('alpha@2.0.0:EngineB', () async => 'y');
      cache.getOrCreate('beta@1.0.0:EngineA', () async => 'z');

      cache.evictPlugin('alpha');

      expect(cache.length, 1);
    });

    test('a plugin update (new version) resolves to a NEW cache entry',
        () async {
      final cache = PluginVmCache<String>();
      final oldKey = SourceCandidate(config('1.0.0'), NewPipeEngine()).key;
      final newKey = SourceCandidate(config('2.0.0'), NewPipeEngine()).key;

      expect(oldKey, isNot(newKey),
          reason: 'version must be part of cache identity');

      await cache.getOrCreate(oldKey, () async => 'old-vm');
      final afterUpdate =
          await cache.getOrCreate(newKey, () async => 'new-vm');

      expect(afterUpdate, 'new-vm',
          reason: 'next resolution executes the new plugin code');
    });

    test('pluginCacheProvider exposes one shared cache', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        identical(
          container.read(pluginCacheProvider),
          container.read(pluginCacheProvider),
        ),
        isTrue,
      );
    });
  });
}
