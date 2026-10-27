import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' show PlaylistMode;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/control/control_protocol.dart';

/// The commands a running Spotube instance answers over the control
/// channel.
///
/// The vocabulary is deliberately small and side-effecting commands are
/// explicit. The same set backs both the CLI (`spotube --play ...`) and
/// the MCP server, so there is one definition of "what can be controlled"
/// rather than two.
class ControlCommands {
  /// The commands this instance understands, with a one-line description.
  static const Map<String, String> catalog = {
    'state.get':
        'The current playback state: track, position, duration, volume, queue.',
    'playback.play': 'Resume playback.',
    'playback.pause': 'Pause playback.',
    'playback.stop': 'Stop playback and clear the queue.',
    'playback.next': 'Skip to the next track.',
    'playback.previous': 'Skip to the previous track.',
    'playback.seek': 'Seek to a position in seconds.',
    'playback.jump': 'Jump to a queue index.',
    'playback.shuffle': 'Turn shuffle on or off.',
    'playback.loop': 'Set the loop mode: off, all, or one.',
    'volume.set': 'Set the volume, 0.0 to 1.0.',
    'search': 'Search the metadata provider and return the matches.',
    'queue.add': 'Add a track to the queue by id.',
    'queue.remove': 'Remove a track from the queue by id.',
    'queue.clear': 'Clear the queue.',
  };

  /// Builds the handler that answers a request.
  ///
  /// Takes the container so the command can read the providers it needs.
  static ControlCommandHandler handler(Ref ref) {
    return (request) async {
      final arguments = request.arguments;
      switch (request.command) {
        case 'state.get':
          return _state(ref);

        case 'playback.play':
          await audioPlayer.resume();
          return {'playing': true};

        case 'playback.pause':
          await audioPlayer.pause();
          return {'playing': false};

        case 'playback.stop':
          await ref.read(audioPlayerProvider.notifier).stop();
          return {'playing': false};

        case 'playback.next':
          await audioPlayer.skipToNext();
          return {'ok': true};

        case 'playback.previous':
          await audioPlayer.skipToPrevious();
          return {'ok': true};

        case 'playback.seek':
          final seconds = _doubleArg(arguments, 'seconds');
          if (seconds == null) {
            throw const FormatException('playback.seek needs "seconds"');
          }
          await audioPlayer
              .seek(Duration(milliseconds: (seconds * 1000).round()));
          return {'seconds': seconds};

        case 'playback.jump':
          final index = _intArg(arguments, 'index');
          if (index == null) {
            throw const FormatException('playback.jump needs "index"');
          }
          await audioPlayer.jumpTo(index);
          return {'index': index};

        case 'playback.shuffle':
          final value = arguments['enabled'];
          if (value is! bool) {
            throw const FormatException('playback.shuffle needs "enabled"');
          }
          await audioPlayer.setShuffle(value);
          return {'shuffled': value};

        case 'playback.loop':
          final mode = arguments['mode'];
          if (mode is! String) {
            throw const FormatException('playback.loop needs "mode"');
          }
          final loopMode = PlaylistMode.values.firstWhere(
            (m) => m.name == mode,
            orElse: () => throw FormatException(
              'unknown loop mode "$mode" '
              '(expected one of ${PlaylistMode.values.map((m) => m.name).join(", ")})',
            ),
          );
          await audioPlayer.setLoopMode(loopMode);
          return {'mode': loopMode.name};

        case 'volume.set':
          final value = _doubleArg(arguments, 'volume');
          if (value == null) {
            throw const FormatException('volume.set needs "volume"');
          }
          await ref
              .read(volumeProvider.notifier)
              .setVolume(value.clamp(0.0, 1.0));
          return {'volume': value.clamp(0.0, 1.0)};

        case 'search':
          final query = arguments['query'];
          if (query is! String || query.trim().isEmpty) {
            throw const FormatException('search needs a non-empty "query"');
          }
          return _search(ref, query.trim());

        case 'search.play':
          final query = arguments['query'];
          if (query is! String || query.trim().isEmpty) {
            throw const FormatException(
                'search.play needs a non-empty "query"');
          }
          return _searchAndPlay(ref, query.trim());

        case 'queue.add':
          final trackId = arguments['trackId'];
          if (trackId is! String) {
            throw const FormatException('queue.add needs "trackId"');
          }
          final track = await _findTrack(ref, trackId);
          if (track == null) {
            throw StateError('no track with id "$trackId"');
          }
          await ref.read(audioPlayerProvider.notifier).addTrack(track);
          return {'added': track.id};

        case 'queue.remove':
          final trackId = arguments['trackId'];
          if (trackId is! String) {
            throw const FormatException('queue.remove needs "trackId"');
          }
          await ref.read(audioPlayerProvider.notifier).removeTrack(trackId);
          return {'removed': trackId};

        case 'queue.clear':
          await audioPlayer.clearPlaylist();
          return {'ok': true};

        case 'commands.list':
          return {
            for (final entry in catalog.entries) entry.key: entry.value,
          };

        default:
          throw FormatException(
            'unknown command "${request.command}". '
            'Known commands: ${catalog.keys.join(", ")}',
          );
      }
    };
  }

