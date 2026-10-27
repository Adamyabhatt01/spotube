import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/playback/track_sources.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

import 'package:spotube/services/sourced_track/exceptions.dart';
import 'package:spotube/services/sourced_track/source_dependencies.dart';
import 'package:spotube/services/sourced_track/source_resolver.dart';
import 'package:spotube/services/sourced_track/validation.dart';
import 'package:spotube/utils/stream_url_expiry.dart';

/// Uploads that are an official *music* release. Deliberately narrower than it
/// looks: `(Official Lyric Video)` used to match here and collect the same
/// bonus as `(Official Audio)`, which ranked lyric pages ahead of the
/// recording itself.
final officialMusicRegex = RegExp(
  r"official\s(audio|music\s?video|visualizer)",
  caseSensitive: false,
);

/// Not the song: tempo and echo edits, re-sung takes, lyric-only pages. These
/// routinely out-score the recording on view-count-ordered result pages, one
/// measured case being a 60M-view "Slowed + Reverb" of a studio track.
final _alteredVersionRegex = RegExp(
  r"slowed|reverb|sped\s?up|\b8d\b|bass\s?boosted|karaoke|\bcover\b|lyrics?\b|unofficial",
  caseSensitive: false,
);

/// How far a candidate may drift from the track's length and still be the same
/// recording. Bounds live boots, "Best of" runtimes and acoustic re-takes,
/// which are all present on a real result page for a popular song.
const kSourceDurationTolerance = Duration(seconds: 15);

/// A candidate shorter than this share of the track is not a recording of
/// it — it is a clip, an edit, a preview or a YouTube Short.
///
/// A title match alone cannot tell them apart: "One More Time - Daft Punk
/// Edit" carries the exact track title, so the title scored it *above* the
/// real recording, and the mismatched duration only cost it two points
/// against the title's three. A quarter of the track's length is the line:
/// a real recording of a three-minute song is not twenty seconds long, and
/// a genuinely short song (a thirty-second intro) still clears it, because
/// the bound is relative to the track's own length.
const kSourceDurationFloorRatio = 0.25;

/// A candidate longer than this multiple of the track is not a recording of
/// it either — it is a "Best of", a live set, or an hour-long mix.
///
/// Deliberately generous: extended mixes and long live performances are
/// real recordings people play, and the same recording with a couple of
/// minutes of a crowd at the start still lands inside it.
const kSourceDurationCeilingRatio = 3.0;

/// How much a candidate is penalised for a duration that disagrees with the
/// track's.
///
/// Larger than the title match's +3 on purpose: a candidate whose length
/// is wrong is a different recording, however closely the titles agree, so
/// no amount of title agreement may carry it past a candidate of the right
/// length. Before this, a 33-second "Edit" of a five-minute track scored
/// +3 and won against the real recording whenever the real one carried no
/// "(Official …)" marker.
const kSourceDurationMismatchPenalty = 5;

/// Whether a candidate's length rules it out as a recording of [track].
///
/// True when the candidate is a clip, an edit, a preview or a Short of
/// the track, or a mix several times longer than it.
///
/// A candidate with no known duration is never ruled out: the plugin
/// boundary does not always carry one (a yt-dlp flat search row often
/// omits it), and "unknown" is not evidence of a mismatch.
bool isWrongLengthForTrack(
  Duration candidate,
  SpotubeFullTrackObject track,
) {
  if (candidate <= Duration.zero) return false;
  if (track.durationMs <= 0) return false;

  final trackDuration = Duration(milliseconds: track.durationMs);
  if (candidate < trackDuration * kSourceDurationFloorRatio) return true;
  if (candidate > trackDuration * kSourceDurationCeilingRatio) return true;

  return false;
}

/// Trademark/copyright glyphs that survive from label metadata into artist
/// credits ("Slay™"). Search engines treat them as literal terms, which can
/// collapse an otherwise full result page.
final _creditSymbolRegex = RegExp('[™®©℠]');

String _stripCreditSymbols(String value) =>
    value.replaceAll(_creditSymbolRegex, '').trim();

/// YouTube renders a multi-artist upload's channel as "Flawed and 2 more",
/// where only the leading name is comparable to a credited artist.
final _trailingCoArtistsRegex = RegExp(r'\s+and\s+\d+\s+more$');

