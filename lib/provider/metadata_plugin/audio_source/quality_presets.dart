import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/source_dependencies.dart';

part 'quality_presets.g.dart';
part 'quality_presets.freezed.dart';

/// Clamps a persisted preset index into the range the current preset list
/// actually offers.
///
/// The persisted index was chosen against the plugin's list at the time it
/// was written. A plugin update — or a different plugin under the same
/// slug — can present a shorter list, leaving the index past the end.
/// Direct indexing then throws a RangeError in the playback, download and
/// settings paths, so the index is clamped to the list that is here now.
///
/// An empty list clamps to 0: the index is meaningless there, and every
/// consumer already treats "no preset" as "nothing to serve" rather than
/// an error.
int clampPresetIndex(int index, int length) {
  if (length <= 0) return 0;
  if (index < 0) return 0;
  if (index >= length) return length - 1;
  return index;
}

@freezed
class AudioSourcePresetsState
    with _$AudioSourcePresetsState
    implements AudioSourcePresetSelection {
  factory AudioSourcePresetsState({
    @Default([]) final List<SpotubeAudioSourceContainerPreset> presets,
    @Default(0) final int selectedStreamingQualityIndex,
    @Default(0) final int selectedStreamingContainerIndex,
    @Default(0) final int selectedDownloadingQualityIndex,
    @Default(0) final int selectedDownloadingContainerIndex,
  }) = _AudioSourcePresetsState;

  factory AudioSourcePresetsState.fromJson(Map<String, dynamic> json) =>
      _$AudioSourcePresetsStateFromJson(json);
}

class AudioSourceAvailableQualityPresetsNotifier
    extends Notifier<AudioSourcePresetsState> {
  AudioPlayerPort get _player => ref.read(audioPlayerPortProvider);

  @override
  build() {
    final audioSourceSnapshot = ref.watch(audioSourcePluginProvider);
    final audioSourceConfigSnapshot = ref.watch(
      metadataPluginsProvider.select((data) =>
          data.whenData((value) => value.defaultAudioSourcePluginConfig)),
    );

    _initialize(audioSourceSnapshot, audioSourceConfigSnapshot);

    listenSelf((previous, next) {
      final isNewLossless =
          next.presets.elementAtOrNull(next.selectedStreamingContainerIndex)
              is SpotubeAudioSourceContainerPresetLossless;
      final isOldLossless = previous?.presets
              .elementAtOrNull(previous.selectedStreamingContainerIndex)
          is SpotubeAudioSourceContainerPresetLossless;
      if (!isOldLossless && isNewLossless) {
        _player.setDemuxerBufferSize(6 * 1024 * 1024); // 6MB
      } else if (isOldLossless && !isNewLossless) {
        _player.setDemuxerBufferSize(4 * 1024 * 1024); // 4MB
      }
    });

    return AudioSourcePresetsState();
  }

  void _initialize(
    AsyncValue<MetadataPlugin?> audioSourceSnapshot,
    AsyncValue<PluginConfiguration?> audioSourceConfigSnapshot,
  ) {
    audioSourceConfigSnapshot.whenData((audioSourceConfig) {
      audioSourceSnapshot.whenData((audioSource) {
        _restorePersistedState(audioSource, audioSourceConfig);
      });
    });
  }

  /// Restores the persisted presets for the resolved audio source. Errors are
  /// reported, never thrown: [whenData] discards an async callback's future,
  /// so a throw here surfaced as an unhandled async error instead of an
  /// `AsyncError` on this provider.
  Future<void> _restorePersistedState(
    MetadataPlugin? audioSource,
    PluginConfiguration? audioSourceConfig,
  ) async {
    if (audioSource == null || audioSourceConfig == null) {
      AppLogger.reportError(
        MetadataPluginException.noDefaultAudioSourcePlugin(),
        StackTrace.current,
        "AudioSourcePresets: no default audio source plugin",
      );
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final persistedStateStr =
          preferences.getString("audioSourceState-${audioSourceConfig.slug}");

      final presets = audioSource.audioSource.supportedPresets;

      if (persistedStateStr != null) {
        final restored = AudioSourcePresetsState.fromJson(
          jsonDecode(persistedStateStr),
        );
        state = restored.copyWith(
          presets: presets,
          // The persisted indices were chosen against the plugin's list at
          // the time. A plugin update (or a different plugin under the same
          // slug) can present a shorter list, leaving the index past the
          // end — direct indexing then throws a RangeError in the playback
          // and download paths. Clamp to the list that is actually here.
          selectedStreamingContainerIndex: clampPresetIndex(
            restored.selectedStreamingContainerIndex,
            presets.length,
          ),
          selectedDownloadingContainerIndex: clampPresetIndex(
            restored.selectedDownloadingContainerIndex,
            presets.length,
          ),
        );
      } else {
        state = AudioSourcePresetsState(
          presets: presets,
        );
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack, "AudioSourcePresets: restore");
    }
  }

  void setSelectedStreamingContainerIndex(int index) {
    state = state.copyWith(
      selectedStreamingContainerIndex: index,
      selectedStreamingQualityIndex:
          0, // Resetting both because it's a different quality
    );
    _updatePreferences();
  }

  void setSelectedStreamingQualityIndex(int index) {
    state = state.copyWith(selectedStreamingQualityIndex: index);
    _updatePreferences();
  }

  void setSelectedDownloadingContainerIndex(int index) {
    state = state.copyWith(
      selectedDownloadingContainerIndex: index,
      selectedDownloadingQualityIndex:
          0, // Resetting both because it's a different quality
    );
    _updatePreferences();
  }

  void setSelectedDownloadingQualityIndex(int index) {
    state = state.copyWith(selectedDownloadingQualityIndex: index);
    _updatePreferences();
  }

  void _updatePreferences() async {
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSourceConfig == null) {
      // Same discarded-error shape as [_restorePersistedState]: this is an
      // async void, so a throw here never reaches a caller.
      AppLogger.reportError(
        MetadataPluginException.noDefaultAudioSourcePlugin(),
        StackTrace.current,
        "AudioSourcePresets: no default audio source plugin",
      );
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      "audioSourceState-${audioSourceConfig.slug}",
      jsonEncode(state),
    );
  }
}

final audioSourcePresetsProvider = NotifierProvider<
    AudioSourceAvailableQualityPresetsNotifier, AudioSourcePresetsState>(
  () => AudioSourceAvailableQualityPresetsNotifier(),
);
