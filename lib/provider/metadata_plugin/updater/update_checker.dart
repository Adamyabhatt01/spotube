import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// Minimum gap between update-check runs: app release + both plugin checks.
///
/// Previously every launch fired all three with no memory of the last run
/// (the only gate was the boolean opt-out) — the way updaters like Sparkle
/// avoid it is a last-checked timestamp, so a daily driver pays one burst a
/// day instead of one per launch.
const updateCheckInterval = Duration(hours: 24);

/// Whether [updateCheckInterval] has elapsed since [lastCheckMs] (epoch ms,
/// 0 when never checked). Pure for testing; clock skew into the future reads
/// as due rather than suppressing checks forever.
bool isUpdateCheckDue(int lastCheckMs, DateTime now) {
  if (lastCheckMs <= 0) return true;
  final elapsed = now.millisecondsSinceEpoch - lastCheckMs;
  if (elapsed < 0) return true;
  return Duration(milliseconds: elapsed) >= updateCheckInterval;
}

final metadataPluginUpdateCheckerProvider =
    FutureProvider<PluginUpdateAvailable?>((ref) async {
  final metadataPluginConfigs = await ref.watch(metadataPluginsProvider.future);
  final metadataPlugin = await ref.watch(metadataPluginProvider.future);

  if (metadataPlugin == null ||
      metadataPluginConfigs.defaultMetadataPluginConfig == null) {
    return null;
  }

  return metadataPlugin.core
      .checkUpdate(metadataPluginConfigs.defaultMetadataPluginConfig!);
});

final audioSourcePluginUpdateCheckerProvider =
    FutureProvider<PluginUpdateAvailable?>((ref) async {
  final audioSourcePluginConfigs =
      await ref.watch(metadataPluginsProvider.future);
  final audioSourcePlugin = await ref.watch(audioSourcePluginProvider.future);

  if (audioSourcePlugin == null ||
      audioSourcePluginConfigs.defaultAudioSourcePluginConfig == null) {
    return null;
  }

  return audioSourcePlugin.core
      .checkUpdate(audioSourcePluginConfigs.defaultAudioSourcePluginConfig!);
});
