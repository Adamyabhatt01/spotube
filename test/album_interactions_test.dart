// An album card's cover is a navigation target, not a play/pause toggle.
//
// Playlist cards and the sidebar already follow that split: the cover and
// label open the collection, and the explicit play button is the only direct
// playback action. Album cards used to map the cover to `onPlaybuttonPressed`,
// so on touch (where no hover reveals the separate play button) tapping the
// artwork started or paused playback instead of opening the album.
//
// `AlbumCard` therefore passes no `onCoverPressed` to either presentation.
// Asserted at the source level because mounting an AlbumCard needs the full
// metadata-plugin stack, and the widget-level contract is already covered by
// `playlist_interactions_test.dart`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('album cards do not map the cover to playback', () {
    final source = File('lib/modules/album/album_card.dart').readAsStringSync();

    expect(
      source,
      contains('onTap: onTap,'),
      reason: 'the card and tile covers stay part of the navigation target',
    );
    expect(
      source,
      isNot(contains('onCoverPressed:')),
      reason: 'explicit play is the only direct-play action on an album',
    );
  });
}
