import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/metadata/metadata.dart';

import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Resources owned by a single WebSocket client connection.
///
/// Everything registered here (stream listeners and the provider
/// listener) is torn down when the socket closes, so a disconnected
/// client never keeps receiving — or writing to a closed sink —
/// forever. Sending is guarded by [closed] because `WebSocketSink.add`
/// throws once the sink is closed.
class _ConnectionResources {
  final WebSocketChannel _channel;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  ProviderSubscription? _queueSubscription;
  bool closed = false;

  _ConnectionResources(this._channel);

  void addEvent(WebSocketEvent event) {
    if (closed) return;
    try {
      _channel.sink.add(event.toJson());
    } catch (_) {
      // The socket died between the closed check and the write.
      // Teardown follows via the message stream's onDone/onError.
    }
  }

  void listen<T>(
    Stream<T> stream,
    void Function(T event) onData, {
    void Function()? onDone,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (closed) return;
    _subscriptions.add(stream.listen(
      onData,
      onDone: onDone,
      onError: onError ??
          (Object e, StackTrace stack) => AppLogger.reportError(e, stack),
    ));
  }

  Future<void> dispose() async {
    if (closed) return;
    closed = true;
    _queueSubscription?.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

class ServerConnectRoutes {
  final Ref ref;
  final StreamController<String> _connectClientStreamController;
  ServerConnectRoutes(this.ref)
      : _connectClientStreamController = StreamController<String>.broadcast() {
    ref.onDispose(() {
      _connectClientStreamController.close();
      // Safety net: normally every connection tears itself down when its
      // socket closes; if the provider is disposed while a client is
      // still connected, release those resources here.
      for (final connection in _activeConnections) {
        connection.dispose();
      }
    });
  }

  final Set<_ConnectionResources> _activeConnections = {};

  /// Number of connected WebSocket clients with live resources.
  /// Test seam: lets tests assert that closing a socket actually
  /// releases that connection's listeners.
  @visibleForTesting
  int get activeConnectionCount => _activeConnections.length;

  AudioPlayerNotifier get audioPlayerNotifier =>
      ref.read(audioPlayerProvider.notifier);
  PlaybackHistoryActions get historyNotifier =>
      ref.read(playbackHistoryActionsProvider);
  Stream<String> get connectClientStream =>
      _connectClientStreamController.stream;

  /// Origins that approved the pairing dialog for their CURRENT socket.
  /// Entries are removed when the socket closes: the key includes the
  /// ephemeral remote port, so retained entries are dead weight whose
  /// host:port could later be reused by a different machine.
  final List<String> _allowedConnections = [];

  FutureOr<Response> websocket(Request req) {
    return webSocketHandler(
      (
        WebSocketChannel channel,
        String? protocol,
      ) async {
        final context =
            (req.context["shelf.io.connection_info"] as HttpConnectionInfo?);
        final origin = "${context?.remoteAddress.host}:${context?.remotePort}";
        _connectClientStreamController.add(origin);

        // Confirm whether user allows to connect
        if (_allowedConnections.contains(origin) == false) {
          final dialogContext = rootNavigatorKey.currentContext;
          if (dialogContext == null || !dialogContext.mounted) {
            // Fail closed: without UI to pair, an unapproved client must
            // not receive playback control. (Previously the missing
            // context silently skipped the approval check entirely.)
            try {
              channel.sink.add(
                WebSocketErrorEvent("Connection denied").toJson(),
              );
              await channel.sink.close();
            } catch (_) {
              // Sink already dead — nothing left to reject.
            }
            return;
          }
          final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (context) {
                  return AlertDialog(
                    title: Text(context.l10n.connect),
                    content: Text(
                      context.l10n.connect_request(origin),
                    ),
                    actions: [
                      Button.secondary(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                        },
                        child: Text(context.l10n.decline),
                      ),
                      Button.primary(
                        onPressed: () {
                          Navigator.of(context).pop(true);
                        },
                        child: Text(context.l10n.accept),
                      ),
                    ],
                  );
                },
              ) ??
              false;

          if (confirmed) {
            _allowedConnections.add(origin);
          } else {
            channel.sink.add(
              WebSocketErrorEvent("Connection denied").toJson(),
            );
            await channel.sink.close();
            return;
          }
        }

        final connectionResources = _ConnectionResources(channel);
        _activeConnections.add(connectionResources);

        void cleanupConnection() {
          // Prune the pairing grant with the socket it belongs to, keeping
          // _allowedConnections bounded by the number of live connections.
          _allowedConnections.remove(origin);
          if (_activeConnections.remove(connectionResources)) {
            unawaited(connectionResources.dispose());
          }
        }

        // The queue payload is only read for its membership — `tracks`,
        // `currentIndex`, `collections` (see the client in
        // provider/connect/connect.dart, which keeps separate providers for
        // play state, position, duration, shuffle, loop and volume, all sent
        // below). Re-encoding the whole queue for a change the client cannot
        // see in it costs a full jsonEncode per track change per client, and
        // PR 3 made `tracks` identity stable across those changes.
        AudioPlayerState? lastSentQueue;
        connectionResources._queueSubscription = ref.listen(
          audioPlayerProvider,
          (previous, next) {
            PerfCounters.note('connect.queueNotification');
            if (isSameQueuePayload(lastSentQueue, next)) return;
            lastSentQueue = next;
            PerfCounters.note('connect.queueEvent');
            connectionResources.addEvent(WebSocketQueueEvent(next));
          },
          fireImmediately: true,
        );

        // AudioPlayer state events don't fire on subscribe.
        connectionResources
            .addEvent(WebSocketPlayingEvent(audioPlayer.isPlaying));
        connectionResources.addEvent(
          WebSocketPositionEvent(audioPlayer.position),
        );
        connectionResources.addEvent(
          WebSocketDurationEvent(audioPlayer.duration),
        );
        connectionResources
            .addEvent(WebSocketShuffleEvent(audioPlayer.isShuffled));
        connectionResources.addEvent(WebSocketLoopEvent(audioPlayer.loopMode));
        connectionResources.addEvent(WebSocketVolumeEvent(audioPlayer.volume));

        connectionResources.listen(
          // ~1 Hz instead of the raw ~5 Hz, and one less payload to encode per
          // second per client. The host's own progress bar already moves on
          // these ticks, and a seek forces one immediately.
          audioPlayer.positionTickStream,
          (position) {
            connectionResources.addEvent(WebSocketPositionEvent(position));
          },
        );
        connectionResources.listen(
          audioPlayer.playingStream,
          (playing) {
            connectionResources.addEvent(WebSocketPlayingEvent(playing));
          },
        );
        connectionResources.listen(
          audioPlayer.durationStream,
          (duration) {
            connectionResources.addEvent(WebSocketDurationEvent(duration));
          },
        );
        connectionResources.listen(
          audioPlayer.shuffledStream,
          (shuffled) {
            connectionResources.addEvent(WebSocketShuffleEvent(shuffled));
          },
        );
        connectionResources.listen(
          audioPlayer.loopModeStream,
          (loopMode) {
            connectionResources.addEvent(WebSocketLoopEvent(loopMode));
          },
        );
        connectionResources.listen(
          audioPlayer.volumeStream,
          (volume) {
            connectionResources.addEvent(WebSocketVolumeEvent(volume));
          },
        );
        connectionResources.listen(
          channel.stream,
          (message) async {
            try {
              final event = WebSocketEvent.fromJson(
                jsonDecode(message),
                (data) => data,
              );

              event.onLoad((event) async {
                await audioPlayerNotifier.load(
                  event.data.tracks.cast<SpotubeFullTrackObject>().toList(),
                  autoPlay: true,
                  initialIndex: event.data.initialIndex ?? 0,
                );

                if (event.data.collectionId == null) return;
                audioPlayerNotifier.addCollection(event.data.collectionId!);
                if (event.data.collection is SpotubeSimpleAlbumObject) {
                  historyNotifier.addAlbums(
                      [event.data.collection as SpotubeSimpleAlbumObject]);
                } else {
                  historyNotifier.addPlaylists(
                      [event.data.collection as SpotubeSimplePlaylistObject]);
                }
              });

              event.onPause((event) async {
                await audioPlayer.pause();
              });

              event.onResume((event) async {
                await audioPlayer.resume();
              });

              event.onStop((event) async {
                await ref.read(audioPlayerProvider.notifier).stop();
              });

              event.onNext((event) async {
                await audioPlayer.skipToNext();
              });

              event.onPrevious((event) async {
                await audioPlayer.skipToPrevious();
              });

              event.onJump((event) async {
                await audioPlayer.jumpTo(event.data);
              });

              event.onSeek((event) async {
                await audioPlayer.seek(event.data);
              });

              event.onShuffle((event) async {
                await audioPlayer.setShuffle(event.data);
              });

              event.onLoop((event) async {
                await audioPlayer.setLoopMode(event.data);
              });

              event.onAddTrack((event) async {
                await audioPlayerNotifier.addTrack(event.data);
              });

              event.onRemoveTrack((event) async {
                await audioPlayerNotifier.removeTrack(event.data);
              });

              event.onReorder((event) async {
                await audioPlayerNotifier.moveTrack(
                  event.data.oldIndex,
                  event.data.newIndex,
                );
              });

              event.onVolume((event) async {
                ref.read(volumeProvider.notifier).setVolume(event.data);
              });
            } catch (e, stackTrace) {
              AppLogger.reportError(e, stackTrace);
              connectionResources
                  .addEvent(WebSocketErrorEvent(e.toString()));
            }
          },
          // Socket lifecycle: disconnect or wire error releases every
          // resource this connection registered above.
          onDone: cleanupConnection,
          onError: (e, stack) {
            AppLogger.reportError(e, stack);
            cleanupConnection();
          },
        );
      },
    )(req);
  }
}

final serverConnectRoutesProvider = Provider((ref) => ServerConnectRoutes(ref));

/// Whether [next] carries queue membership the client has not been sent yet.
///
/// `==` on these lists is the cheap check it looks like, not a deep one: freezed
/// hands out `tracks`/`collections` wrapped in `EqualUnmodifiableListView`,
/// whose `==` compares the *backing list* by identity. So two states built by
/// `copyWith` (which passes the existing list straight through) compare equal,
/// while any mutation that installs a new list compares different — and equal
/// content in a new list still compares different, which only ever costs a send
/// that had to happen anyway.
///
/// Membership is all the client reads out of this payload (see
/// `provider/connect/connect.dart`, which keeps separate providers for play
/// state, position, duration, shuffle, loop and volume, all sent separately),
/// plus `currentIndex`, which selects the active track.
bool isSameQueuePayload(AudioPlayerState? sent, AudioPlayerState next) {
  if (sent == null) return false;
  return sent.tracks == next.tracks &&
      sent.collections == next.collections &&
      sent.currentIndex == next.currentIndex;
}
