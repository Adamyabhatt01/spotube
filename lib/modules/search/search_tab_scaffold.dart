import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/fallbacks/error_box.dart';
import 'package:spotube/components/fallbacks/no_default_metadata_plugin.dart';
import 'package:spotube/modules/search/loading.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

/// Shared error/loading branch for the five search tabs (`all`, `tracks`,
/// `albums`, `artists`, `playlists`).
///
/// Takes the watched [AsyncValue] rather than a provider, so it fits both
/// shapes in this surface: the plain `FutureProvider` behind the All tab and
/// the four paginated notifiers with their own `fetchMore` strategies, which
/// genuinely differ and stay in the tab files. Each tab supplies its
/// snapshot, its retry invalidation and its layout; empty states stay with
/// the layout too.
class SearchTabScaffold extends ConsumerWidget {
  final AsyncValue snapshot;
  final void Function() onRetry;
  final Widget child;

  const SearchTabScaffold({
    super.key,
    required this.snapshot,
    required this.onRetry,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.error
        case MetadataPluginException(
          errorCode: MetadataPluginErrorCode.noDefaultMetadataPlugin,
          message: _
        )) {
      return const NoDefaultMetadataPlugin();
    }

    if (snapshot.hasError) {
      return ErrorBox(
        error: snapshot.error!,
        onRetry: onRetry,
      );
    }

    return SearchPlaceholder(
      snapshot: snapshot,
      child: child,
    );
  }
}
