import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/fake.dart';
import 'package:spotube/components/fallbacks/not_found.dart';
import 'package:spotube/components/playbutton_view/playbutton_view.dart';
import 'package:spotube/modules/album/album_card.dart';
import 'package:spotube/modules/search/search_tab_scaffold.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/metadata_plugin/search/albums.dart';

class SearchPageAlbumsTab extends HookConsumerWidget {
  const SearchPageAlbumsTab({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final controller = useScrollController();

    final searchTerm = ref.watch(searchTermStateProvider);
    final searchAlbumsSnapshot =
        ref.watch(metadataPluginSearchAlbumsProvider(searchTerm));
    final searchAlbumsNotifier =
        ref.read(metadataPluginSearchAlbumsProvider(searchTerm).notifier);
    final searchAlbums =
        searchAlbumsSnapshot.asData?.value.items ?? [FakeData.albumSimple];

    return SearchTabScaffold(
      snapshot: searchAlbumsSnapshot,
      onRetry: () {
        ref.invalidate(metadataPluginSearchAlbumsProvider(searchTerm));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: searchAlbumsSnapshot.hasValue &&
                searchAlbumsSnapshot.asData?.value.items.isEmpty == true
            ? const Center(child: NotFound())
            : CustomScrollView(
          slivers: [
            PlaybuttonView(
              controller: controller,
              itemCount: searchAlbums.length,
              hasMore: searchAlbumsSnapshot.asData?.value.hasMore == true,
              isLoading: searchAlbumsSnapshot.isLoading,
              onRequestMore: searchAlbumsNotifier.fetchMore,
              gridItemBuilder: (context, index) =>
                  AlbumCard(searchAlbums[index]),
              listItemBuilder: (context, index) =>
                  AlbumCard.tile(searchAlbums[index]),
            ),
          ],
        ),
      ),
    );
  }
}
