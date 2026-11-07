// Tapping a track row must start playback on the tapped song.
//
// The rows render `PresentationState.presentationTracks`, which the sort
// dropdown and the track filter reorder relative to the collection's own
// order — and the queue is loaded in that collection order (the tail-append in
// `appendCollectionTail` counts on it). So the visible row number is not a
// queue position: `useTrackTilePlayCallback` used to forward it as
// `initialIndex`, and a sorted or filtered list opened the wrong song.

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_presentation/presentation_state.dart';
import 'package:spotube/components/track_presentation/use_track_tile_play_callback.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/models/sort.dart' show SortBy;
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart'
    show SpotubeMedia;
import 'package:spotube/services/sourced_track/sourced_track.dart';

/// Records what the player was asked to open and never touches media_kit.
class _RecordingPlayerNotifier extends AudioPlayerNotifier {
  final List<String> backendCalls = [];
  List<Media> medias = const [];

  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        currentIndex: 0,
        tracks: const [],
      );

  @override
  List<Media> get backendMedias => medias;

  @override
  int get backendCurrentIndex => 0;

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {}

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {}

  @override
  Future<void> removeMediaFromBackend(int index) async {}

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {
    backendCalls.add('open:$initialIndex:${medias.length}');
    this.medias = List<Media>.of(medias);
  }
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

/// `load` warms the intended track's audio source through
/// [sourcedTrackProvider], which needs the whole plugin stack; the result is
/// discarded either way, so park it on a pending future.
class _HangingSourcedTrackNotifier extends SourcedTrackNotifier {
  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) =>
      Completer<SourcedTrack>().future;
}

/// No mDNS in tests: an errored clients provider makes `showSelectDeviceDialog`
/// answer "this device", which is the branch that loads a local queue.
class _NoRemoteDevicesNotifier extends ConnectClientsNotifier {
  @override
  Future<ConnectClientsState> build() async =>
      throw StateError('no remote devices in tests');
}

/// One resolved remote device, so the tap callback asks which device to use.
class _OneRemoteDeviceNotifier extends ConnectClientsNotifier {
  @override
  Future<ConnectClientsState> build() async => ConnectClientsState(
        services: const [],
        discovery: null,
        resolvedService: const BonsoirService.ignoreNorms(
          name: 'Remote Phone',
          type: '_spotube._tcp',
          port: 9999,
        ),
      );
}

/// Records the websocket messages the callback sends to the remote device.
class _RecordingConnectNotifier extends ConnectNotifier {
  final List<int> jumps = [];
  final List<WebSocketLoadEventData> loads = [];

  @override
  Future<ConnectState?> build() async => null;

  @override
  Future<void> jumpTo(int position) async {
    jumps.add(position);
  }

  @override
  Future<void> load(WebSocketLoadEventData data) async {
    loads.add(data);
  }
}

/// The presentation state a page holds after the sort dropdown or the filter
/// moved rows around.
class _StubPresentationNotifier extends PresentationStateNotifier {
  _StubPresentationNotifier(this.displayed, this.sortBy);

  final List<SpotubeTrackObject> displayed;
  final SortBy sortBy;

  @override
  PresentationState build(Object arg) => PresentationState(
        selectedTracks: const [],
        presentationTracks: displayed,
        sortBy: sortBy,
      );
}

class _TapHolder {
  Future<void> Function(SpotubeTrackObject track)? callback;
}

/// Mounts the hook under the `Data` the real pages provide and hands the
/// resulting callback out to the test.
class _Harness extends HookConsumerWidget {
  const _Harness({required this.holder});

  final _TapHolder holder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    holder.callback = useTrackTilePlayCallback(ref);
    return const SizedBox.shrink();
  }
}

