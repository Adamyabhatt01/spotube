import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/common.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';

/// Family flavors of the shared pagination engine
/// ([PaginatedAsyncNotifierMixin]). The members were previously copy-pasted
/// here twice (~160 lines each); they now live once in the mixin, whose
/// `on AsyncNotifierBase<...>` constraint accepts family notifiers
/// (`FamilyAsyncNotifier`/`AutoDisposeFamilyAsyncNotifier` extend
/// `Buildless*AsyncNotifier` → `AsyncNotifierBase`).
///
/// [snapshotKey] defaults to null on the mixin, so the snapshot-persist path
/// (`persistSnapshot`/`scheduleSnapshotPersist`) stays a no-op for plain
/// paginated families — identical to the copies this file replaces, which
/// never touched the database. The dead non-autoDispose twin
/// (`FamilyPaginatedAsyncNotifier`) had zero references and was deleted.
abstract class AutoDisposeFamilyPaginatedAsyncNotifier<K, A>
    extends AutoDisposeFamilyAsyncNotifier<SpotubePaginationResponseObject<K>,
        A> with PaginatedAsyncNotifierMixin<K>, MetadataPluginMixin<K> {}
