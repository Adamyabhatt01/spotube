import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/playback/track_sources.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

import 'package:spotube/services/sourced_track/exceptions.dart';
import 'package:spotube/services/sourced_track/validation.dart';
import 'package:spotube/utils/service_utils.dart';

final officialMusicRegex = RegExp(
  r"official\s(video|audio|music\svideo|lyric\svideo|visualizer)",
  caseSensitive: false,
);

/// How long a cached source-match stays authoritative.
///
/// This TTL bounds only the cached match *identity* (which video belongs
/// to a track). Stream URLs carry their own `expire` stamp and are
/// refreshed reactively; manifests are re-resolved from the match on
/// every hit. In-memory playback is therefore never invalidated by this
/// TTL — at worst a track re-searches its match after 6h.
const kSourceMatchCacheTtl = Duration(hours: 6);

/// Verdict for a cached source_match row, pure for testability.
enum SourceMatchCacheDecision {
  /// Fresh, deserializable row: use without searching.
  hit,

  /// Stale row (or stale tombstone): delete and re-search.
  refresh,

  /// Fresh but undeserializable row: a previous search found nothing, so
  /// fail without spending another search (negative cache).
  negativeHit,
}

SourceMatchCacheDecision classifyCachedSourceMatch({
  required String sourceInfo,
  required DateTime createdAt,
  DateTime? now,
  Duration ttl = kSourceMatchCacheTtl,
}) {
  final expired = (now ?? DateTime.now()).difference(createdAt) > ttl;
  var readable = false;
  try {
    final decoded = jsonDecode(sourceInfo);
    if (decoded is Map<String, dynamic>) {
      SpotubeAudioSourceMatchObject.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      readable = true;
    }
  } catch (_) {
    readable = false;
  }
  if (readable) return expired ? SourceMatchCacheDecision.refresh : SourceMatchCacheDecision.hit;
  return expired ? SourceMatchCacheDecision.refresh : SourceMatchCacheDecision.negativeHit;
}

class SourcedTrack extends BasicSourcedTrack {
  final Ref ref;

  SourcedTrack({
    required this.ref,
    required super.info,
    required super.query,
    required super.source,
    required super.siblings,
    required super.sources,
    super.sourceCandidateKey,
  });

static Future<SourcedTrack> fetchFromTrack({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    final youtubeEngine = ref.read(userPreferencesProvider.select((s) => s.youtubeClientEngine));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final database = ref.read(databaseProvider);
    var cachedSource = await (database.select(database.sourceMatchTable)
          ..where((s) =>
              s.trackId.equals(query.id) &
              s.sourceType.equals(audioSourceConfig.slug))
          ..limit(1)
          ..orderBy([
            (s) =>
                OrderingTerm(expression: s.createdAt, mode: OrderingMode.desc),
          ]))
        .get()
        .then((s) => s.firstOrNull);

    if (cachedSource != null) {
      switch (classifyCachedSourceMatch(
        sourceInfo: cachedSource.sourceInfo,
        createdAt: cachedSource.createdAt,
      )) {
        case SourceMatchCacheDecision.hit:
          break;
        case SourceMatchCacheDecision.refresh:
          // Stale identity (or stale tombstone): drop and re-search below.
          await (database.sourceMatchTable.delete()
                ..where((s) => s.id.equals(cachedSource!.id)))
            .go();
          cachedSource = null;
        case SourceMatchCacheDecision.negativeHit:
          // A recent search already found nothing: fail without
          // spending another search.
          throw TrackNotFoundError(query);
      }
    }

    final candidateKey = '${audioSourceConfig.slug}:${youtubeEngine.runtimeType}';

    if (cachedSource == null) {
      final siblings = await fetchSiblings(ref: ref, query: query);
      if (siblings.isEmpty) {
        // Negative cache: remember the miss so near-future resolutions
        // fail fast instead of re-searching. Expires via the same TTL.
        await database.into(database.sourceMatchTable).insert(
              SourceMatchTableCompanion.insert(
                trackId: query.id,
                sourceInfo: const Value('{}'),
                sourceType: audioSourceConfig.slug,
              ),
            );
        throw TrackNotFoundError(query);
      }

      await database.into(database.sourceMatchTable).insert(
            SourceMatchTableCompanion.insert(
              trackId: query.id,
              sourceInfo: Value(jsonEncode(siblings.first)),
              sourceType: audioSourceConfig.slug,
            ),
          );

      final manifest = await audioSource.audioSource.streams(siblings.first);

      return SourcedTrack(
        ref: ref,
        siblings: siblings.skip(1).toList(),
        info: siblings.first,
        source: audioSourceConfig.slug,
        sources: manifest,
        query: query,
        sourceCandidateKey: candidateKey,
      );
    }
    final item = SpotubeAudioSourceMatchObject.fromJson(
      jsonDecode(cachedSource.sourceInfo),
    );
    final manifest = await audioSource.audioSource.streams(item);

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: [],
      sources: manifest,
      info: item,
      query: query,
      source: audioSourceConfig.slug,
      sourceCandidateKey: candidateKey,
    );

    AppLogger.log.i("${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  static List<SpotubeAudioSourceMatchObject> rankResults(
    List<SpotubeAudioSourceMatchObject> results,
    SpotubeFullTrackObject track,
  ) {
    return results
        .map((sibling) {
          int score = 0;

          for (final artist in track.artists) {
            final isSameChannelArtist =
                sibling.artists.any((a) => a.toLowerCase() == artist.name);

            if (isSameChannelArtist) {
              score += 1;
            }

            final titleContainsArtist =
                sibling.title.toLowerCase().contains(artist.name.toLowerCase());

            if (titleContainsArtist) {
              score += 1;
            }
          }

          final titleContainsTrackName =
              sibling.title.toLowerCase().contains(track.name.toLowerCase());

          final hasOfficialFlag =
              officialMusicRegex.hasMatch(sibling.title.toLowerCase());

          if (titleContainsTrackName) {
            score += 3;
          }

          if (hasOfficialFlag) {
            score += 1;
          }

          if (hasOfficialFlag && titleContainsTrackName) {
            score += 2;
          }

          return (sibling: sibling, score: score);
        })
        .sorted((a, b) => b.score.compareTo(a.score))
        .map((e) => e.sibling)
        .toList();
  }

  static Future<List<SpotubeAudioSourceMatchObject>> fetchSiblings({
    required SpotubeFullTrackObject query,
    required Ref ref,
  }) async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);

