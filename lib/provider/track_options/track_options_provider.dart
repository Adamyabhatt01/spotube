import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/dialogs/playlist_add_track_dialog.dart';
import 'package:spotube/components/dialogs/prompt_dialog.dart';
import 'package:spotube/components/dialogs/track_details_dialog.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';

enum TrackOptionValue {
  album,
  share,
  addToPlaylist,
  addToQueue,
  removeFromPlaylist,
  removeFromQueue,
  blacklist,
  delete,
  playNext,
  favorite,
  details,
  download,
  startRadio,
}

class TrackOptionsActions {
  final Ref ref;
  final SpotubeTrackObject track;

  TrackOptionsActions(this.ref, this.track);

  AudioPlayerNotifier get playback => ref.read(audioPlayerProvider.notifier);
  MetadataPluginSavedTracksNotifier get favoriteTracks =>
      ref.read(metadataPluginSavedTracksProvider.notifier);
  MetadataPluginSavedPlaylistsNotifier get favoritePlaylistsNotifier =>
      ref.read(metadataPluginSavedPlaylistsProvider.notifier);
  DownloadManagerNotifier get downloadManager =>
      ref.read(downloadManagerProvider.notifier);
  BlackListNotifier get blacklist => ref.read(blacklistProvider.notifier);

  void actionShare(BuildContext context) {
    Clipboard.setData(ClipboardData(text: track.externalUri)).then((_) {
      if (context.mounted) {
        showToast(
          context: rootNavigatorKey.currentContext!,
          location: ToastLocation.topRight,
          builder: (context, overlay) {
            return SurfaceCard(
              child: Text(
                context.l10n.copied_to_clipboard(track.externalUri),
                textAlign: TextAlign.center,
              ),
            );
          },
        );
      }
    });
  }

  Future<void> actionAddToPlaylist(
    BuildContext context,
    String? playlistId,
  ) async {
    await showDialog(
      context: context,
      builder: (context) {
        return PlaylistAddTrackDialog(
          tracks: [track],
          openFromPlaylist: playlistId,
        );
      },
    );
  }

  Future<void> actionStartRadio(BuildContext context) async {
    final playback = ref.read(audioPlayerProvider.notifier);
    final playlist = ref.read(audioPlayerProvider);
    final metadataPlugin = await ref.read(metadataPluginProvider.future);

    if (metadataPlugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }

    final tracks = await metadataPlugin.track.radio(track.id);

    bool replaceQueue = false;

    if (context.mounted && playlist.tracks.isNotEmpty) {
      replaceQueue = await showPromptDialog(
        context: context,
        title: context.l10n.how_to_start_radio,
        message: context.l10n.replace_queue_question,
        okText: context.l10n.replace,
        cancelText: context.l10n.add_to_queue,
      );
    }

    if (replaceQueue || playlist.tracks.isEmpty) {
      await playback.stop();
      await playback.load([track], autoPlay: true);

      return;
    } else {
      await playback.addTrack(track);
    }

    await playback.addTracks(
      tracks.toList()
        ..removeWhere((e) {
          final isDuplicate = playlist.tracks.any((t) => t.id == e.id);
          return e.id == track.id || isDuplicate;
        }),
    );
  }

