// ignore: implementation_imports
import 'package:riverpod/src/async_notifier.dart';
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';

import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/metadata.dart';

extension PaginationExtension<T> on AsyncValue<T> {
  bool get isLoadingNextPage => this is AsyncData && this is AsyncLoadingNext;
}

/// Re-mints the metadata session's access token, if that is possible.
///
/// A rejected token is not a rate limit — waiting does not fix it — but the
/// session may still be recoverable: the cookies can be good while the access
/// token has been invalidated before its stated expiry, and a fresh token is
/// a far better answer than asking the user to sign in again.
///
/// A seam, so a test can stand in for the plugin without loading one.
final metadataSessionRefresherProvider =
    Provider<Future<bool> Function()>((ref) {
  return () async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) return false;

    await plugin.auth.refresh();
    return true;
  };
});

mixin MetadataPluginMixin<K>
// ignore: invalid_use_of_internal_member
    on AsyncNotifierBase<SpotubePaginationResponseObject<K>> {
  /// The plugin future captured for this build.
  ///
  /// A saved-list refresh can outlive the provider that started it: the
  /// active plugin/account changes, Riverpod invalidates this notifier, and
  /// the old instance's in-flight fetch resumes after that invalidation.
  /// Reading the dependency again there is an assertion, not a value. Prime
  /// this at the top of a build or a refresh (while the ref is valid) and
  /// every later request reuses the same plugin instance until the next
  /// build replaces it.
  Future<MetadataPlugin>? _metadataPluginFuture;

  /// Provider values captured for this build alongside the plugin future.
  ///
  /// A refresh can resume after this notifier was invalidated, when any new
  /// `ref.read` is an assertion. The gate and session refresher are immutable
  /// for the life of the build, so capture them with the plugin and reuse them
  /// for every request the build starts.
  RateLimitGate? _rateLimitGate;
  Future<bool> Function()? _metadataSessionRefresher;

  Future<MetadataPlugin> get metadataPlugin {
    return _metadataPluginFuture ??= _resolveMetadataPlugin();
  }

  Future<MetadataPlugin> _resolveMetadataPlugin() async {
    return _requirePlugin(await ref.read(metadataPluginProvider.future));
  }

  MetadataPlugin _requirePlugin(MetadataPlugin? plugin) {
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    return plugin;
  }

  /// Captures the current plugin before the caller's first `await`.
  ///
  /// Safe only while this notifier is mounted and not invalidated; call it
  /// from `build()` (force) or method entry points (cached). A refresh on a
  /// notifier that has already been invalidated must reuse the future its
  /// build captured instead of reading the ref again.
  void primeMetadataPlugin({bool force = false}) {
    if (!force && _metadataPluginFuture != null) return;
    final future = ref.read(metadataPluginProvider.future).then(_requirePlugin);
    _metadataPluginFuture = future;
    // Capture every dependency this build's requests need in the same turn.
    // Waiting until a request is about to run is too late if the build has
    // since been invalidated (theme/account change).
    _rateLimitGate = ref.read(rateLimitGateProvider.notifier);
    _metadataSessionRefresher = ref.read(metadataSessionRefresherProvider);
    // A provider disposed before the plugin finishes loading completes this
    // future with an error, and a notifier that never reaches its fetch may
    // have no other listener. Attach one so teardown cannot report an
    // unhandled async error; callers that do await it still see the failure.
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }

  RateLimitGate get rateLimitGate =>
      _rateLimitGate ?? ref.read(rateLimitGateProvider.notifier);

  /// Reads from a plugin through the session [RateLimitGate] without waiting
  /// out a cooldown: a 429 strikes the gate and surfaces immediately, so the
  /// next read fails fast instead of re-probing Spotify's rate limiter. Used
  /// by provider `build()`s, which back navigation-rebuilt screens.
  Future<T> fetchGated<T>(Future<T> Function() request) =>
      runGated(rateLimitGate, request);

  /// Runs [request], absorbing transient Spotify 429 rate limits with a
  /// bounded cooldown-retry. Every 429 also strikes the session-wide
  /// [RateLimitGate], so once throttled, further gated requests fail fast
  /// (with [RateLimitedUntilException]) instead of re-probing the wall on
  /// every provider build. Any other error rethrows as AsyncError.
  ///
  /// A rejected credential (401/403) gets one extra attempt: the session is
  /// refreshed from its stored cookies and the request is retried. Spotify
  /// invalidates access tokens before their stated expiry, and the plugin's
  /// own refresh timer only fires at that expiry — so without this the app
  /// stays 401-ing (with a stale library) until the user signed in again,
  /// even though the cookies were still good.
  Future<T> fetchWithRateLimitRetry<T>(
    Future<T> Function() request, {
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    // Capture provider values before the first await. A theme/plugin change
    // can invalidate this provider while the request is in flight, and
    // Riverpod forbids reading a dependency after that invalidation but
    // before the rebuild; the gate instance itself remains safe to use.
    // `primeMetadataPlugin` captures these at build time; the getters are only
    // a fallback for callers that never went through that path.
    final gate = rateLimitGate;
    final Future<bool> Function() refreshSession =
        _metadataSessionRefresher ?? ref.read(metadataSessionRefresherProvider);

    try {
      return await runGated(
        gate,
        request,
        maxRetries: maxRateLimitAutoRetries,
        cooldown: cooldown,
      );
    } catch (e) {
      if (!isCredentialError(e)) rethrow;

      // One refresh, one retry: the cookies are the source of a fresh token.
      final refreshed = await _refreshSession(refreshSession);
      if (!refreshed) rethrow;

      return runGated(
        gate,
        request,
        maxRetries: maxRateLimitAutoRetries,
        cooldown: cooldown,
      );
    }
  }

  /// Re-mints the session's access token. Returns false when that is not
  /// possible — no plugin, no cookies, or a refresh that failed — so the
  /// caller can fall back to telling the user the session expired.
  Future<bool> _refreshSession(Future<bool> Function() refresh) async {
    try {
      return await refresh();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return false;
    }
  }
}

extension AutoDisposeAsyncNotifierCacheFor
// ignore: deprecated_member_use
    on AutoDisposeAsyncNotifierProviderRef {
  // When invoked keeps your provider alive for [duration]
  // ignore: unused_element
  void cacheFor([Duration duration = const Duration(minutes: 5)]) {
    final link = keepAlive();
    final timer = Timer(duration, () => link.close());
    onDispose(() => timer.cancel());
  }
}

// ignore: deprecated_member_use
extension AutoDisposeCacheFor on AutoDisposeRef {
  // When invoked keeps your provider alive for [duration]
  // ignore: unused_element
  void cacheFor([Duration duration = const Duration(minutes: 5)]) {
    final link = keepAlive();
    final timer = Timer(duration, () => link.close());
    onDispose(() => timer.cancel());
  }
}

// ignore: subtype_of_sealed_class
class AsyncLoadingNext<T> extends AsyncData<T> {
  const AsyncLoadingNext(super.value);
}
