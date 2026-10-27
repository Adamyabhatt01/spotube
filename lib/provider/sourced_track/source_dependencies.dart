import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/manifest_cache.dart';
import 'package:spotube/services/sourced_track/source_dependencies.dart';

/// Adapts the Riverpod providers to the [SourceDependencies] port.
///
/// This is the only place `services/sourced_track` meets the provider graph;
/// keeping the adapter here lets the resolution core stay provider-free (see
/// `test/architecture_boundaries_test.dart`).
class RefSourceDependencies implements SourceDependencies {
  RefSourceDependencies(this._ref);

  final Ref _ref;

  @override
  late final MetadataPluginCache pluginCache =
      _PluginVmCacheAdapter(_ref.read(pluginCacheProvider));

  @override
  ManifestCache get manifestCache => _ref.read(manifestCacheProvider);

  @override
  Future<SourcePluginSnapshot> pluginSnapshot() async {
    final state = await _ref.read(metadataPluginsProvider.future);
    return SourcePluginSnapshot(
      plugins: state.plugins,
      defaultAudioSourcePluginConfig: state.defaultAudioSourcePluginConfig,
    );
  }

  @override
  Future<MetadataPlugin?> defaultAudioSourcePlugin() =>
      _ref.read(audioSourcePluginProvider.future);

  @override
  Future<Uint8List> pluginByteCode(PluginConfiguration config) =>
      _ref.read(metadataPluginsProvider.notifier).getPluginByteCode(config);

  @override
  List<String> get sourcePriority =>
      _ref.read(userPreferencesProvider.select((s) => s.sourcePriority));

  @override
  YoutubeClientEngine get youtubeClientEngine => _ref.read(
        userPreferencesProvider.select((s) => s.youtubeClientEngine),
      );

  @override
  Dio get dio => _ref.read(appDioProvider);

  @override
  AppDatabase get database => _ref.read(databaseProvider);

  @override
  AudioSourcePresetSelection get presets =>
      _ref.read(audioSourcePresetsProvider);
}

class _PluginVmCacheAdapter implements MetadataPluginCache {
  _PluginVmCacheAdapter(this._cache);

  final PluginVmCache<MetadataPlugin> _cache;

  @override
  Future<MetadataPlugin> getOrCreate(
    String key,
    Future<MetadataPlugin> Function() factory,
  ) =>
      _cache.getOrCreate(key, factory);
}

/// The extracted-manifest cache shared by every resolution in this container.
///
/// A provider (rather than a process-wide singleton) so the cache's lifetime
/// is the container's: tests get a fresh, empty cache per case, and the
/// bounded entries cannot outlive the app graph they belong to.
final manifestCacheProvider = Provider<ManifestCache>((ref) => ManifestCache());

/// The application-layer implementation of the source-resolution port.
final sourceDependenciesProvider = Provider<SourceDependencies>(
  (ref) => RefSourceDependencies(ref),
);

/// Convenience for call sites that already hold a [Ref].
extension RefSourceDependenciesX on Ref {
  SourceDependencies get sourceDeps => read(sourceDependenciesProvider);
}
