import 'package:collection/collection.dart';
import 'package:path/path.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/utils/service_utils.dart';

/// Wave size for batched filesystem existence checks, shared by startup
/// reconciliation and bulk-download prefiltering so neither opens every handle
/// at once.
const int downloadExistenceWaveSize = 32;

/// Destination of [track]'s file for the given settings.
///
/// Shared by the phase-1 prefilter and the transfer worker so the checked path
/// and the downloaded path can never drift apart.
String downloadSavePath(
  SpotubeFullTrackObject track,
  String downloadLocation,
  SpotubeAudioSourceContainerPreset container, {
  bool useRetryFilePath = false,
}) {
  final stem = ServiceUtils.trackFileStem(track, spaceAfterComma: true);
  // A retry must not reuse or overwrite the failed attempt's file: it may be
  // truncated, or may belong to a distinct track whose name sanitized to the
  // same path. The track id makes the retry destination deterministic and
  // unique without deleting anything.
  final fileName = useRetryFilePath
      ? "$stem [${track.id}].${container.getFileExtension()}"
      : "$stem.${container.getFileExtension()}";
  return join(
    downloadLocation,
    ServiceUtils.sanitizeFilename(fileName),
  );
}

/// The selected download container, or null while the plugin's presets are
/// still loading or the persisted index points past the end of the list.
SpotubeAudioSourceContainerPreset? selectedDownloadContainer(
  AudioSourcePresetsState presets,
) =>
    presets.presets.elementAtOrNull(presets.selectedDownloadingContainerIndex);

/// Selects the download URL for [track]. When [autoQuality] is enabled, the
/// selected container/quality is not required — the best available stream
/// (any container) is used instead.
String? pickDownloadUrl(
  SourcedTrack track,
  SpotubeAudioSourceContainerPreset container,
  AudioSourcePresetsState presets,
  bool autoQuality,
) {
  if (autoQuality) {
    return track.getStreamOfAnyContainer(container)?.url;
  }
  return track.getUrlOfQuality(
    container,
    presets.selectedDownloadingQualityIndex,
  );
}

DownloadPersistedStatus persistedStatusFor(DownloadStatus status) {
  return switch (status) {
    DownloadStatus.queued => DownloadPersistedStatus.queued,
    DownloadStatus.downloading => DownloadPersistedStatus.downloading,
    DownloadStatus.completed => DownloadPersistedStatus.completed,
    DownloadStatus.failed => DownloadPersistedStatus.failed,
    DownloadStatus.canceled => DownloadPersistedStatus.canceled,
  };
}

String truncateDownloadError(String value, int maxLength) =>
    value.length <= maxLength ? value : value.substring(0, maxLength);