SpotubeFullTrackObject _track(String id, String name) {
  return SpotubeFullTrackObject(
    id: id,
    name: name,
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'artist-$id',
        name: 'Artist $name',
        externalUri: 'https://example.test/artist/$id',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'album-$id',
      name: 'Album $name',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST$id',
    explicit: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final playlist = SpotubeSimplePlaylistObject(
    id: 'pl-1',
    name: 'Playlist',
    description: '',
    externalUri: 'https://example.test/playlist/pl-1',
    owner: SpotubeUserObject(id: 'owner', name: 'Owner', externalUri: ''),
  );

  /// The collection in its own order — the order the queue loads in.
  final source = [
    _track('alpha', 'Alpha'),
    _track('bravo', 'Bravo'),
    _track('charlie', 'Charlie'),
  ];

  late AppDatabase database;
  late _RecordingPlayerNotifier player;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.into(database.audioPlayerStateTable).insert(
          AudioPlayerStateTableCompanion.insert(
            playing: false,
            loopMode: PlaylistMode.none,
            shuffled: false,
            collections: const [],
            tracks: const Value(<SpotubeTrackObject>[]),
            currentIndex: const Value(0),
            id: const Value(0),
          ),
        );
    player = _RecordingPlayerNotifier();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> tapTrack(
    WidgetTester tester,
    SpotubeTrackObject track, {
    required List<SpotubeTrackObject> displayed,
    SortBy sortBy = SortBy.none,
    List<SpotubeTrackObject>? queueTracks,
    List<String> queueCollections = const [],
  }) async {
    final holder = _TapHolder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWith(() => player),
          databaseProvider.overrideWithValue(database),
          blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
          connectClientsProvider.overrideWith(() => _NoRemoteDevicesNotifier()),
          sourcedTrackProvider
              .overrideWith(() => _HangingSourcedTrackNotifier()),
          // `load` waits for the playback-server port before building remote
          // URIs; these tests never touch the network, so supply one instead
          // of binding a real loopback server (and needing its logger).
          playbackServerPortProvider.overrideWith((ref) async => 21999),
          presentationStateProvider
              .overrideWith(() => _StubPresentationNotifier(displayed, sortBy)),
        ],
        child: Data<TrackPresentationOptions>.inherit(
          data: TrackPresentationOptions(
            collection: playlist,
            title: playlist.name,
            image: '',
            routePath: '/playlist/${playlist.id}',
            tracks: source,
            pagination: PaginationProps(
              hasNextPage: false,
              isLoading: false,
              onFetchMore: () {},
              onRefresh: () async {},
              onFetchAll: () async => source,
            ),
          ),
          child: _Harness(holder: holder),
        ),
      ),
    );

    if (queueTracks != null) {
      player.state = AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: queueCollections,
        tracks: queueTracks,
        currentIndex: 0,
      );
      // Let the harness see the active-collection state before the tap.
      await tester.pump();
    }

    await holder.callback!(track);
    await tester.pump();
  }

  /// Taps a row with a remote device selected and answers the device dialog.
  Future<_RecordingConnectNotifier> tapRemoteTrack(
    WidgetTester tester,
    SpotubeTrackObject track, {
    required List<SpotubeTrackObject> displayed,
    List<SpotubeTrackObject> remoteTracks = const [],
    List<String> remoteCollections = const [],
  }) async {
    final holder = _TapHolder();
    final remote = _RecordingConnectNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWith(() => player),
          databaseProvider.overrideWithValue(database),
          blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
          connectClientsProvider.overrideWith(() => _OneRemoteDeviceNotifier()),
          connectProvider.overrideWith(() => remote),
          queueProvider.overrideWith(
            (ref) => AudioPlayerState(
              playing: false,
              loopMode: PlaylistMode.none,
              shuffled: false,
              collections: remoteCollections,
              tracks: remoteTracks,
              currentIndex: 0,
            ),
          ),
          sourcedTrackProvider
              .overrideWith(() => _HangingSourcedTrackNotifier()),
          playbackServerPortProvider.overrideWith((ref) async => 21999),
          presentationStateProvider
              .overrideWith(() => _StubPresentationNotifier(displayed, SortBy.none)),
        ],
        // `showSelectDeviceDialog` reads (does not watch) the clients
        // provider, so something has to build it before the tap or the first
        // read is still AsyncLoading and the dialog is skipped.
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(connectClientsProvider);
            return child!;
          },
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: AppLayout(
              tokens: const ThemeTokens(),
              radii: const ThemeRadius(),
              layout: const ThemeLayout(),
              child: Data<TrackPresentationOptions>.inherit(
                data: TrackPresentationOptions(
                  collection: playlist,
                  title: playlist.name,
                  image: '',
                  routePath: '/playlist/${playlist.id}',
                  tracks: source,
                  pagination: PaginationProps(
                    hasNextPage: false,
                    isLoading: false,
                    onFetchMore: () {},
                    onRefresh: () async {},
                    onFetchAll: () async => source,
                  ),
                ),
                child: _Harness(holder: holder),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final done = holder.callback!(track);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remote Phone'));
    await tester.pump();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await done;
    return remote;
  }

  testWidgets('a remote tap jumps the remote queue, never the local player',
      (tester) async {
    // The tapped row is already in the *remote* queue at index 2. The old
    // branch called the local `jumpToTrack`, so the remote device kept playing
    // whatever it was on while the local queue moved (or silently did nothing).
    final remote = await tapRemoteTrack(
      tester,
      source[2],
      displayed: source,
      remoteTracks: source,
      remoteCollections: const ['pl-1'],
    );

    expect(remote.jumps, [2]);
    expect(remote.loads, isEmpty);
    expect(player.state.tracks, isEmpty,
        reason: 'the local queue is not the selected playback target');
  });

  testWidgets('a remote tap whose row is missing from the remote queue loads it',
      (tester) async {
    // `collections` saying the playlist is loaded on the remote device is not
    // proof that this row is in its queue. The row must be loaded and made the
    // initial track, not silently ignored.
    final missing = _track('delta', 'Delta');
    final displayed = [...source, missing];

    final remote = await tapRemoteTrack(
      tester,
      missing,
      displayed: displayed,
      remoteTracks: source,
      remoteCollections: const ['pl-1'],
    );

    expect(remote.jumps, isEmpty);
    expect(remote.loads, hasLength(1));
    final data = remote.loads.single;
    expect(data.initialIndex, displayed.length - 1);
    expect(data.tracks.map((t) => t.id), displayed.map((t) => t.id));
  });

  testWidgets('a sorted list plays the tapped row, not row N of the collection',
      (tester) async {
    // Z→A puts the collection's last track on the first row.
    final displayed = source.reversed.toList();

    await tapTrack(
      tester,
      displayed.first,
      displayed: displayed,
      sortBy: SortBy.descending,
    );

    expect(player.state.tracks.map((t) => t.id), ['alpha', 'bravo', 'charlie'],
        reason: 'the queue itself stays in collection order');
    expect(player.state.tracks[player.state.currentIndex].id, 'charlie',
        reason: 'the first visible row is what must start playing');
  });

  testWidgets('a filtered list plays the tapped row', (tester) async {
    final displayed = [source[1]];

    await tapTrack(
      tester,
      displayed.single,
      displayed: displayed,
      sortBy: SortBy.ascending,
    );

    expect(player.state.tracks[player.state.currentIndex].id, 'bravo');
  });

  testWidgets('an unsorted list still opens the tapped track', (tester) async {
    await tapTrack(tester, source[2], displayed: source);

    expect(player.state.tracks[player.state.currentIndex].id, 'charlie');
  });

  testWidgets(
      'an active collection whose queue lacks the row still plays it',
      (tester) async {
    // The collection is listed as active, but the queue only holds its first
    // track — the background tail append failed, or only part of a paginated
    // collection was added. Tapping a missing row used to call jumpToTrack,
    // which silently returned for index -1, so the old song kept playing.
    await tapTrack(
      tester,
      source[2],
      displayed: source,
      queueTracks: [source[0]],
      queueCollections: const ['pl-1'],
    );

    expect(player.state.tracks.map((t) => t.id),
        ['alpha', 'bravo', 'charlie']);
    expect(player.state.tracks[player.state.currentIndex].id, 'charlie');
  });
}
