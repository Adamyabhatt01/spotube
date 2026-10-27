part of 'metadata_plugin_provider.dart';

class PluginVmCache<T> {
  final Map<String, Future<T>> _cache = {};

  /// Caches the creation [Future] (so concurrent attempts share one VM), but
  /// a FAILED future must not linger: without the removal below, one transient
  /// error would permanently disable this (plugin, engine) candidate.
  Future<T> getOrCreate(String key, Future<T> Function() factory) {
    final existing = _cache[key];
    if (existing != null) return existing;

    late final Future<T> tracked;
    tracked = factory().catchError((Object error, StackTrace stack) {
      if (identical(_cache[key], tracked)) _cache.remove(key);
      return Future<T>.error(error, stack);
    });
    _cache[key] = tracked;
    return tracked;
  }

  void evictPlugin(String pluginSlug) {
    // Keys look like "<slug>@<version>:<engine>" (see SourceCandidate.key).
    _cache.keys
        .where(
            (k) => k.startsWith('$pluginSlug:') || k.startsWith('$pluginSlug@'))
        .toList()
        .forEach(_cache.remove);
  }

  void clear() => _cache.clear();

  @visibleForTesting
  int get length => _cache.length;
}

/// Provider for the plugin cache. Drops cached VM references when the
/// provider is disposed; hetu_script exposes no VM disposal API, so the
/// VMs themselves become garbage-collectable but are not force-released.
final pluginCacheProvider = Provider<PluginVmCache<MetadataPlugin>>((ref) {
  final cache = PluginVmCache<MetadataPlugin>();
  ref.onDispose(() => cache.clear());
  return cache;
});
