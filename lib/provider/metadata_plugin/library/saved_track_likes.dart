import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app's own answer to "is this track in Liked Songs?" for the tracks the
/// user touched during this session.
///
/// Spotify's library membership (`areEntitiesInLibrary`) is eventually
/// consistent: right after `addToLibrary` it can still report "not saved" for a
/// few seconds. The heart used to read that answer as its only truth, so the
/// first tap saved the song without changing the icon, and the second tap —
/// still reading "not saved" — saved it again and prepended a second row to the
/// local Liked Songs list.
///
/// This overlay is written the moment the user taps, so the icon and the next
/// toggle decision are instant. It survives for the session and is dropped on
/// the next launch, when the network answer is authoritative again.
class SavedTrackLikesNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String trackId, bool liked) {
    if (state[trackId] == liked) return;
    state = {...state, trackId: liked};
  }

  void clear(String trackId) {
    if (!state.containsKey(trackId)) return;
    final next = {...state}..remove(trackId);
    state = next;
  }
}

final savedTrackLikesProvider =
    NotifierProvider<SavedTrackLikesNotifier, Map<String, bool>>(
  SavedTrackLikesNotifier.new,
);
