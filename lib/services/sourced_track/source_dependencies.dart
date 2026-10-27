import 'dart:typed_data';

import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/metadata.dart';

/// The installed audio-source plugins, plus which one is the default.
class SourcePluginSnapshot {
  const SourcePluginSnapshot({
    required this.plugins,
    required this.defaultAudioSourcePluginConfig,
  });

  final List<PluginConfiguration> plugins;
  final PluginConfiguration? defaultAudioSourcePluginConfig;
}

/// The per-(plugin, engine) cache of live plugin instances.
abstract interface class MetadataPluginCache {
  Future<MetadataPlugin> getOrCreate(
    String key,
    Future<MetadataPlugin> Function() factory,
  );
}

/// The audio-source preset selection, as it stands when a track is served.
abstract interface class AudioSourcePresetSelection {
  List<SpotubeAudioSourceContainerPreset> get presets;
  int get selectedStreamingContainerIndex;
  int get selectedStreamingQualityIndex;
}

/// Everything source resolution needs from the application layer.
///
/// This is the services-side port for the Riverpod providers that used to be
/// read through a `Ref`. Keeping it an interface is what lets
/// `services/sourced_track` stay free of provider imports; the provider-side
/// adapter lives in `provider/sourced_track/source_dependencies.dart`.
///
/// Values are synchronous getters where the current provider value is enough,
/// and futures where the provider has to finish loading first.
abstract interface class SourceDependencies {
  /// Installed plugins and the default audio-source plugin, loaded.
  Future<SourcePluginSnapshot> pluginSnapshot();

  /// The live default audio-source plugin, or null when none is configured.
  Future<MetadataPlugin?> defaultAudioSourcePlugin();

  /// Compiled bytecode for [config], used to build non-default candidates.
  Future<Uint8List> pluginByteCode(PluginConfiguration config);

  /// Cache of plugin instances keyed by [SourceCandidate.key].
  MetadataPluginCache get pluginCache;

  /// User-configured plugin/engine priority; empty means "no preference".
  List<String> get sourcePriority;

  /// The engine the user selected.
  YoutubeClientEngine get youtubeClientEngine;

  /// Source-match cache storage.
  AppDatabase get database;

  /// Current preset selection, read per serve so quality changes apply
  /// without re-resolving.
  AudioSourcePresetSelection get presets;
}
