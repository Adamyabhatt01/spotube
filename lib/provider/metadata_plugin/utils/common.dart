// ignore: implementation_imports
import 'package:riverpod/src/async_notifier.dart';
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';

import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/utils/rate_limit_gate.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/metadata.dart';

extension PaginationExtension<T> on AsyncValue<T> {
  bool get isLoadingNextPage => this is AsyncData && this is AsyncLoadingNext;
}

mixin MetadataPluginMixin<K>
// ignore: invalid_use_of_internal_member
    on AsyncNotifierBase<SpotubePaginationResponseObject<K>> {
  Future<MetadataPlugin> get metadataPlugin async {
    final plugin = await ref.read(metadataPluginProvider.future);

    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    return plugin;
  }

  /// Runs [request], absorbing transient Spotify 429 rate limits with a
  /// bounded cooldown-retry. Every 429 also strikes the session-wide
  /// [RateLimitGate], so once throttled, further gated requests fail fast
  /// (with [RateLimitedUntilException]) instead of re-probing the wall on
  /// every provider build. Any other error rethrows as AsyncError.
  Future<T> fetchWithRateLimitRetry<T>(
    Future<T> Function() request, {
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    final gate = ref.read(rateLimitGateProvider.notifier);
    gate.ensureOpen();

    var attempt = 0;
    while (true) {
      try {
        final result = await request();
        gate.recordSuccess();
        return result;
      } catch (e) {
        if (!isRateLimitedError(e)) rethrow;
        if (e is! RateLimitedUntilException) gate.recordRateLimit();
        if (!shouldRetryAfterRateLimit(e, attempt)) rethrow;
        ++attempt;
        await Future.delayed(cooldown);
      }
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
