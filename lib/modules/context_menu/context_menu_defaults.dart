import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';

/// One host-owned action in a target's default table.
///
/// Labels are l10n keys resolved by the renderer, so the table stays pure and
/// testable. Adding an action is one entry here plus one callback in the host
/// widget that owns the target.
class ContextMenuActionTemplate {
  final String id;
  final String labelKey;
  final Map<String, String> labelArgs;
  final String? icon;
  final String? when;
  final bool destructive;
  final ContextMenuSubmenu submenu;

  /// State-sensitive label: the first flag that reads true swaps the key.
  /// This is how a `play` row becomes `Pause` while audio is sounding.
  final Map<String, String> labelKeys;

  /// State-sensitive icon, looked up by the same rule as [labelKeys].
  final Map<String, String> iconKeys;

  const ContextMenuActionTemplate({
    required this.id,
    required this.labelKey,
    this.labelArgs = const {},
    this.icon,
    this.when,
    this.destructive = false,
    this.submenu = ContextMenuSubmenu.none,
    this.labelKeys = const {},
    this.iconKeys = const {},
  });
}

/// The single host defaults table. Every context menu is built from this, so
/// adding an action cannot drift between playlist cards, rows and pages.
const contextMenuDefaults =
    <ContextMenuTarget, List<ContextMenuActionTemplate>>{
  ContextMenuTarget.playlist: [
    ContextMenuActionTemplate(
      id: 'play',
      labelKey: 'play',
      icon: 'play',
      labelKeys: {'playing': 'pause'},
      iconKeys: {'playing': 'pause'},
    ),
    ContextMenuActionTemplate(
      id: 'open',
      labelKey: 'open',
      icon: 'open',
    ),
    ContextMenuActionTemplate(
      id: 'pin',
      labelKey: 'pin',
      icon: 'pin',
      submenu: ContextMenuSubmenu.pinTargets,
    ),
    ContextMenuActionTemplate(
      id: 'unpin',
      labelKey: 'unpin',
      icon: 'unpin',
      when: 'item.pinned == true',
    ),
    ContextMenuActionTemplate(
      id: 'addToQueue',
      labelKey: 'add_to_queue',
      icon: 'queue',
    ),
    ContextMenuActionTemplate(
      id: 'download',
      labelKey: 'download',
      icon: 'download',
    ),
    ContextMenuActionTemplate(
      id: 'rename',
      labelKey: 'rename',
      icon: 'rename',
      when: 'item.owner == true',
    ),
    ContextMenuActionTemplate(
      id: 'delete',
      labelKey: 'delete_playlist',
      icon: 'delete',
      when: 'item.owner == true',
      destructive: true,
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.track: [
    ContextMenuActionTemplate(
      id: 'playNext',
      labelKey: 'play_next',
      icon: 'next',
    ),
    ContextMenuActionTemplate(
      id: 'addToQueue',
      labelKey: 'add_to_queue',
      icon: 'queue',
      when: 'item.inQueue == false',
    ),
    ContextMenuActionTemplate(
      id: 'removeFromQueue',
      labelKey: 'remove_from_queue',
      icon: 'queueRemove',
      when: 'item.inQueue == true',
    ),
    ContextMenuActionTemplate(
      id: 'like',
      labelKey: 'save_as_favorite',
      icon: 'like',
      labelKeys: {'liked': 'remove_from_favorites'},
      iconKeys: {'liked': 'likeFilled'},
    ),
    ContextMenuActionTemplate(
      id: 'download',
      labelKey: 'download_track',
      icon: 'download',
    ),
    ContextMenuActionTemplate(
      id: 'addToPlaylist',
      labelKey: 'add_to_playlist',
      icon: 'playlist',
      submenu: ContextMenuSubmenu.playlists,
    ),
    ContextMenuActionTemplate(
      id: 'removeFromPlaylist',
      labelKey: 'remove_from_playlist',
      icon: 'playlistRemove',
      when: 'item.userPlaylist == true',
    ),
    ContextMenuActionTemplate(
      id: 'goToAlbum',
      labelKey: 'go_to_album',
      icon: 'album',
    ),
    ContextMenuActionTemplate(
      id: 'goToArtist',
      labelKey: 'go_to_artist',
      icon: 'artist',
    ),
    ContextMenuActionTemplate(
      id: 'startRadio',
      labelKey: 'start_a_radio',
      icon: 'radio',
    ),
    ContextMenuActionTemplate(
      id: 'blacklist',
      labelKey: 'add_to_blacklist',
      icon: 'playlistRemove',
      labelKeys: {'blacklisted': 'remove_from_blacklist'},
    ),
    ContextMenuActionTemplate(
      id: 'delete',
      labelKey: 'delete',
      icon: 'delete',
      when: 'item.local == true',
      destructive: true,
    ),
    ContextMenuActionTemplate(
      id: 'share',
      labelKey: 'share',
      icon: 'share',
    ),
    ContextMenuActionTemplate(
      id: 'details',
      labelKey: 'details',
      icon: 'details',
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.album: [
    ContextMenuActionTemplate(id: 'play', labelKey: 'play', icon: 'play'),
    ContextMenuActionTemplate(
      id: 'addToQueue',
      labelKey: 'add_to_queue',
      icon: 'queue',
    ),
    ContextMenuActionTemplate(
      id: 'download',
      labelKey: 'download',
      icon: 'download',
    ),
    ContextMenuActionTemplate(
      id: 'goToArtist',
      labelKey: 'go_to_artist',
      icon: 'artist',
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.artist: [
    ContextMenuActionTemplate(id: 'play', labelKey: 'play', icon: 'play'),
    ContextMenuActionTemplate(
      id: 'addToQueue',
      labelKey: 'add_to_queue',
      icon: 'queue',
    ),
    ContextMenuActionTemplate(
      id: 'download',
      labelKey: 'download',
      icon: 'download',
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.queueItem: [
    ContextMenuActionTemplate(id: 'play', labelKey: 'play', icon: 'play'),
    ContextMenuActionTemplate(
      id: 'removeFromQueue',
      labelKey: 'remove_from_queue',
      icon: 'remove',
      destructive: true,
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.download: [
    ContextMenuActionTemplate(id: 'play', labelKey: 'play', icon: 'play'),
    ContextMenuActionTemplate(
      id: 'openFolder',
      labelKey: 'open_folder',
      icon: 'folder',
      when: 'item.completed == true',
    ),
    ContextMenuActionTemplate(
      id: 'removeDownload',
      labelKey: 'remove_download',
      icon: 'remove',
      when: 'item.completed == true',
      destructive: true,
    ),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.searchResult: [
    ContextMenuActionTemplate(id: 'play', labelKey: 'play', icon: 'play'),
    ContextMenuActionTemplate(
      id: 'addToQueue',
      labelKey: 'add_to_queue',
      icon: 'queue',
    ),
    ContextMenuActionTemplate(
      id: 'download',
      labelKey: 'download',
      icon: 'download',
    ),
    ContextMenuActionTemplate(id: 'open', labelKey: 'open', icon: 'open'),
    ContextMenuActionTemplate(
      id: 'copyLink',
      labelKey: 'copy_link',
      icon: 'link',
    ),
  ],
  ContextMenuTarget.radio: [
    ContextMenuActionTemplate(
      id: 'playPause',
      labelKey: 'play',
      icon: 'play',
      labelKeys: {'playing': 'pause'},
      iconKeys: {'playing': 'pause'},
    ),
    ContextMenuActionTemplate(
      id: 'favorite',
      labelKey: 'add_to_favorites',
      icon: 'like',
      labelKeys: {'favorited': 'remove_from_favorites'},
      iconKeys: {'favorited': 'likeFilled'},
    ),
    ContextMenuActionTemplate(
      // Not the shared `pin` id: that one opens the pin-target submenu, while
      // a station pin is a single fixed sidebar toggle.
      id: 'pinStation',
      labelKey: 'pin_to_sidebar',
      icon: 'pin',
      labelKeys: {'pinned': 'unpin_from_sidebar'},
      iconKeys: {'pinned': 'unpin'},
    ),
    ContextMenuActionTemplate(
      id: 'copyStreamUrl',
      labelKey: 'copy_stream_url',
      icon: 'link',
    ),
    ContextMenuActionTemplate(
      id: 'openHomepage',
      labelKey: 'open_homepage',
      icon: 'open',
      when: 'item.hasHomepage == true',
    ),
  ],
};
