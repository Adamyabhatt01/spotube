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

  /// Persists the current state as the last-known-good list.
  ///
  /// A list that is still paging is persisted too, marked incomplete. It used
  /// to be skipped entirely, which meant a library with more playlists than
  /// fit on one page never got a snapshot at all — and a playlist created on
  /// another device was then invisible here not only for this session but
  /// for every later one, because the row it would have lived in was never
  /// written.
  ///
  /// Best-effort: cache failures are reported, never surfaced.
  Future<void> persistSnapshot() async {
    final key = snapshotKey;
    if (key == null) return;
    final value = state.value;
    if (value == null) return;
    try {
      await writeLibrarySnapshot(
        ref.read(databaseProvider),
        key,
        value.items,
        complete: !value.hasMore,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  /// Debounce window for [scheduleSnapshotPersist]. A snapshot write serializes
  /// and re-inserts the *entire* list, so an optimistic favorite must not pay
  /// for one per click.
  @visibleForTesting
  static const snapshotPersistDebounce = Duration(seconds: 2);

  Timer? _snapshotPersistTimer;

  /// Coalesces bursty snapshot requests (optimistic favorite/unfavorite
  /// toggles, page-walk completions) into one trailing [persistSnapshot].
  /// Intermediate states are not worth their full-list write; the final one
  /// is, and it reflects `state` as it is when the timer fires. A provider
  /// disposed inside the window loses the pending write — never the
  /// correctness of what is already on disk.
  void scheduleSnapshotPersist() {
    if (snapshotKey == null) return;
    _snapshotPersistTimer?.cancel();
    _snapshotPersistTimer = Timer(snapshotPersistDebounce, () {
      _snapshotPersistTimer = null;
      unawaited(persistSnapshot());
    });
    ref.onDispose(() {
      _snapshotPersistTimer?.cancel();
      _snapshotPersistTimer = null;
    });
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
    // Fresh network rows win over copies already on screen. A saved playlist
    // carries a cover URL that Spotify regenerates when its tracks change, so
    // keeping the old row for a duplicated id left that card on a stale cover
    // forever: paging in the same playlist again silently changed nothing.
    final fresh = {for (final item in newItems) _itemKey(item): item};
    final merged = <K>[
      for (final item in oldItems) fresh.remove(_itemKey(item)) ?? item,
    ];
    merged.addAll(fresh.values);
    return merged;
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
      scheduleSnapshotPersist();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      state = AsyncData(oldState!);
    } finally {
      _isFetching = false;
    }
  }

  /// Upper bound on pages walked by [fetchAll]. A healthy library needs
  /// a handful of pages (10k items at 100/page = 100); a plugin that keeps
  /// answering `hasMore: true` forever would otherwise loop without end.
  /// Measured: a rogue `hasMore:true` source walked 50 pages and was still
  /// `hasMore` (see `test/perf_audit_measure_test.dart`). On hitting the cap
  /// the collected items are finalized rather than discarded.
  @visibleForTesting
  static const fetchAllMaxPages = 200;

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
      var pagesWalked = 0;
      var capped = false;

      while (hasMore) {
        if (pagesWalked >= fetchAllMaxPages) {
          AppLogger.reportError(
            StateError(
              'fetchAll stopped after $fetchAllMaxPages pages '
              '(rogue hasMore:true); finalizing partial list',
            ),
            StackTrace.current,
          );
          capped = true;
          break;
        }
        pagesWalked++;
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

      // A capped walk is final by construction: if `hasMore` stayed true the
      // list would advertise another page that this method refuses to fetch,
      // so callers would keep re-entering it.
      state = AsyncData(lastPage.copyWith(
        items: allItems,
        hasMore: capped ? false : lastPage.hasMore,
        nextOffset: capped ? null : lastPage.nextOffset,
      ));
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

  /// Whether a warm build re-walks the whole list instead of probing page one.
  ///
  /// Opted in by the saved-playlists list: its items carry a cover URL that
  /// Spotify regenerates when the playlist's tracks change, and confirming
  /// only page one leaves every playlist past it on last session's cover
  /// until the user scrolls to that page.
  ///
  /// It also decides how deep a manual [refresh] goes. The playlists list
  /// needs every page there for a second reason: Spotify *appends* a newly
  /// created playlist to the end of the library, so a page-one probe cannot
  /// see it — which is exactly the row a second device is missing.
  bool get refreshAllPages => false;

  /// Set while a manual [refresh] is in flight. Separate from [_isFetching]
  /// (which guards the page walk) so the two cannot starve each other.
  bool _refreshing = false;

  /// Whether the last [refresh] was thrown away because the list was
  /// rebuilt while it ran.
  ///
  /// A rebuild disposes the notifier the re-read was running on, and the
  /// result goes with it — but the rebuilt list is the current one, so the
  /// re-read is simply done again. This is what tells the caller that.
  bool get lastRefreshWasDiscarded => _lastRefreshWasDiscarded;
  bool _lastRefreshWasDiscarded = false;

  /// The library size the plugin last reported.
  ///
  /// The plugin's own count, which is not necessarily the number of rows the
  /// list holds — it is the number the library says it has. Comparing two
  /// of *its* answers is how a re-read knows the library moved; comparing it
  /// with the row count would read a difference that is not one.
  int? _reportedTotal;

  /// The persisted list as a complete page, or null when there is no usable
  /// snapshot. A failing cache is simply no cache.
  Future<SpotubePaginationResponseObject<K>?> _readSnapshotPage() async {
    final key = snapshotKey;
    final decoder = snapshotDecoder;
    if (key == null || decoder == null) return null;

    final LibrarySnapshot<K>? snapshot;
    try {
      snapshot = await readLibrarySnapshot(
        ref.read(databaseProvider),
        key,
        decoder,
      );
    } catch (_) {
      // A failing cache is simply no cache; the blocking fetch follows and
      // surfaces whatever error is worth seeing.
      return null;
    }
    if (snapshot == null || snapshot.items.isEmpty) return null;

    final items = snapshot.items;

    return SpotubePaginationResponseObject(
      limit: items.length,
      // An incomplete snapshot is a prefix of the library, not the library:
      // say so, so the page keeps paging instead of claiming one page is
      // everything the account has.
      nextOffset: snapshot.complete ? null : items.length,
      total: items.length,
      hasMore: !snapshot.complete,
      items: items,
    );
  }

  /// Lets the framework publish the build's own result before the list is
  /// compared against it.
  ///
  /// The framework assigns `state` after `build()` returns, which is one
  /// microtask later than the revalidation's first suspension point. Without
  /// this yield a revalidation that resolved in the same microtask batch
  /// compared against a `state.value` that was still null, concluded the
  /// list had "moved", and threw its fresh result away — silently, because
  /// that early return has no log.
  Future<void> _awaitBuildDelivery() => Future<void>.delayed(Duration.zero);

  /// Walks every page of the saved list from the network and returns the
  /// items in order.
  ///
  /// Independent of the current state: it starts at offset 0 every time, so
  /// it also works for a list that was served from a snapshot (which claims
  /// to be complete and would otherwise stop a walk before it started).
  Future<List<K>> _walkAllPages({
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    final walked = <K>[];
    final seen = <String>{};
    // Fixed page size: the served snapshot's limit is the whole snapshot
    // length, and asking the plugin for one page that large is not a
    // paginated request.
    var offset = 0;
    var limit = 20;
    var pages = 0;

    while (true) {
      if (pages >= PaginatedAsyncNotifierMixin.fetchAllMaxPages) break;
      pages++;
      final page = await fetchWithRateLimitRetry(
        () => fetch(offset, limit),
        cooldown: cooldown,
      );
      _reportedTotal = page.total;
      for (final item in page.items) {
        if (seen.add(_itemKey(item))) walked.add(item);
      }
      if (!page.hasMore) break;
      // A page that claims there is more but does not say where is a
      // contract violation: fail loudly instead of looping forever.
      final next = page.nextOffset;
      if (next == null) break;
      offset = next;
      if (page.limit > 0) limit = page.limit;
    }

    return walked;
  }

  /// Re-reads the saved list from the network and replaces what is on
  /// screen.
  ///
  /// This is the "the library changed on another device" path. The saved
  /// lists are read once per app session — their build serves the disk
  /// snapshot and revalidates behind it — so without an explicit re-read a
  /// playlist created on a phone never reaches a desktop that has been open
  /// since before. The re-read is what makes the two devices agree.
  ///
  /// The list on screen stays until the network answers, and a failed re-read
  /// leaves it untouched: it is last-known-good data, and an error replacing
  /// it would be a worse trade than a stale list.
  ///
  /// It costs one request in the common case. A page-one probe says whether
  /// the library changed at all — its total moved, or it carries a row the
  /// list never had — and only then are the remaining pages worth reading.
  /// [forceFullWalk] skips that shortcut, for the caller that needs the
  /// *whole* list rather than the news.
  ///
  /// Returns the rows the re-read settled on, or null when it failed and the
  /// previous list was kept. The null is what lets a caller tell "the network
  /// says this is not there" from "we could not ask" — two very different
  /// answers.
  Future<List<K>?> refresh({bool forceFullWalk = false}) async {
    _lastRefreshWasDiscarded = false;

    if (_refreshing) {
      AppLogger.logEvent(
        '[library] $snapshotKey: re-read skipped (one is already running)',
      );
      return null;
    }
    _refreshing = true;

    // The list as it was when the request went out. A write that lands
    // while the network is busy owns its own rows.
    final before = state.value;

    try {
      // The size the library had *before* this request went out. The probe
      // below reports the current one; comparing the two is how a re-read
      // knows the library moved.
      final previousTotal = _reportedTotal;

      final probe = await fetchWithRateLimitRetry(() => fetch(0, 20));
      _reportedTotal = probe.total;

      final List<K> networkItems;
      final bool complete;

      if (!probe.hasMore) {
        // The probe answered the whole library.
        networkItems = probe.items.cast<K>();
        complete = true;
      } else if (refreshAllPages &&
          (forceFullWalk ||
              _libraryChanged(probe, before, previousTotal))) {
        // The library changed, and the row that changed may sit past the
        // first page: Spotify appends a new playlist to the *end* of the
        // library, so the rest has to be read too.
        networkItems = await _walkAllPages();
        complete = true;
      } else {
        networkItems = probe.items.cast<K>();
        complete = false;
      }

      // Let the framework publish the build's own result before the list is
      // compared against it.
      await _awaitBuildDelivery();
      if (_discarded) {
        _lastRefreshWasDiscarded = true;
        AppLogger.logEvent(
          '[library] $snapshotKey: re-read discarded (the list was rebuilt)',
        );
        return null;
      }

      // The list as it is now. A write that landed while the network was
      // busy owns its own rows; the network's answer supplies the rest.
      final current = state.value;
      final moved = before != null && !identical(current, before);

      final networkKeys = networkItems.map(_itemKey).toSet();
      final items = <K>[
        ...networkItems,
        // A complete answer is authoritative: everything it did not name was
        // unsaved. An incomplete one only spoke for the head, so the tail the
        // list already holds survives it.
        if (!complete || moved)
          for (final item in current?.items ?? <K>[])
            if (!networkKeys.contains(_itemKey(item))) item,
      ];

      final page = SpotubePaginationResponseObject<K>(
        limit: probe.limit,
        nextOffset: complete ? null : probe.nextOffset,
        total: probe.total,
        hasMore: !complete,
        items: items,
      );

      state = AsyncData(page);
      await persistSnapshot();

      // A record of what the re-read found. The log file otherwise only
      // receives error reports, so a re-read that silently did nothing —
      // or one that quietly found nothing because the network could not be
      // asked — left no trace at all.
      final beforeIds = before?.items.map(_itemKey).toSet() ?? const <String>{};
      final added = items.where((i) => !beforeIds.contains(_itemKey(i))).length;
      AppLogger.logEvent(
        '[library] $snapshotKey: ${items.length} rows, $added new, '
        'complete=${page.hasMore == false}',
      );

      return page.items.cast<K>();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      AppLogger.logEvent(
        '[library] $snapshotKey: re-read FAILED — $e',
      );
      return null;
    } finally {
      _refreshing = false;
    }
  }

  /// Whether the probe says the library changed since the list was last
  /// read.
  ///
  /// Two independent signals, because either one alone can miss a change:
  /// the total the plugin reports is the library's size, so a row added at
  /// the *end* moves it; and a row added at the *head* shows up in the
  /// probe's own rows. A library that grew, or that carries a row the list
  /// never had, is worth reading the rest of the pages for.
  ///
  /// A list that was never finished reading counts as changed whatever the
  /// total says: its tail was never fetched, so the probe cannot vouch for
  /// it.
  bool _libraryChanged(
    SpotubePaginationResponseObject<K> probe,
    SpotubePaginationResponseObject<K>? before,
    int? previousTotal,
  ) {
    if (before == null) return true;
    if (before.hasMore) return true;

    if (previousTotal != null && probe.total != previousTotal) return true;

    final known = before.items.map(_itemKey).toSet();
    return probe.items.any((item) => !known.contains(_itemKey(item)));
  }

  /// Re-reads the saved list from the network and returns the ids it holds.
  ///
  /// Null means the network could not be asked. That is not the same answer
  /// as "the row is not in the list", and a caller has to be able to tell the
  /// two apart: the first means "leave it alone", the second means "put it
  /// there".
  ///
  /// The whole list is read, not just its head: "is this row in the list?"
  /// cannot be answered from the first page when the row was appended to the
  /// end.
  Future<Set<String>?> refreshIds() async {
    final items = await refresh(forceFullWalk: true);
    if (items == null) return null;

    final ids = <String>{};
    for (final item in items) {
      final dynamic dynamicItem = item;
      try {
        final id = dynamicItem.id;
        if (id != null) ids.add(id.toString());
      } on NoSuchMethodError catch (_) {
        // item type has no id field
      }
    }
    return ids;
  }

  Future<SpotubePaginationResponseObject<K>> buildSavedList({
    Duration cooldown = rateLimitRetryCooldown,
  }) async {
    // A build that is replaced fires its own `onDispose` callbacks, so the
    // flag has to be cleared for the build that replaces it.
    //
    // Left latched, the instance was "discarded" for the rest of its life
    // after the second build — and every re-read on it was thrown away, at
    // the very moment it had the answer. The list was re-read over and over
    // and never took the answer, which is why a playlist created on another
    // device never arrived.
    _discarded = false;

    final cached = await _readSnapshotPage();
    if (cached != null) {
      ref.onDispose(() => _discarded = true);
      // Deliberately not awaited: completing this build is what puts the list
      // on screen, and the refresh result arrives through `state` instead.
      _revalidating ??= (refreshAllPages
              ? _revalidateAll(cooldown, cached)
              : _revalidate(cooldown, cached))
          .whenComplete(() {
        _revalidating = null;
      });
      return cached;
    }

    final page = await fetchWithRateLimitRetry(
      () => fetch(0, 20),
      cooldown: cooldown,
    );
    _reportedTotal = page.total;
    // Cache the page once the burst window closes. A list that is still
    // paging is cached too, marked incomplete: it is what this device
    // actually knows, and without it a library with more rows than fit on
    // one page never had a snapshot at all.
    scheduleSnapshotPersist();
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
    _reportedTotal = fresh.total;

    // Anything that already moved the list owns it: an optimistic favorite, a
    // page walk, or a build that has not delivered [served] yet (then
    // `state.value` is still null and this result would be clobbered anyway).
    // Page one of a fetch started before such a change must not roll it back.
    await _awaitBuildDelivery();
    if (_discarded || _isFetching || !identical(state.value, served)) return;

    state = AsyncData(_mergeRevalidation(served, fresh));
    // Awaited, so a caller that waits for `revalidation` also knows the
    // snapshot on disk matches the list on screen.
    await persistSnapshot();
  }

  /// Re-walks every page behind a served snapshot, replacing each row with
  /// the network's copy. Used by the [refreshAllPages] lists.
  ///
  /// Best-effort like [_revalidate]: any failing page abandons the walk and
  /// leaves the last-known-good list on screen. The walk never blocks the
  /// build — the snapshot is already being displayed while it runs.
  Future<void> _revalidateAll(
    Duration cooldown,
    SpotubePaginationResponseObject<K> served,
  ) async {
    final List<K> walked;
    try {
      walked = await _walkAllPages(cooldown: cooldown);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return;
    }

    // A plugin that answered every page with nothing must not erase a list
    // that is currently on screen and usable.
    if (walked.isEmpty) return;

    // Anything that already moved the list owns it: an optimistic favorite, a
    // page walk, or a build that has not delivered [served] yet.
    await _awaitBuildDelivery();
    if (_discarded || _isFetching || !identical(state.value, served)) return;

    // Rows the walk did not return (a playlist created while it ran, an
    // optimistic addition) stay at the tail instead of vanishing — but only
    // when the served snapshot was a complete walk. A partial snapshot's
    // rows are the first pages of an older ordering, which overlap the
    // pages the walk just read; keeping them would resurrect rows the walk
    // has already replaced.
    final walkedKeys = walked.map(_itemKey).toSet();
    final items = <K>[
      ...walked,
      if (!served.hasMore)
        for (final item in served.items)
          if (!walkedKeys.contains(_itemKey(item))) item,
    ];
    final total = items.length;
    state = AsyncData(
      SpotubePaginationResponseObject<K>(
        limit: total,
        nextOffset: null,
        total: total,
        hasMore: false,
        items: items,
      ),
    );
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
  /// A *partial* served snapshot cannot supply a tail: its rows are pages 1..k
  /// of an older ordering, and page 1 of the new ordering overlaps them. Only
  /// the probe's own page survives; the rest is paged in again from the
  /// network's own offset.
  SpotubePaginationResponseObject<K> _mergeRevalidation(
    SpotubePaginationResponseObject<K> served,
    SpotubePaginationResponseObject<K> fresh,
  ) {
    if (!fresh.hasMore) return fresh;

    if (served.hasMore) return fresh;

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
