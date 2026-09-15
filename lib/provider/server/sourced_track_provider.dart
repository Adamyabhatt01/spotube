import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

class SourcedTrackNotifier
    extends FamilyAsyncNotifier<SourcedTrack, SpotubeFullTrackObject> {
  @override
  FutureOr<SourcedTrack> build(query) {
    // Phase 2 perf (2.2): only the audio-source PLUGIN is watched here.
    // `audioSourcePresetsProvider` was previously watched too, so every
    // quality-preset tweak rebuilt all live instances and re-ran a full
    // `streams()` manifest fetch — yet `fetchFromTrack` never consumes
    // presets (the manifest is quality-agnostic; quality is picked
    // dynamically in `SourcedTrack.url` via `ref.read`). Dropping the watch
    // is behavior-preserving. See test/sourced_track_presets_test.dart.
    ref.watch(audioSourcePluginProvider);

    return SourcedTrack.fetchFromTrack(query: query, ref: ref);
  }

  Future<SourcedTrack> refreshStreamingUrl() async {
    return await update((prev) async {
      return await prev.refreshStream();
    });
  }

  Future<SourcedTrack> copyWithSibling() async {
    return await update((prev) async {
      return prev.copyWithSibling();
    });
  }

  Future<SourcedTrack> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    return await update((prev) async {
      return await prev.swapWithSibling(sibling) ?? prev;
    });
  }

  Future<SourcedTrack> swapWithNextSibling() async {
    return await update((prev) async {
      return await prev.swapWithSibling(prev.siblings.first) as SourcedTrack;
    });
  }
}

final sourcedTrackProvider = AsyncNotifierProviderFamily<SourcedTrackNotifier,
    SourcedTrack, SpotubeFullTrackObject>(
  () => SourcedTrackNotifier(),
);