    if (audioSource == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final videoResults = <SpotubeAudioSourceMatchObject>[];

    final searchResults = await audioSource.audioSource.matches(query);

    if (ServiceUtils.onlyContainsEnglish(query.name)) {
      videoResults.addAll(searchResults);
    } else {
      videoResults.addAll(rankResults(searchResults, query));
    }

    return videoResults.toSet().toList();
  }

  Future<SourcedTrack> copyWithSibling() async {
    if (siblings.isNotEmpty) {
      return this;
    }
    final fetchedSiblings = await fetchSiblings(ref: ref, query: query);

    return SourcedTrack(
      ref: ref,
      siblings: fetchedSiblings.where((s) => s.id != info.id).toList(),
      source: source,
      sources: sources,
      info: info,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    if (sibling.id == info.id) {
      return null;
    }

    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final isStepSibling = siblings.none((s) => s.id == sibling.id);

    final newSourceInfo = isStepSibling
        ? sibling
        : siblings.firstWhere((s) => s.id == sibling.id);

    final newSiblings = siblings.where((s) => s.id != sibling.id).toList()
      ..insert(0, info);

    final manifest = await audioSource.audioSource.streams(newSourceInfo);

    final database = ref.read(databaseProvider);

    await (database.sourceMatchTable.delete()
          ..where(
            (table) =>
                table.trackId.equals(query.id) &
                table.sourceType.equals(audioSourceConfig.slug),
          ))
        .go();

    await database.into(database.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: query.id,
            sourceInfo: Value(jsonEncode(sibling)),
            sourceType: audioSourceConfig.slug,
            createdAt: Value(DateTime.now()),
          ),
          mode: InsertMode.replace,
        );

    return SourcedTrack(
      ref: ref,
      source: source,
      siblings: newSiblings,
      sources: manifest,
      info: newSourceInfo,
      query: query,
    );
  }

  Future<SourcedTrack?> swapWithSiblingOfIndex(int index) {
    return swapWithSibling(siblings[index]);
  }

