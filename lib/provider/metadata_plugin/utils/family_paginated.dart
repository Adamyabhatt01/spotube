import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/services/logger/logger.dart';

abstract class FamilyPaginatedAsyncNotifier<K, A>
    extends FamilyAsyncNotifier<SpotubePaginationResponseObject<K>, A>
    with MetadataPluginMixin<K> {
  Future<SpotubePaginationResponseObject<K>> fetch(int offset, int limit);

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
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      state = AsyncData(oldState!);
    } finally {
      _isFetching = false;
    }
  }

  Future<List<K>> fetchAll() async {
    if (_isFetching) return state.asData?.value.items.cast<K>() ?? [];
    if (state.value == null) return [];
    if (!state.value!.hasMore) return state.value!.items.cast<K>();

    _isFetching = true;
    try {
      bool hasMore = true;
      while (hasMore) {
        final newState = await fetch(
          state.value!.nextOffset!,
          max(state.value!.limit, 100),
        )
            .catchError(
              (e) =>
                  fetch(state.value!.nextOffset!, max(state.value!.limit, 50)),
            )
            .catchError(
              (e) => fetch(state.value!.nextOffset!, state.value!.limit),
            )
            .catchError(
          (e) async {
            await Future.delayed(const Duration(milliseconds: 500));
            return fetch(state.value!.nextOffset!, state.value!.limit);
          },
        );

        hasMore = newState.hasMore;

        final oldItems =
            state.value!.items.isEmpty ? <K>[] : state.value!.items.cast<K>();
        final items = newState.items.isEmpty ? <K>[] : newState.items.cast<K>();

        state = AsyncData(
          newState.copyWith(items: _mergeDeduped(oldItems, items)),
        );
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    } finally {
      _isFetching = false;
    }

    return state.value!.items.cast<K>();
  }
}

abstract class AutoDisposeFamilyPaginatedAsyncNotifier<K, A>
    extends AutoDisposeFamilyAsyncNotifier<SpotubePaginationResponseObject<K>,
        A> with MetadataPluginMixin<K> {
  Future<SpotubePaginationResponseObject<K>> fetch(int offset, int limit);

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
      state = AsyncLoadingNext(state.value!);

      final newState = await fetch(
        state.value!.nextOffset!,
        state.value!.limit,
      );

      state = AsyncData(
        newState.copyWith(
          items: _mergeDeduped(
            state.value!.items.cast<K>(),
            newState.items.cast<K>(),
          ),
        ),
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      state = AsyncData(oldState!);
    } finally {
      _isFetching = false;
    }
  }

  Future<List<K>> fetchAll() async {
    if (_isFetching) return state.asData?.value.items.cast<K>() ?? [];
    if (state.value == null) return [];
    if (!state.value!.hasMore) return state.value!.items.cast<K>();

    _isFetching = true;
    try {
      bool hasMore = true;
      while (hasMore) {
        final newState = await fetch(
          state.value!.nextOffset!,
          max(state.value!.limit, 100),
        )
            .catchError(
              (e) =>
                  fetch(state.value!.nextOffset!, max(state.value!.limit, 50)),
            )
            .catchError(
              (e) => fetch(state.value!.nextOffset!, state.value!.limit),
            )
            .catchError(
          (e) async {
            await Future.delayed(const Duration(milliseconds: 500));
            return fetch(state.value!.nextOffset!, state.value!.limit);
          },
        );

        hasMore = newState.hasMore;

        state = AsyncData(
          newState.copyWith(
            items: _mergeDeduped(
              state.value!.items.cast<K>(),
              newState.items.cast<K>(),
            ),
          ),
        );
      }
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    } finally {
      _isFetching = false;
    }

    return state.value!.items.cast<K>();
  }
}
