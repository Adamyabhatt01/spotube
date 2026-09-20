import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/services/sourced_track/exceptions.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_explode_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';

/// A single source candidate: one audio-source plugin paired with one
/// YouTube engine. Plugin instances are created lazily per (config, engine)
/// and cached via [pluginCacheProvider], scoped to provider lifecycle.
class SourceCandidate {
  final PluginConfiguration config;
  final YouTubeEngine engine;

  SourceCandidate(this.config, this.engine);

  /// Stable identity used for the per-(config, engine) plugin cache. The
  /// version is part of the key so a plugin update can never reuse the VM
  /// compiled from the previous version's bytecode.
  String get key => '${config.slug}@${config.version}:${engine.runtimeType}';
}

/// Ordered, lazy source resolution for a track. This is the single source
/// of truth for candidate ordering across downloads and playback fallbacks,
/// so fallback logic is never duplicated. Plugin construction is deferred
/// until a candidate is actually attempted, and reused within one resolver.
class SourceResolver {
  final Ref ref;

  SourceResolver(this.ref);

  /// Audio-source plugins in priority order. Honors the user's configured
  /// [sourcePriority] (list of plugin slugs) when present; otherwise the
  /// selected default first, then every other installed audio-source plugin
  /// by slug.
  Future<List<PluginConfiguration>> _orderedPlugins() async {
    final state = await ref.read(metadataPluginsProvider.future);
    final priority = ref.read(
      userPreferencesProvider.select((s) => s.sourcePriority),
    );

    final audioSourcePlugins = state.plugins
        .where((p) => p.abilities.contains(PluginAbilities.audioSource))
        .toList();

    if (priority.isNotEmpty) {
      final ordered = <PluginConfiguration>[];
      for (final slug in priority) {
        ordered.addAll(audioSourcePlugins.where((p) => p.slug == slug));
      }
      ordered.addAll(
        audioSourcePlugins.where((p) => !priority.contains(p.slug)),
      );
      return ordered.toSet().toList();
    }

    final defaultConfig = state.defaultAudioSourcePluginConfig;
    return [
      if (defaultConfig != null) defaultConfig,
      ...audioSourcePlugins.where(
        (p) => defaultConfig == null || p.slug != defaultConfig.slug,
      ),
    ];
  }

  /// Engines in priority order. Honors the user's configured [sourcePriority]
  /// (list of engine labels) when present; otherwise the user-selected engine
  /// first, then every other platform-available engine.
  List<YouTubeEngine> _orderedEngines() {
    final priority = ref.read(
      userPreferencesProvider.select((s) => s.sourcePriority),
    );
    final userPref = ref.read(
      userPreferencesProvider.select((value) => value.youtubeClientEngine),
    );

    List<YoutubeClientEngine> modes;
    if (priority.isNotEmpty) {
      modes = [];
      for (final label in priority) {
        modes.addAll(
          YoutubeClientEngine.values.where((m) => m.label == label),
        );
      }
      modes.addAll(
        YoutubeClientEngine.values.where(
          (m) => !priority.contains(m.label),
        ),
      );
    } else {
      modes = [userPref, ...YoutubeClientEngine.values];
    }

    return modes
        .where((mode) => mode.isAvailableForPlatform())
        .toSet()
        .toList()
        .map(_buildEngine)
        .toList();
  }

  YouTubeEngine _buildEngine(YoutubeClientEngine mode) {
    return switch (mode) {
      YoutubeClientEngine.newPipe => NewPipeEngine(),
      YoutubeClientEngine.ytDlp => YtDlpEngine(),
      YoutubeClientEngine.youtubeExplode => YouTubeExplodeEngine(),
    };
  }

  /// Lazily builds (and caches via provider) a live plugin for a config, bound
  /// to an engine. For the default plugin + default engine candidate it
  /// reuses the already-instantiated [audioSourcePluginProvider], so the
  /// most common path does not spin up a duplicate Hetu VM. Other pairs are
  /// built at most once via the provider cache.
  Future<MetadataPlugin> _pluginFor(SourceCandidate candidate) async {
    // Reuse the default plugin instance when this candidate IS the default
    // (first in priority = default plugin + user-selected engine). This
    // avoids a second Hetu VM for normal downloads/playback.
    final plugins = await _orderedPlugins();
    final engines = _orderedEngines();
    final isDefault =
        plugins.isNotEmpty && engines.isNotEmpty &&
        candidate.key == SourceCandidate(plugins.first, engines.first).key;

    if (isDefault) {
      final defaultPlugin = await ref.read(audioSourcePluginProvider.future);
      if (defaultPlugin != null) {
        final cache = ref.read(pluginCacheProvider);
        cache.getOrCreate(candidate.key, () => Future.value(defaultPlugin));
        return defaultPlugin;
      }
    }

    final cache = ref.read(pluginCacheProvider);
    return cache.getOrCreate(
      candidate.key,
      () async {
        final notifier = ref.read(metadataPluginsProvider.notifier);
        final byteCode = await notifier.getPluginByteCode(candidate.config);
        return MetadataPlugin.create(
          candidate.engine,
          candidate.config,
          byteCode,
        );
      },
    );
  }

