import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/components/track_presentation/append_playback_tail.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/playlist/liked_playlist_synthetic.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/library/tracks.dart';
import 'package:spotube/provider/metadata_plugin/tracks/playlist.dart';
import 'package:spotube/provider/player/player_actions_service.dart';
import 'package:spotube/provider/voice/voice_config_provider.dart';
import 'package:spotube/services/voice/engine/voice_engine.dart';
import 'package:spotube/services/voice/matching/phrase_matcher.dart';
import 'package:spotube/services/voice/matching/text_normalizer.dart';

/// Where a spoken command needs a widget's context to go.
///
/// The executor deliberately stops at the app's state: it can set the search
/// term and load a queue without a [BuildContext], but changing the visible
/// page cannot happen without one, so it is reported back instead.
enum VoicePage {
  searchResults,
  queue,
}

/// What happened to a heard command.
class VoiceCommandReport {
  /// null when nothing ran: the transcript matched no command, or the command
  /// needs the user to pick between [playlistCandidates] first.
  final VoiceCommandId? command;

  final VoicePage? page;

  /// Names the listener said almost equally well; the UI asks, it does not guess.
  final List<SpotubeSimplePlaylistObject> playlistCandidates;

  /// The slot named something the library does not have.
  final bool notFound;

  const VoiceCommandReport({
    this.command,
    this.page,
    this.playlistCandidates = const [],
    this.notFound = false,
  });

  bool get understood => command != null || playlistCandidates.isNotEmpty;
}

/// Turns a [CommandHeardEvent] into app actions.
///
/// Split from [PlayerActionsService] because a spoken command carries more than
/// a verb: it carries a slot that has to be resolved against the user's own
/// library, and it can ask for things a theme never can (like, queue, search).
/// Split from the controller because the engine's job is audio; nothing in it
/// knows what "louder" means.
class VoiceExecutor {
  const VoiceExecutor(this.ref);

  final Ref ref;

  static const _matcher = PhraseMatcher();

  /// "louder" without a number, and "skip forward" without one: the steps the
  /// phrase defaults promise ("ten seconds forward").
  static const _volumeStep = 0.1;
  static const _seekStep = Duration(seconds: 10);

  VoiceLanguage get _language => ref.read(voiceConfigProvider).primaryLanguage;

  Future<VoiceCommandReport> execute(CommandHeardEvent event) async {
    // Test-phrase mode parses on purpose and must not touch the player.
    if (event.suppressed) return const VoiceCommandReport();
    final match = event.result.match;
    if (match == null) return const VoiceCommandReport();

    final actions = ref.read(playerActionsServiceProvider);
    switch (match.id) {
      case VoiceCommandId.play:
        await actions.resume();
      case VoiceCommandId.pause:
        await actions.pause();
      case VoiceCommandId.playPause:
        await actions.playPause();
      case VoiceCommandId.next:
        await actions.next();
      case VoiceCommandId.previous:
        await actions.previous();
      case VoiceCommandId.seekForward:
        await actions.seekBy(_seekStep);
      case VoiceCommandId.seekBackward:
        await actions.seekBy(-_seekStep);
      case VoiceCommandId.seekTo:
        final percent = _percent(match.slot);
        if (percent == null) return const VoiceCommandReport();
        await actions.seek({'fraction': percent / 100});
      case VoiceCommandId.volumeUp:
        await actions.setVolume({'delta': _volumeStep});
      case VoiceCommandId.volumeDown:
        await actions.setVolume({'delta': -_volumeStep});
      case VoiceCommandId.setVolume:
        final percent = _percent(match.slot);
        if (percent == null) return const VoiceCommandReport();
        await actions.setVolume({'volume': percent / 100});
      case VoiceCommandId.search:
        final term = match.slot?.trim();
        if (term == null || term.isEmpty) return const VoiceCommandReport();
        // The same two writes the search bar makes on Enter, so results and
        // recents do not depend on how the term arrived.
        ref.read(searchTermStateProvider.notifier).state = term;
        await ref.read(recentSearchesProvider.notifier).add(term);
        return const VoiceCommandReport(
          command: VoiceCommandId.search,
          page: VoicePage.searchResults,
        );
      case VoiceCommandId.playPlaylist:
        return await _playPlaylistByName(match.slot);
      case VoiceCommandId.like:
        await _setSaved(true);
      case VoiceCommandId.unlike:
        await _setSaved(false);
      case VoiceCommandId.addToQueue:
        final track = ref.read(audioPlayerProvider).activeTrack;
        if (track == null) return const VoiceCommandReport();
        await ref.read(audioPlayerProvider.notifier).addTrack(track);
      case VoiceCommandId.openQueue:
        return const VoiceCommandReport(
          command: VoiceCommandId.openQueue,
          page: VoicePage.queue,
        );
      case VoiceCommandId.stopListening:
        // The window belongs to the controller, which the wiring widget holds;
        // closing the microphone is not this service's state to touch.
        break;
    }
    return VoiceCommandReport(command: match.id);
  }

