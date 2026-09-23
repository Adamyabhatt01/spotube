import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

/// Build-time helper for the four Spotify saved-list notifiers.
///
/// Warm (a snapshot exists) the list is served from SQLite and the network
/// revalidation runs *behind* it. Cold it is fetched the blocking way, because
/// there is nothing to show yet. Serving first is the whole point: a build used
/// to sit on `fetchWithRateLimitRetry`'s cooldowns — and on a closed gate it
/// only reached the snapshot inside the `catch`, after all that waiting.
mixin SavedListCacheMixin<K>
    on PaginatedAsyncNotifierMixin<K>, MetadataPluginMixin<K> {
  /// Set once this notifier is gone. The revalidation a warm build started
  /// outlives the page that asked for it, and writing to a disposed provider
  /// is an assertion, not a no-op.
  bool _discarded = false;

  /// The revalidation this instance already has running, so a second warm
  /// build cannot stack a second walk onto the same list.
  Future<void>? _revalidating;

  /// Exposed only so a test can wait for the background refresh instead of
  /// guessing at it with event-loop rounds.
  @visibleForTesting
  Future<void>? get revalidation => _revalidating;

  /// The persisted list as a complete page, or null when there is no usable
  /// snapshot. A failing cache is simply no cache.
  Future<SpotubePaginationResponseObject<K>?> _readSnapshotPage() async {
    final key = snapshotKey;
    final decoder = snapshotDecoder;
    if (key == null || decoder == null) return null;

    final List<K>? items;
    try {
      items = await readLibrarySnapshot(
        ref.read(databaseProvider),
        key,
        decoder,
      );
    } catch (_) {
      // A failing cache is simply no cache; the blocking fetch follows and
      // surfaces whatever error is worth seeing.
      return null;
    }
    if (items == null || items.isEmpty) return null;

    return SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );
  }

  Future<SpotubePaginationResponseObject<K>> buildSavedList({
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    final cached = await _readSnapshotPage();
    if (cached != null) {
      ref.onDispose(() => _discarded = true);
      // Deliberately not awaited: completing this build is what puts the list
      // on screen, and the refresh result arrives through `state` instead.
      _revalidating ??= _revalidate(cooldown, cached).whenComplete(() {
        _revalidating = null;
      });
      return cached;
    }

    final page = await fetchWithRateLimitRetry(
      () => fetch(0, 20),
      cooldown: cooldown,
    );
    // A single-page library is already complete; cache it right away.
    if (!page.hasMore) unawaited(persistSnapshot());
    return page;
  }

  /// Refreshes the first page behind a served snapshot. [served] is the page
  /// this build handed back, used as the identity of "nothing else has touched
  /// the list since".
  ///
  /// Failure leaves the list on screen untouched: it is last-known-good data,
  /// and an `ErrorBox` replacing it would be a worse trade than a stale list.
  /// So the error is only logged — which is also the only place a stale
  /// library is discoverable, hence `reportError` rather than silence.
  Future<void> _revalidate(
    Duration cooldown,
    SpotubePaginationResponseObject<K> served,
  ) async {
    final SpotubePaginationResponseObject<K> fresh;
    try {
      fresh = await fetchWithRateLimitRetry(
        () => fetch(0, 20),
        cooldown: cooldown,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return;
    }

    // Anything that already moved the list owns it: an optimistic favorite, a
    // page walk, or a build that has not delivered [served] yet (then
    // `state.value` is still null and this result would be clobbered anyway).
    // Page one of a fetch started before such a change must not roll it back.
    if (_discarded || _isFetching || !identical(state.value, served)) return;

    state = AsyncData(_mergeRevalidation(served, fresh));
    // Awaited, so a caller that waits for `revalidation` also knows the
    // snapshot on disk matches the list on screen.
    await persistSnapshot();
  }

  /// Stale-while-revalidate merge for the page-1 probe in [_revalidate].
  ///
  /// The probe asked for the first page only. When the network says there is no
  /// second page (`fresh.hasMore == false`) what it returned *is* the complete
  /// saved list, so it is authoritative and replaces the snapshot outright —
  /// anything the snapshot held beyond it was genuinely unsaved.
  ///
  /// When there is a second page, only the top of the list was confirmed. The
  /// served snapshot (a full walk from an earlier session) supplies everything
  /// beyond it: page 1 is prepended in the network's order, and snapshot items
  /// the network did not return are kept in their existing tail order — they
  /// may simply sit on a later page. Not walking every page on every app start
  /// is the point; the tail is confirmed when the user actually opens the list.
  ///
  /// Assumes [served] is fully materialized (`hasMore == false`) — the only
  /// case [_revalidate] is reached, since `buildSavedList` triggers it after
  /// `_readSnapshotPage`, which is always the entire persisted list.
  SpotubePaginationResponseObject<K> _mergeRevalidation(
    SpotubePaginationResponseObject<K> served,
    SpotubePaginationResponseObject<K> fresh,
  ) {
    if (!fresh.hasMore) return fresh;

    final freshKeys = fresh.items.map(_itemKey).toSet();
    final mergedItems = <K>[
      ...fresh.items,
      for (final item in served.items)
        if (!freshKeys.contains(_itemKey(item))) item,
    ];
    final total = mergedItems.length;
    return SpotubePaginationResponseObject<K>(
      limit: total,
      nextOffset: null,
      total: total,
      hasMore: false,
      items: mergedItems,
    );
  }
}
