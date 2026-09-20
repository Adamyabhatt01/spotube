import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
// ignore: implementation_imports
import 'package:riverpod/src/async_notifier.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/rate_limit.dart';
import 'package:spotube/services/metadata/library_snapshot.dart';

mixin PaginatedAsyncNotifierMixin<K>
    // ignore: invalid_use_of_internal_member
    on AsyncNotifierBase<SpotubePaginationResponseObject<K>> {
  Future<SpotubePaginationResponseObject<K>> fetch(int offset, int limit);

  /// When non-null, the fully-materialized list is persisted as a
  /// last-known-good snapshot ([LibrarySnapshotTable]) so the library can
  /// still render while Spotify rate-limits the plugin. Opted in per saved
  /// list notifier; plain paginated fakes (tests, other providers) leave
  /// these null and never touch the database.
  String? get snapshotKey => null;

  K Function(Map<String, dynamic>)? get snapshotDecoder => null;

  /// Persists the current state iff it is complete (every page loaded).
  /// Best-effort: cache failures are reported, never surfaced.
  Future<void> persistSnapshot() async {
    final key = snapshotKey;
    if (key == null) return;
    final value = state.value;
    if (value == null || value.hasMore) return;
    try {
      await writeLibrarySnapshot(ref.read(databaseProvider), key, value.items);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Single-flight guard shared by [fetchMore] and [fetchAll] so concurrent
  /// UI triggers (scroll edge, visibility callbacks, heart-button lookups)
  /// can never interleave page fetches and duplicate appended pages.
  bool _isFetching = false;

  /// Best-effort identity for deduplicating page items across appends.
  /// Falls back to instance identity for item types without an [id] field.
  String _itemKey(K item) {
    final dynamic dynamicItem = item;
    try {
      final id = dynamicItem.id;
      if (id != null) return id.toString();
    } on NoSuchMethodError catch (_) {
      // item type has no id field
    }
    return "${item.runtimeType}@${identityHashCode(item)}";
  }

  List<K> _mergeDeduped(List<K> oldItems, List<K> newItems) {
    final existingKeys = oldItems.map(_itemKey).toSet();
    return [
      ...oldItems,
      ...newItems.where((item) => existingKeys.add(_itemKey(item))),
    ];
  }

  Future<void> fetchMore() async {
    if (_isFetching ||
        state.value == null ||
        !state.value!.hasMore ||
        state is AsyncLoadingNext) {
      return;
    }

    final oldState = state.value;
    _isFetching = true;
    try {
      state = AsyncLoadingNext(state.asData!.value);

      final newState = await fetch(
        state.value!.nextOffset!,
        state.value!.limit,
      );

      final oldItems =
          state.value!.items.isEmpty ? <K>[] : state.value!.items.cast<K>();
      final items = newState.items.isEmpty ? <K>[] : newState.items.cast<K>();

      state = AsyncData(
        newState.copyWith(items: _mergeDeduped(oldItems, items)),
      );
      unawaited(persistSnapshot());
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      state = AsyncData(oldState!);
    } finally {
      _isFetching = false;
    }
  }

  /// Fetches every remaining page with a single state emission at the end
  /// (instead of one rebuild per page) and linear-time merging via an
  /// incremental key set. Pagination semantics are unchanged: the same
  /// per-fetch limit fallback chain (100 → 50 → limit → delayed retry)
  /// applies per page, and any unrecoverable page error is reported and
  /// rethrown with state left at its pre-fetchAll value (all-or-nothing,
  /// rather than the previous partial-progress state).
  Future<List<K>> fetchAll() async {
    if (_isFetching) return state.asData?.value.items.cast<K>() ?? [];
    if (state.value == null) return [];
    if (!state.value!.hasMore) return state.value!.items.cast<K>();

    _isFetching = true;
    try {
      final allItems = state.value!.items.cast<K>().toList();
      final seenKeys = allItems.map(_itemKey).toSet();
      var hasMore = state.value!.hasMore;
      var offset = state.value!.nextOffset!;
      var limit = state.value!.limit;
      var lastPage = state.value!;

      while (hasMore) {
        final newState = await fetch(offset, max(limit, 100))
            .catchError((e) => fetch(offset, max(limit, 50)))
            .catchError((e) => fetch(offset, limit))
            .catchError((e) async {
          await Future.delayed(const Duration(milliseconds: 500));
          return fetch(offset, limit);
        });

        hasMore = newState.hasMore;
        // Mirrors the old per-iteration read of state.value!.nextOffset!:
        // a null offset with more pages remaining is a contract violation
        // that fails loudly instead of looping forever. Not read on the
        // final page, where nextOffset is legitimately null.
        if (hasMore) offset = newState.nextOffset!;
        limit = newState.limit;
        lastPage = newState;

        final items = newState.items.isEmpty ? <K>[] : newState.items.cast<K>();
        for (final item in items) {
          if (seenKeys.add(_itemKey(item))) allItems.add(item);
        }
      }

      state = AsyncData(lastPage.copyWith(items: allItems));
      await persistSnapshot();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    } finally {
      _isFetching = false;
    }

    return state.value!.items.cast<K>();
  }
}

abstract class PaginatedAsyncNotifier<K>
    extends AsyncNotifier<SpotubePaginationResponseObject<K>>
    with PaginatedAsyncNotifierMixin<K>, MetadataPluginMixin<K> {}

abstract class AutoDisposePaginatedAsyncNotifier<K>
    extends AutoDisposeAsyncNotifier<SpotubePaginationResponseObject<K>>
    with PaginatedAsyncNotifierMixin<K>, MetadataPluginMixin<K> {}

/// Build-time helper for the four Spotify saved-list notifiers: rate-limit
/// retried first page, with a fallback to the persisted last-known-good
/// snapshot when the fetch fails (429, gate closed, network, plugin error).
mixin SavedListCacheMixin<K>
    on PaginatedAsyncNotifierMixin<K>, MetadataPluginMixin<K> {
  Future<SpotubePaginationResponseObject<K>> buildSavedList({
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    try {
      final page = await fetchWithRateLimitRetry(
        () => fetch(0, 20),
        cooldown: cooldown,
      );
      // A single-page library is already complete; cache it right away.
      if (!page.hasMore) unawaited(persistSnapshot());
      return page;
    } catch (e) {
      final key = snapshotKey;
      final decoder = snapshotDecoder;
      if (key != null && decoder != null) {
        List<K>? stale;
        try {
          stale = await readLibrarySnapshot(
            ref.read(databaseProvider),
            key,
            decoder,
          );
        } catch (_) {
          // A failing cache is simply no cache; the original fetch error
          // is what the user should see.
        }
        if (stale != null && stale.isNotEmpty) {
          return SpotubePaginationResponseObject(
            limit: stale.length,
            nextOffset: null,
            total: stale.length,
            hasMore: false,
            items: stale,
          );
        }
      }
      rethrow;
    }
  }
}
