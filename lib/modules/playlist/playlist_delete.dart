import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/dialogs/prompt_dialog.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

/// Confirms and deletes [playlistId], returning whether it was removed.
///
/// Deliberately never pops a route: the playlist header pops its own page
/// after this returns, while a card menu must not navigate anywhere.
Future<bool> deletePlaylistWithConfirmation(
  BuildContext context,
  T Function<T>(ProviderListenable<T> provider) read,
  String playlistId,
) async {
  final accepted = await showPromptDialog(
    context: context,
    title: context.l10n.delete_playlist,
    message: context.l10n.delete_playlist_confirmation,
    destructive: true,
  );
  if (!accepted || !context.mounted) return false;

  try {
    await read(metadataPluginSavedPlaylistsProvider.notifier)
        .delete(playlistId);
    // The playlist is gone: drop its mirror metadata and both order entries,
    // but never the audio files it shares with other collections.
    await read(playlistMirrorServiceProvider).forget(playlistId);
    read(userPreferencesProvider.notifier).removePlaylistFromOrders(playlistId);
    return true;
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
    if (context.mounted) {
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) => SurfaceCard(
          child: Text(context.l10n.something_went_wrong),
        ),
      );
    }
    return false;
  }
}
