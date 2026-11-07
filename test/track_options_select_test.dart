// Regression test for Phase 2 W.4: `trackOptionsStateProvider` subscribes
// to the consumed audio-player slices (`activeTrack`, `tracks`) instead of
// the full player state.
//
// Expectations mirror W.2: flag flips stay silent; active-track changes and
// queue mutations notify; `containsTrack` behavior is identical. The last two
// cases cover the menu-state narrowing that replaced the two whole-list
// watches: a download tick or a blacklist write that says nothing about this
// row must not rebuild it, and one that does must.
//
// Hermetic: the player is a scripted fake (no media_kit), the blacklist is
// stubbed empty (no DB), metadata plugins fail fast (no hetu), and the
// download manager runs for real (pure in-memory default state).

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/track_options/track_options_provider.dart';
import 'package:spotube/services/downloads/download_store.dart';

class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  _FakeAudioPlayerNotifier(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

class _FailingMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() {
    throw StateError('no metadata plugins in unit tests');
  }
}

/// Riverpod exposes no way to list the live provider elements, so disposal is
/// observed through an observer instead.
class _DisposalObserver extends ProviderObserver {
  final List<ProviderBase<Object?>> disposed = [];

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    disposed.add(provider);
  }
}

SpotubeFullTrackObject _testTrack(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'test-artist-1',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/1',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-1',
      name: 'Test Album',
      externalUri: 'https://example.test/album/1',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000001',
    explicit: false,
  );
}

AudioPlayerState _playerState({
  required List<SpotubeTrackObject> tracks,
  int currentIndex = 0,
  bool playing = false,
  bool shuffled = false,
}) {
  return AudioPlayerState(
    playing: playing,
    loopMode: PlaylistMode.none,
    shuffled: shuffled,
    collections: const [],
    currentIndex: currentIndex,
    tracks: tracks,
  );
}