String _normalizeChannelName(String value) => value
    .toLowerCase()
    .replaceAll(_trailingCoArtistsRegex, '')
    .replaceAll(_creditSymbolRegex, '')
    .trim();

/// Metadata variants worth re-searching, most faithful first.
///
/// Audio-source plugins build the search string themselves from the track
/// (typically `"<name> <artists joined>"`, or the ISRC when present), so the
/// track object handed to the plugin is the only recall lever Spotube has.
/// Two things silently destroy recall there: an ISRC, which never appears in
/// a video title and whose *junk* result page stops the plugin's own
/// empty-result fallback; and featured-artist credits, where a single ™ or
/// accented letter is enough for YouTube's filtered search to return one or
/// zero results instead of twenty.
///
/// Returns an empty list when there is nothing left to simplify, so an
/// already-plain query costs one search whether or not the track exists.
List<SpotubeFullTrackObject> searchRetryVariants(
  SpotubeFullTrackObject track,
) {
  final artists = track.artists
      .map((artist) => artist.copyWith(
            name: _stripCreditSymbols(artist.name),
          ))
      .where((artist) => artist.name.isNotEmpty)
      .toList();

  if (artists.isEmpty) return const [];

  final variants = <SpotubeFullTrackObject>[];
  final simplified = track.copyWith(
    isrc: '',
    name: _stripCreditSymbols(track.name),
    artists: artists,
  );

  if (simplified.name.isEmpty) return const [];

  if (simplified != track) variants.add(simplified);

  // A track credited to many artists is usually findable by its primary one,
  // which drops whatever the simplifying above cannot reach.
  if (artists.length > 1) {
    variants.add(simplified.copyWith(artists: [artists.first]));
  }
  return variants;
}

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
}) {
  final expired =
      (now ?? DateTime.now()).difference(createdAt) > kSourceMatchCacheTtl;
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
  if (readable) {
    return expired
        ? SourceMatchCacheDecision.refresh
        : SourceMatchCacheDecision.hit;
  }
  return expired
      ? SourceMatchCacheDecision.refresh
      : SourceMatchCacheDecision.negativeHit;
}

class SourcedTrack extends BasicSourcedTrack {
  final SourceDependencies deps;

  SourcedTrack({
    required this.deps,
    required super.info,
    required super.query,
    required super.source,
    required super.siblings,
    required super.sources,
    super.sourceCandidateKey,
  });