  /// All candidates in resolution priority order (default engine/plugin
  /// first, then widening through other engines and plugins).
  Future<List<SourceCandidate>> candidates() async {
    final plugins = await _orderedPlugins();
    final engines = _orderedEngines();
    final result = <SourceCandidate>[];
    for (final engine in engines) {
      for (final plugin in plugins) {
        result.add(SourceCandidate(plugin, engine));
      }
    }
    return result;
  }

  /// Resolves [track] through a specific candidate, returning a ready
  /// [SourcedTrack] whose stream is picked via [getStreamOfQuality]. Throws
  /// [TrackNotFoundError] when the candidate yields no matches.
  Future<SourcedTrack> resolve(
    SourceCandidate candidate,
    SpotubeFullTrackObject track,
  ) async {
    final plugin = await _pluginFor(candidate);

    final results = await plugin.audioSource.matches(track);
    if (results.isEmpty) {
      throw TrackNotFoundError(track);
    }

    final ranked = SourcedTrack.rankResults(results, track);
    final info = ranked.first;
    final sources = await plugin.audioSource.streams(info);

    return SourcedTrack(
      ref: ref,
      info: info,
      source: candidate.config.slug,
      siblings: ranked.skip(1).toList(),
      sources: sources,
      query: track,
      sourceCandidateKey: candidate.key,
    );
  }

  /// Resolves [track] to a specific sibling [match] via [candidate], without
  /// re-ranking or re-searching. Used to try alternate videos of a track
  /// when the best match's stream is unusable.
  Future<SourcedTrack> resolveMatch(
    SourceCandidate candidate,
    SpotubeFullTrackObject track,
    SpotubeAudioSourceMatchObject match,
  ) async {
    final plugin = await _pluginFor(candidate);
    final sources = await plugin.audioSource.streams(match);

    return SourcedTrack(
      ref: ref,
      info: match,
      source: candidate.config.slug,
      siblings: const [],
      sources: sources,
      query: track,
      sourceCandidateKey: candidate.key,
    );
  }
}

/// Resolves [track] through the full candidate cascade, returning the first
/// [SourcedTrack] that resolves. Returns null if every candidate fails.
/// Each failure is reported to the logger; the last error is returned via
/// [lastError] so callers can surface why the cascade ultimately failed.
Future<SourcedTrack?> resolveTrackWithFallback(
  Ref ref,
  SpotubeFullTrackObject track, {
  void Function(Object error, StackTrace stack)? onCandidateFailure,
}) async {
  final resolver = SourceResolver(ref);
  final candidates = await resolver.candidates();

  for (final candidate in candidates) {
    try {
      return await resolver.resolve(candidate, track);
    } catch (e, stack) {
      onCandidateFailure?.call(e, stack);
    }
  }

  return null;
}

/// Ordered, de-duplicated stream URLs to try for playback when the primary
/// URL fails. [primary] is the already-resolved default source (yielded
/// first, so the success path pays no extra work); the remaining URLs come
/// from the source cascade (other engines, other plugins, sibling matches).
///
/// Built lazily per request and only consulted on failure, so normal
/// playback latency is unaffected. Limited to top 3 fallback candidates
/// to bound network/search work.
Future<List<String>> playbackFallbackUrls(
  Ref ref,
  SourcedTrack primary,
) async {
  final urls = <String>{};

  final primaryUrl = primary.url;
  if (primaryUrl != null) urls.add(primaryUrl);

  final resolver = SourceResolver(ref);
  final candidates = await resolver.candidates();

  // Find the primary candidate key to skip it (already yielded primary.url)
  final primaryKey = primary.sourceCandidateKey ?? '';

  int fallbackCount = 0;
  const maxFallbacks = 3;

  for (final candidate in candidates) {
    if (fallbackCount >= maxFallbacks) break;
    if (candidate.key == primaryKey) continue;

    try {
      final resolved = await resolver.resolve(candidate, primary.query);
      final url = resolved.url;
      if (url != null) urls.add(url);
      fallbackCount++;

      // Only first sibling per candidate to bound work
      if (resolved.siblings.isNotEmpty && fallbackCount < maxFallbacks) {
        try {
          final siblingTrack =
              await resolver.resolveMatch(candidate, primary.query, resolved.siblings.first);
          final siblingUrl = siblingTrack.url;
          if (siblingUrl != null) urls.add(siblingUrl);
        } catch (_) {
          // A broken sibling match should not block the other candidates.
        }
      }
    } catch (_) {
      // A broken plugin/engine candidate should not block the others.
    }
  }

  return urls.toList();
}