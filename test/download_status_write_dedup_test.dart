// PR 1 / R-10: exactly one persisted `downloading` write per task.
//
// The worker used to write `downloading` twice: once when
// `_claimNextQueuedTask` synchronously flipped the task (the double-claim
// guard, in memory AND on disk) and again at the top of `_downloadTrack`'s
// transfer section. This counts the actual SQL statements hitting
// `track_download` with the `downloading` status via a drift
// QueryInterceptor — the only seam that sees unawaited writes.
//
// Harness mirrors download_cancel_test.dart: real loopback server, in-memory
// database, stub prefs — the transfer completes for real.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/sourced_track/source_dependencies.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;

import 'support/common_fakes.dart';

class _StatusWriteCounter extends QueryInterceptor {
  int downloadingWrites = 0;

  // The status column is argument 3 (0-based): after trackId, filePath, title.
  // `args.contains('downloading')` alone is wrong — the completed write's
  // WHERE-clause carries the whole enum name list, which includes it.
  bool _isDownloadingWrite(List<Object?> args) =>
      args.length > 3 && args[3] == 'downloading';

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_isDownloadingWrite(args)) downloadingWrites++;
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_isDownloadingWrite(args)) downloadingWrites++;
    return executor.runUpdate(statement, args);
  }
}

class _LazySourcedTrackNotifier extends SourcedTrackNotifier {
  _LazySourcedTrackNotifier(this.sourceRef, this.url);

  final Ref sourceRef;
  final String url;

  @override
  FutureOr<SourcedTrack> build(SpotubeFullTrackObject query) {
    return SourcedTrack(
      deps: sourceRef.sourceDeps,
      info: SpotubeAudioSourceMatchObject(
        id: 'match-1',
        title: 'Dedup Test Track',
        artists: const ['Test Artist'],
        duration: const Duration(minutes: 3),
        externalUri: 'https://example.test/watch/1',
      ),
      query: query,
      source: 'youtube',
      siblings: const [],
      sources: [
        SpotubeAudioSourceStreamObject(
          url: url,
          container: 'weba',
          type: SpotubeMediaCompressionType.lossy,
          bitrate: 128000.0,
        ),
      ],
    );
  }
}

final _refProbeProvider = Provider<Ref>((ref) => ref);

SpotubeFullTrackObject _testTrack() {
  return SpotubeFullTrackObject(
    id: 'dedup-test-track',
    name: 'Dedup Test Track',
    externalUri: 'https://example.test/track/9',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a9',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/9',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'alb9',
      name: 'Test Album',
      externalUri: 'https://example.test/album/9',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST00000009',
    explicit: false,
  );
}

void main() {
  AppLogger.initialize(false);

  late Directory tempRoot;
  late HttpServer server;
  late ProviderContainer container;
  late AppDatabase db;
  late _StatusWriteCounter counter;
  final track = _testTrack();

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('dl_dedup_');
    counter = _StatusWriteCounter();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(counter));
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);

    // Small body, fast response: the transfer is only here to let the task
    // run queued -> downloading -> completed for real.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      final payload = List.generate(4096, (i) => i % 256);
      if (req.method == 'HEAD') {
        req.response.headers.set('content-length', '${payload.length}');
        req.response.close();
        return;
      }
      req.response.add(payload);
      req.response.close();
    });

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        userPreferencesProvider.overrideWith(
          () => StubPrefsNotifier(
            PreferencesTable.defaults()
                .copyWith(downloadLocation: tempRoot.path),
          ),
        ),
        audioSourcePluginProvider.overrideWith((ref) async => null),
        metadataPluginsProvider
            .overrideWith(() => EmptyMetadataPluginNotifier()),
        audioSourcePresetsProvider.overrideWith(
          () => FixedPresetsNotifier(
            AudioSourcePresetsState(
              presets: [
                SpotubeAudioSourceContainerPreset.lossy(
                  type: SpotubeMediaCompressionType.lossy,
                  name: 'weba',
                  qualities: [
                    SpotubeAudioLossyContainerQuality(bitrate: 128000)
                  ],
                ),
              ],
            ),
          ),
        ),
        sourcedTrackProvider.overrideWith(
          () => _LazySourcedTrackNotifier(
            container.read(_refProbeProvider),
            'http://${server.address.address}:${server.port}/stream.weba',
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await server.close(force: true);
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  DownloadTask? taskState() => container
      .read(downloadManagerProvider)
      .firstWhereOrNull((e) => e.track.id == track.id);

  test('one download persists `downloading` exactly once', () async {
    container.read(downloadManagerProvider.notifier).addToQueue(track);

    for (var i = 0;
        i < 200 && taskState()?.status != DownloadStatus.completed;
        i++) {
      await Future.delayed(const Duration(milliseconds: 25));
    }
    // Let the unawaited persist futures all land.
    for (var i = 0; i < 500; i++) {
      await Future.delayed(Duration.zero);
    }

    expect(taskState()?.status, DownloadStatus.completed);
    expect(
      counter.downloadingWrites,
      1,
      reason: 'the claim owns the `downloading` write; the transfer section '
          'used to write it a second time',
    );

    // The persisted row must be completed (the dedup must not have removed
    // the claim write itself, which is what makes `markInFlightAsInterrupted`
    // meaningful after a crash).
    final row = await (db.select(db.trackDownloadTable)
          ..where((t) => t.trackId.equals(track.id)))
        .getSingle();
    expect(row.status, DownloadPersistedStatus.completed);
    expect(
      File(p.join(tempRoot.path, row.filePath)).existsSync(),
      isTrue,
      reason: 'a real file completed the whole path',
    );
  });

  test('cancel while the worker is past the claim still lands canceled',
      () async {
    // Regression guard for the race the second write used to open: with only
    // the claim writing `downloading`, a cancel at any later point can never
    // be reverted by the transfer section.
    final notifier = container.read(downloadManagerProvider.notifier);
    notifier.addToQueue(track);
    for (var i = 0;
        i < 200 && taskState()?.status == DownloadStatus.queued;
        i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    notifier.cancel(track);
    for (var i = 0; i < 400; i++) {
      await Future.delayed(Duration.zero);
    }
    expect(taskState()?.status, DownloadStatus.canceled);
  });
}
