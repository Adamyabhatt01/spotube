import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/saved_track_likes.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';

typedef UseTrackToggleLike = ({
  bool isLiked,
  bool isLoading,
  bool hasLocalState,
  Future<void> Function(SpotubeTrackObject track) toggleTrackLike,
});

UseTrackToggleLike useTrackToggleLike(SpotubeTrackObject track, WidgetRef ref) {
  final savedTracksNotifier =
      ref.watch(metadataPluginSavedTracksProvider.notifier);

  final isSavedTrack = ref.watch(metadataPluginIsSavedTrackProvider(track.id));
  // A tap this session knows better than a query that may still be catching
  // up with the last write, so it also unlocks the button while the saved
  // list itself is still loading.
  final hasLocalState = ref.watch(
    savedTrackLikesProvider.select((likes) => likes.containsKey(track.id)),
  );

  return (
    isLiked: isSavedTrack.asData?.value ?? false,
    isLoading: isSavedTrack.isLoading,
    hasLocalState: hasLocalState,
    toggleTrackLike: savedTracksNotifier.toggleFavorite,
  );
}