  static Future<SourcedTrack> fetchFromTrack({
    required SpotubeFullTrackObject query,
    required SourceDependencies deps,
  }) async {
    // The cached-row read and the primary candidate are independent: overlap
    // them instead of paying two sequential awaits on every track start,
    // hit or miss. The plugin/config pair above stays sequential on purpose:
    // a missing audio plugin must throw before any plugin-list work starts.
    final audioSource = await deps.defaultAudioSourcePlugin();
    final audioSourceConfig =
        (await deps.pluginSnapshot()).defaultAudioSourcePluginConfig;
    final youtubeEngine = deps.youtubeClientEngine;
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final database = deps.database;
    final resolver = SourceResolver(deps);
    final (cachedRows, candidateKey) = await (
      (database.select(database.sourceMatchTable)
            ..where((s) =>
                s.trackId.equals(query.id) &
                s.sourceType.equals(audioSourceConfig.slug))
            ..limit(1)
            ..orderBy([
              (s) => OrderingTerm(
                  expression: s.createdAt, mode: OrderingMode.desc),
            ]))
          .get(),
      resolver.primaryCandidate().then((candidate) => candidate.key),
    ).wait;
    var cachedSource = cachedRows.firstOrNull;

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

    if (cachedSource == null) {
      // A primary-engine failure comes in two kinds and they must not be
      // conflated: "searched, found nothing" is a miss worth remembering,
      // "could not search" (crashed backend, bot check) is not. Both widen.
      var siblings = const <SpotubeAudioSourceMatchObject>[];
      Object? primaryFailure;
      try {
        siblings = await fetchSiblings(deps: deps, query: query);
      } on TrackNotFoundError {
        // answered "no such track"
      } catch (error) {
        primaryFailure = error;
      }

      if (siblings.isEmpty) {
        // Playback used to stop here: `playbackFallbackUrls` can only reroute a
        // URL that already exists, and only downloads walked the other engines —
        // so a track visible to a backend the user did not pick never played.
        // Costs nothing unless the first engine came up empty, which is the case
        // above.
        final SourcedTrack resolvedElsewhere;
        try {
          resolvedElsewhere = await resolver.resolveFirstAvailable(
            query,
            candidates: await resolver.engineFallbackCandidates(
              pluginSlug: audioSourceConfig.slug,
              skipEngine: youtubeEngine,
            ),
          );
        } on TrackNotFoundError {
          if (primaryFailure != null) {
            // Nothing else could resolve it either, and the original error is
            // the informative one. Absence stays uncached so the next playback
            // gets a fresh attempt.
            throw primaryFailure;
          }
          // Every engine answered "no such track": remember the miss so
          // near-future resolutions fail fast instead of re-searching.
          // Expires via the same TTL.
          await database.into(database.sourceMatchTable).insert(
                SourceMatchTableCompanion.insert(
                  trackId: query.id,
                  sourceInfo: const Value('{}'),
                  sourceType: audioSourceConfig.slug,
                ),
              );
          rethrow;
        }

        await database.into(database.sourceMatchTable).insert(
              SourceMatchTableCompanion.insert(
                trackId: query.id,
                sourceInfo: Value(jsonEncode(resolvedElsewhere.info)),
                sourceType: resolvedElsewhere.source,
              ),
            );

        return resolvedElsewhere;
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
        deps: deps,
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
    // A cached match still costs a full manifest extraction on every serve.
    // Skip it while every URL in a previously extracted manifest is
    // unexpired; anything else (miss, expiry, unknown expiry) falls through
    // to today's re-extract path, and failures there propagate exactly as
    // before — a failed extraction never populates the cache.
    final manifest = deps.manifestCache.lookup(
          trackId: query.id,
          sourceSlug: audioSourceConfig.slug,
          matchId: item.id,
          now: DateTime.now(),
        ) ??
        await (() async {
          final extracted = await audioSource.audioSource.streams(item);
          final minExpire = manifestMinExpireSeconds(
            [for (final source in extracted) source.url],
          );
          if (minExpire != null) {
            deps.manifestCache.store(
              trackId: query.id,
              sourceSlug: audioSourceConfig.slug,
              matchId: item.id,
              sources: extracted,
              minExpireSeconds: minExpire,
            );
          }
          return extracted;
        })();

    final sourcedTrack = SourcedTrack(
      deps: deps,
      siblings: [],
      sources: manifest,
      info: item,
      query: query,
      source: audioSourceConfig.slug,
      sourceCandidateKey: candidateKey,
    );

    // The `url` getter reads the preset provider and rescans the manifest;
    // it exists to trace resolution, so it must not run for a release-mode
    // log line that Level.info drops anyway.
    if (kDebugMode) AppLogger.log.i("${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  /// Searches [track] through [search], escalating to
  /// [searchRetryVariants] only when a variant comes back clean-empty.
  ///
  /// A thrown search is never treated as an empty one: it propagates so
  /// callers skip the negative cache instead of remembering a blockage as
  /// "this track does not exist".
  static Future<List<SpotubeAudioSourceMatchObject>> matchWithQueryVariants({
    required SpotubeFullTrackObject track,
    required Future<List<SpotubeAudioSourceMatchObject>> Function(
      SpotubeFullTrackObject track,
    ) search,
  }) async {
    final results = await search(track);
    if (results.isNotEmpty) return results;

    for (final variant in searchRetryVariants(track)) {
      final retry = await search(variant);
      if (retry.isNotEmpty) return retry;
    }
    return results;
  }

  static List<SpotubeAudioSourceMatchObject> rankResults(
    List<SpotubeAudioSourceMatchObject> results,
    SpotubeFullTrackObject track,
  ) {
    return results
        .map((sibling) {
          int score = 0;

          for (final artist in track.artists) {
            final isSameChannelArtist = sibling.artists.any(
              (channel) =>
                  _normalizeChannelName(channel) ==
                  _normalizeChannelName(artist.name),
            );

            if (isSameChannelArtist) {
              score += 1;
            }

            final titleContainsArtist = sibling.title
                .toLowerCase()
                .contains(_normalizeChannelName(artist.name));

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

          if (_alteredVersionRegex.hasMatch(sibling.title)) {
            score -= 4;
          }

          // A candidate whose length disagrees with the track is a different
          // recording of it, however closely the titles agree. `durationMs` is
          // the only field the plugin boundary still carries that says
          // anything about the recording itself. A non-positive duration means
          // the plugin never learned one, which is not evidence of a mismatch.
          final duration = sibling.duration;
          if (duration > Duration.zero && track.durationMs > 0) {
            final drift = duration - Duration(milliseconds: track.durationMs);
            if (drift.abs() > kSourceDurationTolerance) {
              score -= kSourceDurationMismatchPenalty;
            }
          }

          return (sibling: sibling, score: score);
        })
        .sorted((a, b) => b.score.compareTo(a.score))
        .map((e) => e.sibling)
        .toList();
  }

  static Future<List<SpotubeAudioSourceMatchObject>> fetchSiblings({
    required SpotubeFullTrackObject query,
    required SourceDependencies deps,
  }) async {
    final audioSource = await deps.defaultAudioSourcePlugin();

    if (audioSource == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    final videoResults = <SpotubeAudioSourceMatchObject>[];

    final searchResults = await matchWithQueryVariants(
      track: query,
      search: (track) => audioSource.audioSource.matches(track),
    );

    // The clip of a track carries the track's exact title, so the title
    // score cannot tell a 33-second edit from the five-minute recording.
    // The length can — and the wrong-length candidates only go when
    // something of the right length is left to play.
    final ranked = rankResults(searchResults, query);
    videoResults.addAll(dropWrongLengthCandidates(ranked, query));

    return videoResults.toSet().toList();
  }

  /// Drops the candidates whose length rules them out as a recording of
  /// [track], but only when something of the right length is left.
  ///
  /// A clip of the track ("One More Time - Daft Punk Edit", 33 seconds, for
  /// a five-minute recording) carries the exact track title, so the title
  /// score alone cannot separate it from the recording. The length can.
  ///
  /// The candidates are only dropped when a right-length one survives:
  /// a track that genuinely has no full-length match on the backend must
  /// still play *something*, and a clip is better than nothing. When every
  /// candidate is the wrong length, they are all kept and the ranking
  /// decides — the penalty above then puts the closest one first.
  static List<SpotubeAudioSourceMatchObject> dropWrongLengthCandidates(
    List<SpotubeAudioSourceMatchObject> candidates,
    SpotubeFullTrackObject track,
  ) {
    if (candidates.isEmpty) return candidates;

    final wrongLength = <SpotubeAudioSourceMatchObject>[];
    final rightLength = <SpotubeAudioSourceMatchObject>[];

    for (final candidate in candidates) {
      if (isWrongLengthForTrack(candidate.duration, track)) {
        wrongLength.add(candidate);
      } else {
        rightLength.add(candidate);
      }
    }

    if (rightLength.isEmpty) return candidates;
    return rightLength;
  }

  Future<SourcedTrack> copyWithSibling() async {
    if (siblings.isNotEmpty) {
      return this;
    }
    final fetchedSiblings = await fetchSiblings(deps: deps, query: query);

    return SourcedTrack(
      deps: deps,
      siblings: fetchedSiblings.where((s) => s.id != info.id).toList(),
      source: source,
      sources: sources,
      info: info,
      query: query,
      sourceCandidateKey: sourceCandidateKey,
    );
  }

  Future<SourcedTrack?> swapWithSibling(
    SpotubeAudioSourceMatchObject sibling,
  ) async {
    if (sibling.id == info.id) {
      return null;
    }

    final audioSource = await deps.defaultAudioSourcePlugin();
    final audioSourceConfig =
        (await deps.pluginSnapshot()).defaultAudioSourcePluginConfig;
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

    final database = deps.database;

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
      deps: deps,
      source: source,
      siblings: newSiblings,
      sources: manifest,
      info: newSourceInfo,
      query: query,
      sourceCandidateKey: sourceCandidateKey,
    );
  }

  Future<SourcedTrack> refreshStream() async {
    final audioSource = await deps.defaultAudioSourcePlugin();
    final audioSourceConfig =
        (await deps.pluginSnapshot()).defaultAudioSourcePluginConfig;
    if (audioSource == null || audioSourceConfig == null) {
      throw MetadataPluginException.noDefaultAudioSourcePlugin();
    }

    List<SpotubeAudioSourceStreamObject> validStreams = [];

    // The per-candidate dump is only ever logged at Level.debug, but the
    // argument is interpolated before the level filter runs — so in release
    // it built a line per validated candidate for nothing. A null collector
    // skips the interpolation entirely (null-aware calls don't evaluate
    // their arguments).
    final stringBuffer = kDebugMode ? StringBuffer() : null;

    // Phase 2 perf (2.4): validate candidates in bounded concurrent waves
    // (max 4 in flight) instead of one HEAD at a time. Order-preserving and
    // abort-on-throw, matching the old serial loop; per-request timeouts
    // bound hangs that previously stalled the whole sequence indefinitely.
    final validSources = await filterValidBounded(
      sources,
      (source) async {
        final res = await deps.dio.head(
          source.url,
          options: Options(
            validateStatus: (status) => status != null && status < 500,
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
        // Null-aware call: with the dump off (release), the line is never
        // interpolated for the up-to-20 candidates this loop validates.
        stringBuffer?.writeln(
          "[${query.id}] $statusCode ${source.container} ${source.codec} ${source.bitrate}",
        );
      },
    );

    validStreams = validSources;

    if (stringBuffer case final dump?) {
      AppLogger.log.d(dump.toString());
    }

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
          final res = await deps.dio.head(
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
      deps: deps,
      siblings: siblings,
      source: source,
      sources: validStreams,
      info: info,
      query: query,
      sourceCandidateKey: sourceCandidateKey,
    );

    if (kDebugMode) AppLogger.log.i("Refreshing ${query.name}: ${sourcedTrack.url}");

    return sourcedTrack;
  }

  String? get url {
    final preferences = deps.presets;
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

    final inPreferred =
        sources.where((s) => s.container == preferredPreset.name).toList();
    if (inPreferred.isNotEmpty) {
      return inPreferred
          .reduce((a, b) => (b.bitrate ?? 0) > (a.bitrate ?? 0) ? b : a);
    }

    return sources
        .reduce((a, b) => (b.bitrate ?? 0) > (a.bitrate ?? 0) ? b : a);
  }

  /// The selected container preset, or null when the audio-source plugin
  /// has published no presets at all.
  ///
  /// Null is a real state, not a bug: the preset list is empty until the
  /// audio-source plugin finishes loading, and a persisted index can point
  /// past the end of a shrunken list. Callers must not force-unwrap this —
  /// see [container] for the null-safe way to read the container.
  SpotubeAudioSourceContainerPreset? get qualityPreset {
    final presetState = deps.presets;
    return presetState.presets
        .elementAtOrNull(presetState.selectedStreamingContainerIndex);
  }

  /// The container the audio is actually served in: the container name
  /// ("webm", "mp4", ...) and its on-disk file extension ("weba", "m4a").
  ///
  /// Null only when there is genuinely no container to report — no presets
  /// and no resolved streams — which means there is nothing to play either.
  ///
  /// The fallback chain mirrors the one [url] uses, so the container
  /// reported to an HTTP client always matches the container of the bytes
  /// being served:
  ///   1. the selected preset,
  ///   2. the first available preset (stale persisted index),
  ///   3. the container of the first resolved stream (no presets yet).
  ({String name, String extension})? get container {
    final presetState = deps.presets;
    final preset = presetState.presets
            .elementAtOrNull(presetState.selectedStreamingContainerIndex) ??
        presetState.presets.firstOrNull;

    final name = preset?.name ?? sources.firstOrNull?.container;
    if (name == null) return null;

    return (
      name: name,
      extension:
          SpotubeAudioSourceContainerPreset.fileExtensionForContainer(name),
    );
  }
}