  /// Plays [playlist] from the chooser, or from the single confident match.
  Future<void> play(SpotubeSimplePlaylistObject playlist) async {
    final notifier = ref.read(audioPlayerProvider.notifier);
    // Already the loaded collection: resume it instead of restarting from the
    // first track, which would lose the user's place mid-album.
    if (ref.read(audioPlayerProvider).collections.contains(playlist.id)) {
      await ref.read(playerActionsServiceProvider).resume();
      return;
    }

    final isLikedSongs = playlist.id == likedTracksPlaylistId;
    final initial = isLikedSongs
        ? (await ref.read(metadataPluginSavedTracksProvider.future)).items
        : (await ref
                .read(metadataPluginPlaylistTracksProvider(playlist.id).future))
            .items;
    if (initial.isEmpty) return;

    await notifier.load(initial, autoPlay: true);
    notifier.addCollection(playlist.id);
    await ref.read(playbackHistoryActionsProvider).addPlaylists([playlist]);

    // The rest of the playlist arrives behind the first page, exactly as the
    // cover button in the search suggestions does it.
    unawaited(
      appendCollectionTail(
        appendTail: (tail) => notifier.addTracks(tail),
        readCollections: () => ref.read(audioPlayerProvider).collections,
        collectionId: playlist.id,
        alreadyLoaded: initial,
        fetchAll: () async {
          if (isLikedSongs) {
            return ref
                .read(metadataPluginSavedTracksProvider.notifier)
                .fetchAll();
          }
          return ref
              .read(metadataPluginPlaylistTracksProvider(playlist.id).notifier)
              .fetchAll();
        },
      ),
    );
  }

  Future<VoiceCommandReport> _playPlaylistByName(String? rawName) async {
    final name = rawName?.trim();
    if (name == null || name.isEmpty) return const VoiceCommandReport();

    // Awaited rather than read: the library is still loading right after
    // launch, and a command spoken then would otherwise be answered "no such
    // playlist" for a list the app has not fetched yet.
    final playlists =
        (await ref.read(metadataPluginSavedPlaylistsProvider.future)).items;
    if (playlists.isEmpty) {
      return const VoiceCommandReport(notFound: true);
    }

    final ranked = _matcher.rankNames(
      name,
      [for (final playlist in playlists) playlist.name],
      _language,
    );
    if (ranked.isEmpty) {
      return const VoiceCommandReport(notFound: true);
    }
    if (ranked.length > 1 &&
        _matcher.namesAreAmbiguous(
          ranked.first.score,
          ranked[1].score,
        )) {
      return VoiceCommandReport(
        playlistCandidates: [
          for (final candidate in ranked.take(3)) playlists[candidate.index],
        ],
      );
    }

    final playlist = playlists[ranked.first.index];
    await play(playlist);
    return const VoiceCommandReport(command: VoiceCommandId.playPlaylist);
  }

  /// Idempotent by direction: "like this" twice does not unlike the track,
  /// which [MetadataPluginSavedTracksNotifier.toggleFavorite] would do.
  Future<void> _setSaved(bool saved) async {
    final track = ref.read(audioPlayerProvider).activeTrack;
    if (track == null) return;
    final liked =
        await ref.read(metadataPluginIsSavedTrackProvider(track.id).future);
    if (liked == saved) return;
    final notifier = ref.read(metadataPluginSavedTracksProvider.notifier);
    if (saved) {
      await notifier.addFavorite([track]);
    } else {
      await notifier.removeFavorite([track]);
    }
  }

  static int? _percent(String? slot) {
    final value = int.tryParse(slot ?? '');
    if (value == null || value <= 0 || value > 100) return null;
    return value;
  }
}

final voiceExecutorProvider = Provider<VoiceExecutor>(
  (ref) => VoiceExecutor(ref),
);
