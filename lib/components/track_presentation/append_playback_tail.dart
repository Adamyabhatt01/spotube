import 'dart:async';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';

/// Streams the pages not yet on screen into the queue once the walk finishes,
/// provided the collection is still the one loaded. Called fire-and-forget
/// after an initial `playlistNotifier.load(page1, autoPlay: true)`, so audio
/// starts on the tap and the tail lands in the background — never blocking
/// the caller's spinner on a full paginated walk.
///
/// The tail is `all.sublist(alreadyLoaded.length)`, matching the notifier's
/// own append-per-page semantics (state.items then later pages). If the walk
/// throws, or the collection was replaced by then, or the caller's widget
/// has torn down (making [readCollections] throw), the tail is dropped and
/// the error is reported — never silent, but never fatal: the user is
/// already listening to page 1.
Future<void> appendCollectionTail({
  required Future<void> Function(Iterable<SpotubeFullTrackObject> tail)
      appendTail,
  required List<String> Function() readCollections,
  required String collectionId,
  required List<SpotubeFullTrackObject> alreadyLoaded,
  required Future<List<SpotubeFullTrackObject>> Function() fetchAll,
}) async {
  try {
    final all = await fetchAll();
    if (all.length <= alreadyLoaded.length) return;
    if (!readCollections().contains(collectionId)) return;
    await appendTail(all.sublist(alreadyLoaded.length));
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
  }
}
