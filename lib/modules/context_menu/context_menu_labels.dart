import 'package:flutter/widgets.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';

/// Resolves the l10n key a [ContextMenuActionTemplate] carries.
///
/// Kept as a switch rather than a dynamic lookup because Flutter's generated
/// localizations expose typed getters, not a map. Adding a host action means
/// adding its key here and in `app_en.arb`.
String contextMenuLabel(
  BuildContext context,
  String key, [
  Map<String, String>? args,
]) {
  final l10n = context.l10n;
  return switch (key) {
    'play' => l10n.play,
    'pause' => l10n.pause,
    'open' => l10n.open,
    'pin' => l10n.pin_to(args?['target'] ?? ''),
    'unpin' => l10n.unpin_from(args?['target'] ?? ''),
    'pin_to' => l10n.pin_to(args?['target'] ?? ''),
    'unpin_from' => l10n.unpin_from(args?['target'] ?? ''),
    'pin_to_ellipsis' => l10n.pin_to_ellipsis,
    'pin_to_sidebar' => l10n.pin_to_sidebar,
    'unpin_from_sidebar' => l10n.unpin_from_sidebar,
    'sidebar' => l10n.sidebar,
    'add_to_queue' => l10n.add_to_queue,
    'remove_from_queue' => l10n.remove_from_queue,
    'download' => l10n.download,
    'download_track' => l10n.download_track,
    'rename' => l10n.rename,
    'delete' => l10n.delete,
    'delete_playlist' => l10n.delete_playlist,
    'copy_link' => l10n.copy_link,
    'play_next' => l10n.play_next,
    'like' => l10n.like,
    'add_to_playlist' => l10n.add_to_playlist,
    'remove_from_playlist' => l10n.remove_from_playlist,
    'save_as_favorite' => l10n.save_as_favorite,
    'add_to_favorites' => l10n.add_to_favorites,
    'remove_from_favorites' => l10n.remove_from_favorites,
    'copy_stream_url' => l10n.copy_stream_url,
    'open_homepage' => l10n.open_homepage,
    'start_a_radio' => l10n.start_a_radio,
    'add_to_blacklist' => l10n.add_to_blacklist,
    'remove_from_blacklist' => l10n.remove_from_blacklist,
    'share' => l10n.share,
    'details' => l10n.details,
    'go_to_album' => l10n.go_to_album,
    'go_to_artist' => l10n.go_to_artist,
    'remove_download' => l10n.remove_download,
    'open_folder' => l10n.open_folder,
    _ => key,
  };
}

/// Maps the contract's icon token to a host icon.
///
/// A theme may name any token; an unknown one renders no leading icon instead
/// of failing the menu.
IconData? contextMenuIcon(String? name) {
  return switch (name) {
    'play' => SpotubeIcons.play,
    'pin' => SpotubeIcons.pinOn,
    'unpin' => SpotubeIcons.pinOff,
    'queue' => SpotubeIcons.queueAdd,
    'download' => SpotubeIcons.download,
    'rename' => SpotubeIcons.edit,
    'delete' => SpotubeIcons.trash,
    'link' => SpotubeIcons.clipboard,
    'like' => SpotubeIcons.heart,
    'likeFilled' => SpotubeIcons.heartFilled,
    'queueRemove' => SpotubeIcons.queueRemove,
    'playlistRemove' => SpotubeIcons.playlistRemove,
    'radio' => SpotubeIcons.radio,
    'share' => SpotubeIcons.share,
    'details' => SpotubeIcons.info,
    'next' => SpotubeIcons.skipForward,
    'playlist' => SpotubeIcons.playlistAdd,
    'album' => SpotubeIcons.album,
    'artist' => SpotubeIcons.artist,
    'open' => SpotubeIcons.open,
    'folder' => SpotubeIcons.folder,
    'remove' => SpotubeIcons.remove,
    _ => null,
  };
}

/// The labeler a widget passes to [ContextMenuBuilder].
ContextMenuLabeler contextMenuLabeler(BuildContext context) =>
    (key, [args]) => contextMenuLabel(context, key, args);