/// Pumps the event loop so already-scheduled microtasks and zero-duration
/// timers run to completion. A real regression schedules work; an idle
/// scheduler drains this deterministically without a wall-clock bet.
Future<void> drain([int yields = 200]) async {
  for (var i = 0; i < yields; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Polls [done] until it returns true or the deadline passes, then fails.
Future<void> eventually(
  bool Function() done,
  String what, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (!done()) fail('$what did not happen within $budget');
}

// Note on what this file proves: Riverpod suppresses notifications AND
// observer updates for rebuilds whose value is ==-equal, and freezed
// re-wraps list fields on every state construction (so state-object identity
// never holds across emits). Hence rebuild-skipping itself is not observable
// through public APIs. What IS locked here:
//  1. the value contract (flag flips never surface; real changes notify);
//  2. behavioral identity of the inlined queue-membership predicate against
//     the AudioPlayerState.containsTrack oracle across a case matrix — this
//     guards the predicate duplication introduced by subscribing to `tracks`
//     instead of the full player state.
//  3. the two narrowed watches, whose "no rebuild" claim is observable as a
//     zero notification count once the provider has settled, and
//  4. release-on-unmount, counted as the disposal that follows the last
//     listener closing (Riverpod reports one for every rebuild of an
//     autoDispose provider, so the absolute count proves nothing).
void main() {
  late ProviderContainer container;
  late _FakeAudioPlayerNotifier fakePlayer;
  late _DisposalObserver disposal;

  // Building DownloadManagerNotifier reconciles `track_download`, so the
  // notifier needs a database that is not resolved from a path provider.
  late AppDatabase db;

  setUp(() async {
    fakePlayer = _FakeAudioPlayerNotifier(_playerState(tracks: const []));
    disposal = _DisposalObserver();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      observers: [disposal],
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioPlayerProvider.overrideWith(() => fakePlayer),
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
        metadataPluginsProvider
            .overrideWith(() => _FailingMetadataPluginNotifier()),
      ],
    );
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  test('flag flips stay silent; track and queue changes notify', () async {
    final track = _testTrack('track-1');
    // Same list instance across emits: real flag flips preserve the queue
    // reference via copyWith, and select compares list identity.
    final queue = <SpotubeTrackObject>[track];
    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(track),
      (_, __) => notifications++,
    );

    final initial = container.read(trackOptionsStateProvider(track));
    expect(initial.isInQueue, isFalse);
    expect(initial.isActiveTrack, isFalse);
    expect(initial.isBlacklisted, isFalse);
    expect(initial.isInDownloadQueue, isFalse);
    final baseline = notifications;

    // Negative: playing/shuffle flips with the same (empty) queue.
    fakePlayer.emit(
      _playerState(tracks: const [], playing: true, shuffled: true),
    );
    await drain();
    expect(notifications, baseline,
        reason: 'flag change must not rebuild menu state');

    // Positive: queue mutation carrying the track notifies.
    fakePlayer.emit(_playerState(tracks: queue, playing: true));
    await eventually(
      () => notifications > baseline,
      'queue mutation to rebuild menu state',
    );
    expect(notifications, greaterThan(baseline),
        reason: 'queue mutation must rebuild menu state');

    // containsTrack behavior identical: track now in queue and active.
    final updated = container.read(trackOptionsStateProvider(track));
    expect(updated.isInQueue, isTrue);
    expect(updated.isActiveTrack, isTrue);
    expect(updated.isBlacklisted, isFalse);
    expect(updated.isInDownloadQueue, isFalse);

    // Negative again: flag flip with the same queue stays silent.
    final afterQueueChange = notifications;
    fakePlayer.emit(
      _playerState(tracks: queue, playing: false, shuffled: true),
    );
    await drain();
    expect(notifications, afterQueueChange,
        reason: 'flag change with unchanged queue must not rebuild');
  });

  test('active-track switch notifies without queue mutation', () async {
    final trackA = _testTrack('track-a');
    final trackB = _testTrack('track-b');
    // Same list instance: only the index changes, mirroring a track
    // advance that reuses the queue reference.
    final queue = <SpotubeTrackObject>[trackA, trackB];

    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(trackB),
      (_, __) => notifications++,
    );

    // Mount with the first track active (initial read settles the baseline).
    fakePlayer.emit(_playerState(tracks: queue));
    await drain();
    expect(
      container.read(trackOptionsStateProvider(trackB)).isActiveTrack,
      isFalse,
    );
    final baseline = notifications;

    // Same queue instance content, different index -> active track changes.
    fakePlayer.emit(
      _playerState(tracks: queue, currentIndex: 1),
    );
    await eventually(
      () => notifications > baseline,
      'active-track switch to rebuild menu state',
    );
    expect(notifications, greaterThan(baseline),
        reason: 'active-track switch must rebuild menu state');
    expect(
      container.read(trackOptionsStateProvider(trackB)).isActiveTrack,
      isTrue,
    );
  });

  test('isInQueue matches AudioPlayerState.containsTrack oracle', () async {
    SpotubeLocalTrackObject local(String id, String path) {
      return SpotubeLocalTrackObject(
        id: id,
        name: 'Local $id',
        externalUri: 'file://$path',
        album: SpotubeSimpleAlbumObject(
          id: 'test-album-1',
          name: 'Test Album',
          externalUri: 'https://example.test/album/1',
          artists: const [],
          albumType: SpotubeAlbumType.album,
        ),
        durationMs: 180000,
        path: path,
      );
    }

    final fullA = _testTrack('a');
    final fullB = _testTrack('b');
    final localX1 = local('x', '/music/x.mp3');
    final localX2 = local('x', '/music/x.mp3');
    final localY = local('x', '/music/y.mp3');

    final cases = <String, (List<SpotubeTrackObject>, SpotubeTrackObject)>{
      'empty queue': (const [], fullA),
      'track present': ([fullA], fullA),
      'track absent': ([fullA], fullB),
      'local same path': ([localX1], localX2),
      'local different path': ([localX1], localY),
      // Predicate falls back to id comparison unless BOTH sides are local.
      'full queue, local menu, same id': ([fullA], local('a', '/other.mp3')),
      'local queue, full menu, same id': (
        [local('a', '/music/a.mp3')],
        _testTrack('a')
      ),
    };

    // Mount the player before emitting (unmounted notifiers reject state).
    container.read(trackOptionsStateProvider(fullA));

    for (final entry in cases.entries) {
      final (queue, menuTrack) = entry.value;
      fakePlayer.emit(_playerState(tracks: queue));
      await drain();

      final oracle = AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        tracks: queue,
      ).containsTrack(menuTrack);
      final actual =
          container.read(trackOptionsStateProvider(menuTrack)).isInQueue;

      expect(actual, oracle, reason: 'case: ${entry.key}');
    }
  });

  test('download churn on other tracks does not rebuild the row menu',
      () async {
    final row = _testTrack('row-track');
    final active = _testTrack('active-track');

    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(row),
      (_, __) => notifications++,
    );
    fakePlayer.emit(_playerState(tracks: [active]));
    final downloads = container.read(downloadManagerProvider.notifier);
    await drain();

    for (var i = 0; i < 5; i++) {
      // A progress tick replaces the list and the task object, which is what
      // DownloadManagerNotifier does repeatedly while a transfer runs.
      downloads.state = [
        DownloadTask(
          track: _testTrack('someone-else'),
          status: DownloadStatus.downloading,
          cancelToken: CancelToken(),
        ),
      ];
      await drain();
    }
    expect(notifications, 0,
        reason: 'an unrelated transfer must not touch this row');

    // Positive control: the same churn, this time for this row's own track.
    downloads.state = [
      DownloadTask(
        track: row,
        status: DownloadStatus.downloading,
        cancelToken: CancelToken(),
      ),
    ];
    await eventually(
      () => notifications > 0,
      'this row\'s download to reach the row menu',
    );
    expect(
      container.read(trackOptionsStateProvider(row)).isInDownloadQueue,
      isTrue,
    );
  });

  test('a finished download shows on its row with nothing in the session',
      () async {
    final row = _testTrack('row-track');
    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(row),
      (_, __) => notifications++,
    );
    fakePlayer.emit(_playerState(tracks: const []));
    await drain();
    expect(
        container.read(trackOptionsStateProvider(row)).isDownloaded, isFalse);

    // The situation after a restart: no DownloadTask exists anywhere, and the
    // only evidence the file is this app's is the row the download manager left.
    await writeDownloadStatus(
      db,
      DownloadRecord(
        trackId: row.id,
        filePath: '/music/${row.id}.weba',
        baseName: row.id,
        status: DownloadPersistedStatus.completed,
        trackData: '{}',
      ),
    );

    await eventually(
      () => container.read(trackOptionsStateProvider(row)).isDownloaded,
      'the download record to reach the row',
    );
    // `completed` is neither queued nor downloading, so the row offers the
    // finished mark rather than a spinner that never fills.
    expect(container.read(trackOptionsStateProvider(row)).isInDownloadQueue,
        isFalse);
    expect(container.read(trackOptionsStateProvider(row)).downloadTask, isNull);
  });

  test('blacklist churn that never mentions this row stays silent', () async {
    final row = _testTrack('row-track');

    var notifications = 0;
    container.listen(
      trackOptionsStateProvider(row),
      (_, __) => notifications++,
    );
    fakePlayer.emit(_playerState(tracks: [row]));
    final blacklist = container.read(blacklistProvider.notifier);
    await drain();
    // The blacklist starts out AsyncLoading; settling it is not the churn.
    notifications = 0;

    blacklist.state = const AsyncData([
      BlacklistTableData(
        id: 1,
        name: 'Someone else',
        elementType: BlacklistedType.artist,
        elementId: 'unrelated-artist',
      ),
    ]);
    await drain();
    expect(notifications, 0,
        reason: 'the blacklist watch is a bool select, not the whole table');

    // Positive control: blacklisting an artist of this row flips the flag.
    blacklist.state = const AsyncData([
      BlacklistTableData(
        id: 2,
        name: 'Test Artist',
        elementType: BlacklistedType.artist,
        elementId: 'test-artist-1',
      ),
    ]);
    await eventually(
      () => notifications > 0,
      'the row artist blacklist to reach the menu',
    );
    expect(
      container.read(trackOptionsStateProvider(row)).isBlacklisted,
      isTrue,
    );
  });

  test('a row menu state is released once the row goes away', () async {
    int disposedRowMenus() => disposal.disposed
        .where(
            (provider) => identical(provider.from, trackOptionsStateProvider))
        .length;

    final row = _testTrack('row-track');
    final subscription = container.listen(
      trackOptionsStateProvider(row),
      (_, __) {},
    );
    fakePlayer.emit(_playerState(tracks: [row]));
    await drain();
    final whileMounted = disposedRowMenus();

    // The widget equivalent of scrolling the row off screen.
    subscription.close();
    await drain();

    expect(
      disposedRowMenus(),
      greaterThan(whileMounted),
      reason: 'a kept-alive family entry keeps rescanning the queue for every '
          'track the user ever opened a menu on, after its row is gone',
    );

    // Releasing it must not cost correctness: remounting yields the same view.
    final remounted = container.listen(
      trackOptionsStateProvider(row),
      (_, __) {},
    );
    expect(
      container.read(trackOptionsStateProvider(row)).isInQueue,
      isTrue,
      reason: 'the recreated instance must see the same queue',
    );
    remounted.close();
  });
}