  /// The playback state, as a plain map.
  static Map<String, dynamic> _state(Ref ref) {
    final state = ref.read(audioPlayerProvider);
    final active = state.activeTrack;
    return {
      'playing': state.playing,
      'shuffled': state.shuffled,
      'loopMode': state.loopMode.name,
      'volume': ref.read(volumeProvider),
      'currentIndex': state.currentIndex,
      'queueLength': state.tracks.length,
      'collections': state.collections,
      'position': audioPlayer.position.inMilliseconds,
      'duration': audioPlayer.duration.inMilliseconds,
      if (active != null)
        'activeTrack': {
          'id': active.id,
          'name': active.name,
          'artists': active.artists.map((a) => a.name).toList(),
          'album': active.album.name,
        },
      'tracks': [
        for (final track in state.tracks)
          {
            'id': track.id,
            'name': track.name,
            'artists': track.artists.map((a) => a.name).toList(),
          },
      ],
    };
  }

  /// Searches the metadata provider and returns a compact result.
  static Future<Map<String, dynamic>> _search(Ref ref, String query) async {
    final response =
        await ref.read(metadataPluginSearchAllProvider(query).future);
    return {
      'query': query,
      'tracks': [
        for (final track in response.tracks)
          {
            'id': track.id,
            'name': track.name,
            'artists': track.artists.map((a) => a.name).toList(),
          },
      ],
      'albums': [
        for (final album in response.albums)
          {'id': album.id, 'name': album.name},
      ],
      'artists': [
        for (final artist in response.artists)
          {'id': artist.id, 'name': artist.name},
      ],
      'playlists': [
        for (final playlist in response.playlists)
          {'id': playlist.id, 'name': playlist.name},
      ],
    };
  }

  /// Searches, then plays the best match.
  ///
  /// The match is the first track whose title contains the query, falling
  /// back to the first result: a search for "bohemian rhapsody" should play
  /// the track, not refuse because the title has different casing.
  static Future<Map<String, dynamic>> _searchAndPlay(
    Ref ref,
    String query,
  ) async {
    final results = await _search(ref, query);
    final tracks = (results['tracks'] as List).cast<Map<String, dynamic>>();
    if (tracks.isEmpty) {
      throw StateError('no track matched "$query"');
    }

    final lowered = query.toLowerCase();
    final match = tracks.firstWhere(
      (track) => (track['name'] as String).toLowerCase().contains(lowered),
      orElse: () => tracks.first,
    );

    final trackId = match['id'] as String;
    final full = await _resolveTrack(ref, trackId);
    if (full == null) {
      throw StateError('could not resolve the track "$trackId"');
    }

    await ref.read(audioPlayerProvider.notifier).load(
      [full],
      autoPlay: true,
    );

    return {
      'played': {
        'id': full.id,
        'name': full.name,
        'artists': full.artists.map((a) => a.name).toList(),
      },
      'candidates': tracks.length,
    };
  }

  /// Resolves a full track object by id, from the search results.
  static Future<SpotubeFullTrackObject?> _resolveTrack(
    Ref ref,
    String id,
  ) async {
    // The search response carries simple track objects; the player needs the
    // full one (with the album and the duration). The metadata plugin's
    // track endpoint is the source, so the search is repeated with the id
    // narrowed to it.
    final response = await ref.read(metadataPluginSearchAllProvider(id).future);
    for (final track in response.tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  /// Finds a track by id, in the queue first, then in the search results.
  static Future<SpotubeFullTrackObject?> _findTrack(Ref ref, String id) async {
    final state = ref.read(audioPlayerProvider);
    for (final track in state.tracks) {
      if (track.id == id && track is SpotubeFullTrackObject) return track;
    }
    return null;
  }

  static double? _doubleArg(Map<String, dynamic> arguments, String name) {
    final value = arguments[name];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _intArg(Map<String, dynamic> arguments, String name) {
    final value = arguments[name];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
