import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The engines worth asking for a stream manifest, in order.
///
/// The selected engine always comes first, so a working configuration keeps
/// its exact behaviour. The others are only reached when that one fails: a
/// YouTube bot gate is account/client-specific, and a different extractor
/// (yt-dlp in particular) can still answer for the same video.
///
/// Only manifest resolution widens here. Search and video metadata stay on
/// the engine the user selected, because a fallback answer there would hide
/// a broken backend instead of working around one blocked stream.
// The chain is memoized per selected engine: `streamManifest` runs once per
// playback start, and constructing the fallbacks each time would also give
// `NewPipeEngine` a fresh lazy-init slot every call.
YouTubeEngine? _chainPrimary;
List<YouTubeEngine>? _chainCache;

List<YouTubeEngine> manifestFallbackChain(YouTubeEngine primary) {
  final cached = _chainCache;
  if (cached != null && identical(primary, _chainPrimary)) return cached;

  final chain = <YouTubeEngine>[
    primary,
    if (primary is! YtDlpEngine && YtDlpEngine.isAvailableForPlatform)
      YtDlpEngine(),
    if (primary is! NewPipeEngine && NewPipeEngine.isAvailableForPlatform)
      NewPipeEngine(),
  ];
  _chainPrimary = primary;
  _chainCache = chain;
  return chain;
}

/// Resolves [videoId]'s manifest from the first engine in [chain] that
/// returns at least one audio stream.
///
/// An engine that throws or answers an empty manifest is skipped. When every
/// engine fails, the first error is rethrown with its original stack so the
/// caller still reports the selected engine's reason (the bot gate is the
/// useful diagnosis, not "every fallback was also empty").
Future<StreamManifest> streamManifestWithFallback({
  required String videoId,
  required List<YouTubeEngine> chain,
}) async {
  Object? firstError;
  StackTrace? firstStack;
  StreamManifest? firstEmpty;

  for (final engine in chain) {
    try {
      final manifest = await engine.getStreamManifest(videoId);
      if (manifest.audioOnly.isNotEmpty) {
        if (!identical(engine, chain.first)) {
          AppLogger.logEvent(
            '[youtube] manifest fallback: ${engine.runtimeType} served $videoId',
          );
        }
        return manifest;
      }
      firstEmpty ??= manifest;
      AppLogger.logEvent(
        '[youtube] ${engine.runtimeType} returned no audio for $videoId',
      );
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
      AppLogger.logEvent(
        '[youtube] ${engine.runtimeType} manifest failed for $videoId: $error',
      );
    }
  }

  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStack!);
  }
  // Every engine answered, none had audio. Return the first (empty) manifest
  // instead of inventing an error: the plugin reports the missing streams.
  return firstEmpty ?? StreamManifest(const <AudioOnlyStreamInfo>[]);
}
