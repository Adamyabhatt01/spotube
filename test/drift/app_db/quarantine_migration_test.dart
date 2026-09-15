// PR3: quarantine-table migration contract (v11 -> v12 + v9 -> v10 markers).
//
// Rules under test:
//  1. Unmigratable v9 rows are quarantined with raw payload + reason, never
//     deleted without a quarantine record.
//  2. Re-running the move is safe (idempotent): zero rows moved, no error,
//     and re-issuing the v12 DDL is a no-op.
//  3. Failure atomicity: if the quarantine INSERT fails, the migration
//     throws and the live corrupt row is still present (nothing disappears
//     without a quarantine record).
//  4. Valid rows migrate identically to the old behavior (readable info).
//
// Runs against drift's isolated SchemaVerifier connections only — never the
// real db.sqlite.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/logger/logger.dart';

import 'generated/schema.dart';
import 'generated/schema_v9.dart' as v9;

SpotubeAudioSourceMatchObject _match(String id) {
  return SpotubeAudioSourceMatchObject(
    id: id,
    title: 'Test Title $id',
    artists: const ['Test Artist'],
    duration: const Duration(minutes: 3),
    externalUri: 'https://example.test/watch/$id',
  );
}

Future<void> _insertV9Row(
  v9.DatabaseAtV9 v9db, {
  required String trackId,
  required String sourceId,
  String sourceType = 'youtube',
}) {
  return v9db.into(v9db.sourceMatchTable).insert(
        v9.SourceMatchTableCompanion.insert(
          trackId: trackId,
          sourceId: sourceId,
          sourceType: Value(sourceType),
        ),
      );
}

void main() {
  AppLogger.initialize(false);

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v9 corrupt rows land in quarantine with diagnostics', () async {
    final schema = await verifier.schemaAt(9);
    final v9db = v9.DatabaseAtV9(schema.newConnection());

    final migratable = _match('video-ok');
    await _insertV9Row(
      v9db,
      trackId: 'track-ok',
      sourceId: jsonEncode({'info': migratable.toJson(), 'sources': const []}),
    );
    await _insertV9Row(v9db, trackId: 'track-raw', sourceId: 'raw-video-id');
    await _insertV9Row(v9db, trackId: 'track-empty', sourceId: '{}');
    await _insertV9Row(v9db, trackId: 'track-garbage', sourceId: 'not json');
    await v9db.customStatement('PRAGMA user_version = 9');
    await v9db.close();

    final appDb = AppDatabase.forTesting(schema.newConnection());

    // Live table: only the migratable row, readable as before.
    final live = await appDb.select(appDb.sourceMatchTable).get();
    expect(live.map((r) => r.trackId), ['track-ok']);
    expect(
      SpotubeAudioSourceMatchObject.fromJson(
        jsonDecode(live.single.sourceInfo) as Map<String, dynamic>,
      ).id,
      'video-ok',
    );

    // Quarantine: the other three, raw payloads + reasons preserved.
    final quarantined =
        await appDb.select(appDb.sourceMatchQuarantineTable).get();
    expect(
      {for (final r in quarantined) r.trackId},
      {'track-raw', 'track-empty', 'track-garbage'},
    );
    final byTrack = {for (final r in quarantined) r.trackId: r};
    expect(byTrack['track-raw']!.rawSourceId, 'raw-video-id');
    expect(byTrack['track-empty']!.rawSourceId, '{}');
    expect(byTrack['track-garbage']!.rawSourceId, 'not json');
    for (final row in quarantined) {
      expect(row.reason, isNotEmpty);
      expect(row.sourceType, 'youtube');
      expect(row.quarantinedAtMs, greaterThan(0));
    }

    await appDb.close();
  });

  test('quarantine move is idempotent, DDL re-runnable', () async {
    final schema = await verifier.schemaAt(12);
    final appDb = AppDatabase.forTesting(schema.newConnection());

    await appDb.into(appDb.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: 'track-live',
            sourceInfo: const Value('{}'),
            sourceType: 'youtube',
          ),
        );

    // No markers: move is a no-op returning zero.
    expect(
      await AppDatabase.moveQuarantineMarkersToTable(appDb),
      isZero,
    );
    // Re-issuing the v12 DDL must not throw (IF NOT EXISTS).
    await appDb.customStatement(AppDatabase.quarantineTableDdl);
    expect(
      await AppDatabase.moveQuarantineMarkersToTable(appDb),
      isZero,
    );
    expect(
      (await appDb.select(appDb.sourceMatchTable).get()).map((r) => r.trackId),
      ['track-live'],
    );

    await appDb.close();
  });

  test('quarantine-write failure keeps the live row (atomicity)', () async {
    final schema = await verifier.schemaAt(12);
    final appDb = AppDatabase.forTesting(schema.newConnection());

    await appDb.into(appDb.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: 'track-doomed',
            sourceInfo: const Value('{}'),
            sourceType: 'youtube',
          ),
        );
    // Forge a v9->v10-style marker directly.
    const marker =
        '{"quarantine":true,"rawSourceId":"bad-payload","reason":"test"}';
    await appDb.customStatement(
      "UPDATE source_match_table SET source_info = '$marker' "
      "WHERE track_id = 'track-doomed'",
    );

    // Fault injection: remove the quarantine table so the INSERT fails.
    await appDb.customStatement('DROP TABLE source_match_quarantine_table');

    // The move must throw...
    await expectLater(
      AppDatabase.moveQuarantineMarkersToTable(appDb),
      throwsA(anything),
    );
    // ...and the live corrupt row must still be there untouched.
    final live = await appDb.select(appDb.sourceMatchTable).get();
    expect(live.map((r) => r.trackId), ['track-doomed']);
    expect(live.single.sourceInfo, marker);

    // Recovery: recreate + move succeeds exactly once.
    await appDb.customStatement(AppDatabase.quarantineTableDdl);
    expect(await AppDatabase.moveQuarantineMarkersToTable(appDb), 1);
    expect(await appDb.select(appDb.sourceMatchTable).get(), isEmpty);
    final quarantined =
        await appDb.select(appDb.sourceMatchQuarantineTable).get();
    expect(quarantined, hasLength(1));
    expect(quarantined.single.rawSourceId, 'bad-payload');

    await appDb.close();
  });
}