  Future<void> action(
    BuildContext context,
    TrackOptionValue value,
    String? playlistId,
  ) async {
    switch (value) {
      case TrackOptionValue.album:
        await context.navigateTo(
          AlbumRoute(id: track.album.id, album: track.album),
        );
        break;
      case TrackOptionValue.delete:
        await File((track as SpotubeLocalTrackObject).path).delete();
        ref.invalidate(localTracksProvider);
        break;
      case TrackOptionValue.addToQueue:
        await playback.addTrack(track);
        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.added_track_to_queue(track.name),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.playNext:
        await playback.addTracksAtFirst([track]);

        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.track_will_play_next(track.name),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.removeFromQueue:
        playback.removeTrack(track.id);

        if (context.mounted) {
          showToast(
            context: context,
            location: ToastLocation.topRight,
            builder: (context, overlay) {
              return SurfaceCard(
                child: Text(
                  context.l10n.removed_track_from_queue(
                    track.name,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            },
          );
        }
        break;
      case TrackOptionValue.favorite:
        final isLikedTrack = await ref.read(
          metadataPluginIsSavedTrackProvider(track.id).future,
        );

        if (isLikedTrack) {
          await favoriteTracks.removeFavorite([track]);
        } else {
          await favoriteTracks.addFavorite([track]);
        }
        break;
      case TrackOptionValue.addToPlaylist:
        actionAddToPlaylist(context, playlistId);
        break;
      case TrackOptionValue.removeFromPlaylist:
        favoritePlaylistsNotifier.removeTracks(playlistId ?? "", [track.id]);
        break;
      case TrackOptionValue.blacklist:
        final isBlacklisted = blacklist.contains(track);
        if (isBlacklisted == true) {
          await ref.read(blacklistProvider.notifier).remove(track.id);
        } else {
          await ref.read(blacklistProvider.notifier).add(
                BlacklistTableCompanion.insert(
                  name: track.name,
                  elementId: track.id,
                  elementType: BlacklistedType.track,
                ),
              );
        }
        break;
      case TrackOptionValue.share:
        actionShare(context);
        break;
      case TrackOptionValue.details:
        if (track is! SpotubeFullTrackObject) break;
        showDialog(
          context: context,
          builder: (context) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: TrackDetailsDialog(track: track as SpotubeFullTrackObject),
          ),
        );
        break;
      case TrackOptionValue.download:
        if (track is SpotubeLocalTrackObject) break;
        downloadManager.addToQueue(
          track as SpotubeFullTrackObject,
          collectionId: playlistId,
        );
        break;
      case TrackOptionValue.startRadio:
        actionStartRadio(context);
        break;
    }
  }
}

typedef TrackOptionFlags = ({
  bool isInQueue,
  bool isBlacklisted,
  bool isInDownloadQueue,
  bool isDownloaded,
  bool isActiveTrack,
  bool isAuthenticated,
  bool isLiked,
  DownloadTask? downloadTask,
});

final trackOptionActionsProvider =
    Provider.autoDispose.family<TrackOptionsActions, SpotubeTrackObject>(
  (ref, track) => TrackOptionsActions(ref, track),
);

/// Auto-disposed on purpose: this is a `family` keyed by every track the user
/// ever opened a menu on, and a kept-alive instance stays subscribed to the
/// player, the download list and the blacklist table for the rest of the
/// session - recomputing an O(queue) scan per unseen row on every queue change.
final trackOptionsStateProvider =
    Provider.autoDispose.family<TrackOptionFlags, SpotubeTrackObject>((
  ref,
  track,
) {
  // Subscribe to consumed player slices only (see test/track_options_select_test.dart).
  final activeTrack =
      ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
  final queueTracks = ref.watch(audioPlayerProvider.select((s) => s.tracks));
  final authenticated = ref.watch(metadataPluginAuthenticatedProvider);
  final isSavedTrack = ref.watch(metadataPluginIsSavedTrackProvider(track.id));

  // Both lists are watched through a `select` that already applies this row's
  // predicate: watching them whole made every download-progress tick and every
  // blacklist write rebuild the menu state of every mounted row.
  final activeTrackId = activeTrack?.id;
  // This row's own transfer, keyed by this row's id rather than by whatever is
  // playing: the predicate is what keeps another track's progress tick from
  // rebuilding this menu, and keying on the row is what lets a download show
  // its progress on the row that started it.
  final downloadTask = ref.watch(downloadManagerProvider.select((tasks) {
    for (final task in tasks) {
      if (task.track.id == track.id) return task;
    }
    return null;
  }));

  final isBlacklisted = ref.watch(
    blacklistedIdsProvider.select(
      (ids) => BlackListNotifier.matches(ids, track),
    ),
  );

  // The record of this track's file, which is what survives a restart. The
  // in-memory task below is only ever a live view of the same work, so the
  // database answers "is this downloaded" and the task answers "how far along
  // is it" — the one question the rows cannot answer.
  final downloadState = track is SpotubeLocalTrackObject
      ? null
      : ref.watch(downloadStateOfProvider(track.id)).asData?.value;
  final isDownloaded =
      downloadState?.status == DownloadPersistedStatus.completed;

  final isInDownloadQueue = track is SpotubeLocalTrackObject
      ? false
      : downloadTask != null &&
              const [
                DownloadStatus.queued,
                DownloadStatus.downloading,
              ].contains(downloadTask.status) ||
          const [
            DownloadPersistedStatus.queued,
            DownloadPersistedStatus.downloading,
          ].contains(downloadState?.status);

  return (
    // Mirrors AudioPlayerState.containsTrack(track); kept inline so this
    // provider subscribes to `tracks` only instead of the full player state.
    isInQueue: queueTracks.isNotEmpty &&
        queueTracks.any(
          (t) =>
              t is SpotubeLocalTrackObject && track is SpotubeLocalTrackObject
                  ? t.path == track.path
                  : t.id == track.id,
        ),
    isBlacklisted: isBlacklisted,
    isInDownloadQueue: isInDownloadQueue,
    isDownloaded: isDownloaded,
    isActiveTrack: activeTrackId == track.id,
    isAuthenticated: authenticated.asData?.value ?? false,
    isLiked: isSavedTrack.asData?.value ?? false,
    downloadTask: downloadTask,
  );
});
