import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_script/values.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';

class MetadataPluginAudioSourceEndpoint {
  final Hetu hetu;
  MetadataPluginAudioSourceEndpoint(this.hetu);

  HTInstance get hetuMetadataAudioSource =>
      (hetu.fetch("metadataPlugin") as HTInstance).memberGet("audioSource")
          as HTInstance;

  /// The container presets the audio-source plugin publishes.
  ///
  /// Defensive on purpose: the plugin's `supportedPresets` member is read
  /// through an untyped `memberGet`, and a plugin that omits it, exposes a
  /// non-list, or returns a preset shape this host cannot parse would
  /// otherwise throw out of the getter. An empty list is the honest answer
  /// in that case: there is no container to serve, and the playback routes
  /// fall back to the container of the resolved stream.
  List<SpotubeAudioSourceContainerPreset> get supportedPresets {
    final Object? raw;
    try {
      raw = hetuMetadataAudioSource.memberGet("supportedPresets");
    } catch (e, stack) {
      AppLogger.reportError(e, stack, "AudioSource: reading supportedPresets");
      return const [];
    }

    if (raw is! List) {
      AppLogger.reportError(
        StateError("supportedPresets is ${raw.runtimeType}, not a List"),
        StackTrace.current,
        "AudioSource: reading supportedPresets",
      );
      return const [];
    }

    final presets = <SpotubeAudioSourceContainerPreset>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        presets.add(
          SpotubeAudioSourceContainerPreset.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        );
      } catch (e, stack) {
        // One unparseable preset must not hide the rest of them.
        AppLogger.reportError(e, stack, "AudioSource: parsing a preset");
      }
    }
    return presets;
  }

  Future<List<SpotubeAudioSourceMatchObject>> matches(
    SpotubeFullTrackObject track,
  ) async {
    final raw = await hetuMetadataAudioSource
        .invoke("matches", positionalArgs: [track.toJson()]) as List;

    return raw.map((e) => SpotubeAudioSourceMatchObject.fromJson(e)).toList();
  }

  Future<List<SpotubeAudioSourceStreamObject>> streams(
    SpotubeAudioSourceMatchObject match,
  ) async {
    final raw = await hetuMetadataAudioSource
        .invoke("streams", positionalArgs: [match.toJson()]) as List;

    return raw.map((e) => SpotubeAudioSourceStreamObject.fromJson(e)).toList();
  }
}
