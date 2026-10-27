import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/components/button/back_button.dart';
import 'package:spotube/components/track_presentation/presentation_list.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/presentation_top.dart';
import 'package:spotube/components/track_presentation/presentation_modifiers.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/utils/platform.dart';

class TrackPresentation extends HookConsumerWidget {
  final TrackPresentationOptions options;
  const TrackPresentation({
    super.key,
    required this.options,
  });

  @override
  Widget build(BuildContext context, ref) {
    final scrollController = useScrollController();
    final focusNode = useFocusNode();
    final scale = context.theme.scaling;

    useEffect(() {
      if (!kIsMobile) return null;
      void listener() {
        if (!scrollController.hasClients) return;

        if (focusNode.hasFocus) {
          scrollController.animateTo(
            300 * scale,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }

      focusNode.addListener(listener);
      return () {
        focusNode.removeListener(listener);
      };
    }, [focusNode, scrollController, scale]);

    final collection = options.collection;
    final releaseYear = collection is SpotubeSimpleAlbumObject
        ? (collection.releaseDate ?? '').split('-').first
        : '';
    final totalDuration = Duration(
      milliseconds: options.tracks.fold<int>(
        0,
        (total, track) => total + track.durationMs,
      ),
    );

    final pageBindings = <String, Object?>{
      'collection.id': options.collectionId,
      'collection.kind': options.kind,
      'collection.title': options.title,
      'collection.description': options.description ?? '',
      'collection.owner': options.owner ?? '',
      'collection.ownerImage': options.ownerImage ?? '',
      'collection.artwork': options.image,
      'collection.route': options.routePath,
      'collection.share': options.shareUrl ?? '',
      'collection.liked': options.isLiked,
      'collection.tracks': options.tracks,
      'collection.trackCount': options.tracks.length,
      'collection.year': releaseYear,
      'collection.duration': _formatCollectionDuration(totalDuration),
    };
    final hasHeader = themeUiSlotExists(ref, 'collection.header');
    final hasBeforeTracks = themeUiSlotExists(ref, 'collection.before_tracks');
    final hasAfterTracks = themeUiSlotExists(ref, 'collection.after_tracks');

    return Data<TrackPresentationOptions>.inherit(
      data: options,
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          // All three call sites (album, playlist, liked-tracks) are
          // pushed routes, never tab roots — back always has somewhere
          // to go. Matches ArtistPage's TitleBar precedent.
          headers: const [
            TitleBar(
              leading: [BackButton()],
            )
          ],
          child: ThemePageContent(
            slot: 'collection.content',
            bindings: pageBindings,
            fallback: CustomScrollView(
              controller: scrollController,
              slivers: [
                if (hasHeader)
                  const SliverToBoxAdapter(
                    child: ThemeSlot('collection.header'),
                  )
                else
                  const TrackPresentationTopSection(),
                const SliverGap(16),
                SliverList.list(
                  children: [
                    TrackPresentationModifiersSection(
                      focusNode: focusNode,
                    ),
                    LayoutBuilder(builder: (context, constrains) {
                      return Basic(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        leading: constrains.mdAndUp ? const Text("  #") : null,
                        title: Row(
                          children: [
                            Expanded(
                              flex: constrains.lgAndUp ? 5 : 6,
                              child: Text(context.l10n.title),
                            ),
                            if (constrains.mdAndUp)
                              Expanded(
                                flex: 3,
                                child: Text(context.l10n.album),
                              ),
                            Text(context.l10n.duration),
                          ],
                        ),
                      ).small().muted();
                    }),
                  ],
                ),
                if (hasBeforeTracks)
                  const SliverToBoxAdapter(
                    child: ThemeSlot('collection.before_tracks'),
                  ),
                const PresentationListSection(),
                if (hasAfterTracks)
                  const SliverToBoxAdapter(
                    child: ThemeSlot('collection.after_tracks'),
                  ),
                const SliverSafeArea(sliver: SliverGap(10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Human-readable total for a collection header.
///
/// Albums read "20 min 27 sec" on Spotify; longer playlists drop the seconds
/// and read "24 hr 3 min". The host formats it once so every theme gets the
/// same wording and does not have to do arithmetic in the node tree.
String _formatCollectionDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds <= 0) return '';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) return '$hours hr $minutes min';
  if (minutes > 0) return '$minutes min $seconds sec';
  return '$seconds sec';
}