  Future<SourcedTrack> refreshStream() async {
    final audioSource = await ref.read(audioSourcePluginProvider.future);
    final audioSourceConfig = await ref.read(metadataPluginsProvider
        .selectAsync((data) => data.defaultAudioSourcePluginConfig));
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    List<SpotubeAudioSourceStreamObject> validStreams = [];

    final stringBuffer = StringBuffer();

    // Phase 2 perf (2.4): validate candidates in bounded concurrent waves
    // (max 4 in flight) instead of one HEAD at a time. Order-preserving and
    // abort-on-throw, matching the old serial loop; per-request timeouts
    // bound hangs that previously stalled the whole sequence indefinitely.
    final validSources = await filterValidBounded(
      sources,
      (source) async {
        final res = await globalDio.head(
          source.url,
          options: Options(
            validateStatus: (status) =>
                status != null && status < 500,
            // Abort the socket itself on stall. Note: Dio 5 only allows
            // connectTimeout on BaseOptions, so the connect phase is bounded
            // by the helper-level timeout in filterValidBounded; this
            // receiveTimeout aborts the underlying request (30s matches the
            // plugin-download precedent).
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        return res.statusCode;
      },
      onValidated: (source, statusCode) {
        stringBuffer.writeln(
          "[${query.id}] $statusCode ${source.container} ${source.codec} ${source.bitrate}",
        );
      },
    );

    validStreams = validSources;

    AppLogger.log.d(stringBuffer.toString());

    if (validStreams.isEmpty) {
      // The cached manifest is entirely unusable (e.g. every URL 403'd by
      // the CDN). Re-fetch the manifest — the engine retries with alternate
      // clients internally — and re-validate instead of trusting the raw
      // result: returning unvalidated URLs here is what previously turned
      // one dead manifest into an endless playback-refresh loop.
      final refetched = await audioSource.audioSource.streams(info);
      final revalidated = await filterValidBounded(
        refetched,
        (source) async {
          final res = await globalDio.head(
            source.url,
            options: Options(
              validateStatus: (status) => status != null && status < 500,
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          return res.statusCode;
        },
      );
      if (revalidated.isEmpty) {
        throw NoValidStreamError(
          "All stream URLs rejected for ${query.name} after manifest re-fetch",
        );
      }
      validStreams = revalidated;
    }

    final sourcedTrack = SourcedTrack(
      ref: ref,
      siblings: siblings,
      source: source,
      sources: validStreams,
      info: info,
      query: query,
    );

    AppLogger.log.i("Refreshing ${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  String? get url {
    final preferences = ref.read(audioSourcePresetsProvider);
    final preset = preferences.presets
            .elementAtOrNull(preferences.selectedStreamingContainerIndex) ??
        preferences.presets.firstOrNull;

    // No presets at all (plugin not loaded yet): serve the first validated
    // stream instead of throwing RangeError on index 0.
    if (preset == null) return sources.firstOrNull?.url;

    return getUrlOfQuality(preset, preferences.selectedStreamingQualityIndex);
  }

  /// Returns the URL of the track based on the codec and quality preferences.
  /// If an exact match is not found, it will return the closest match based on
  /// the user's audio quality preference.
  ///
  /// If no sources match the codec, it will return the first or last source
  /// based on the user's audio quality preference.
  SpotubeAudioSourceStreamObject? getStreamOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    if (sources.isEmpty) return null;

    final quality = preset.qualities.elementAtOrNull(qualityIndex);

    if (quality != null) {
      final exactMatch = sources.firstWhereOrNull(
        (source) {
          if (source.container != preset.name) return false;

          if (quality case SpotubeAudioLosslessContainerQuality()) {
            return source.sampleRate == quality.sampleRate &&
                source.bitDepth == quality.bitDepth;
          } else {
            return source.bitrate ==
                (quality as SpotubeAudioLossyContainerQuality).bitrate;
          }
        },
      );

      if (exactMatch != null) {
        return exactMatch;
      }
    }

    final inContainer =
        sources.where((source) => source.container == preset.name).toList();

    // The requested container/quality can disappear after validation
    // (re-fetched manifest, engine returned a different set). Serve the
    // best available stream instead of throwing StateError from reduce()
    // on an empty iterable.
    if (quality == null || inContainer.isEmpty) {
      return getStreamOfAnyContainer(preset);
    }

    return inContainer.reduce((prev, curr) {
      if (quality is SpotubeAudioLosslessContainerQuality) {
        final prevDiff = ((prev.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((prev.bitDepth ?? 0) - quality.bitDepth).abs();
        final currDiff = ((curr.sampleRate ?? 0) - quality.sampleRate).abs() +
            ((curr.bitDepth ?? 0) - quality.bitDepth).abs();
        return currDiff < prevDiff ? curr : prev;
      } else {
        final prevDiff = ((prev.bitrate ?? 0) -
                (quality as SpotubeAudioLossyContainerQuality).bitrate)
            .abs();
        final currDiff = ((curr.bitrate ?? 0) - quality.bitrate).abs();
        return currDiff < prevDiff ? curr : prev;
      }
    });
  }

  String? getUrlOfQuality(
    SpotubeAudioSourceContainerPreset preset,
    int qualityIndex,
  ) {
    return getStreamOfQuality(preset, qualityIndex)?.url;
  }

  /// Picks the best available stream without requiring the user's selected
  /// container. Tries the exact-selected container first; if that container
  /// has no source at all, falls back to the highest-bitrate stream across
  /// every available container. Used for downloads when the selected
  /// quality/container must not be a hard requirement.
  SpotubeAudioSourceStreamObject? getStreamOfAnyContainer(
    SpotubeAudioSourceContainerPreset preferredPreset,
  ) {
    if (sources.isEmpty) return null;

    final inPreferred = sources
        .where((s) => s.container == preferredPreset.name)
        .toList();
    if (inPreferred.isNotEmpty) {
      return inPreferred.reduce((a, b) =>
          (b.bitrate ?? 0) > (a.bitrate ?? 0) ? b : a);
    }

    return sources.reduce((a, b) =>
        (b.bitrate ?? 0) > (a.bitrate ?? 0) ? b : a);
  }

  SpotubeAudioSourceContainerPreset? get qualityPreset {
    final presetState = ref.read(audioSourcePresetsProvider);
    return presetState.presets
        .elementAtOrNull(presetState.selectedStreamingContainerIndex);
  }
}
