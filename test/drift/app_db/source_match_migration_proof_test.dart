// PR3 regression test: v9 cached source_match rows must migrate to
// readable v12 sourceInfo instead of the '{}' backfill default (which
// crashes SpotubeAudioSourceMatchObject deserialization on the cache-hit
// path).
//
// Representative historical shapes (from git history):
//  - DAB era: sourceId = {"info": {...match...}, "sources": [...]}
//  - invidious era: sourceId = raw video id string
// Migratable rows keep a validated, re-encoded info object; anything else
// is QUARANTINED (v9->v10 parks a marker in source_info because the
// quarantine table only exists from v12; v11->v12 relocates markers into
// source_match_quarantine_table with the raw payload + reason) instead of
// being deleted. The live table stays a pure performance cache: a missing
// row is a self-healing cache miss, a '{}' row is a crash.
//
// Runs against drift's isolated SchemaVerifier connections only — never the
// real db.sqlite.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations.dart';
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

void main() {
  AppLogger.initialize(false);

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v9 rows migrate to readable sourceInfo or quarantine', () async {
    final schema = await verifier.schemaAt(9);
    final setupConnection = schema.newConnection();
    final v9db = v9.DatabaseAtV9(setupConnection);

    // DAB-era row: JSON blob wrapping a valid match object.
    final migratable = _match('video-migratable');
    await v9db.into(v9db.sourceMatchTable).insert(
          v9.SourceMatchTableCompanion.insert(
            trackId: 'track-migratable',
            sourceId: jsonEncode({
              'info': migratable.toJson(),
              'sources': const [],
            }),
          ),
        );
    // Invidious-era row: raw video id, not upgradable offline.
    await v9db.into(v9db.sourceMatchTable).insert(
          v9.SourceMatchTableCompanion.insert(
            trackId: 'track-raw-id',
            sourceId: 'youtube-video-xyz',
          ),
        );

    // Stamp v9 explicitly (the verifier leaves user_version at 0, for which
    // drift would run onCreate instead of the upgrade path), then migrate on
    // a fresh executor mirroring drift's own testWithDataIntegrity flow.
    await v9db.customStatement('PRAGMA user_version = 9');
    await v9db.close();

    final appDb = AppDatabase.forTesting(schema.newConnection());
    final migrated = await appDb.select(appDb.sourceMatchTable).get();

    // Migratable row: present with a readable, equivalent info object.
    final kept = migrated.where((r) => r.trackId == 'track-migratable');
    expect(kept, hasLength(1));
    final parsed = SpotubeAudioSourceMatchObject.fromJson(
      jsonDecode(kept.single.sourceInfo) as Map<String, dynamic>,
    );
    expect(parsed.id, migratable.id);
    expect(parsed.title, migratable.title);
    expect(parsed.externalUri, migratable.externalUri);

    // Raw-id row: absent from live (cache miss, self-healing) and parked
    // in quarantine with the raw payload + reason for diagnosis.
    expect(
      migrated.where((r) => r.trackId == 'track-raw-id'),
      isEmpty,
    );
    final quarantined =
        await appDb.select(appDb.sourceMatchQuarantineTable).get();
    final rawQuarantine =
        quarantined.where((r) => r.trackId == 'track-raw-id');
    expect(rawQuarantine, hasLength(1));
    expect(rawQuarantine.single.rawSourceId, 'youtube-video-xyz');
    expect(rawQuarantine.single.reason, isNotEmpty);
    expect(rawQuarantine.single.quarantinedAtMs, greaterThan(0));

    await appDb.close();
  });

  test('v9->v12 completes the preferences/source_match transition', () async {
    final schema = await verifier.schemaAt(9);
    final setupConnection = schema.newConnection();
    final v9db = v9.DatabaseAtV9(setupConnection);
    await v9db.customStatement('PRAGMA user_version = 9');
    await v9db.close();

    final appDb = AppDatabase.forTesting(schema.newConnection());

    Future<Set<String>> columns(String table) async {
      final info =
          await appDb.customSelect('PRAGMA table_info($table)').get();
      return {for (final row in info) row.read<String>('name')};
    }

    Future<Set<String>> indexes(String table) async {
      final info =
          await appDb.customSelect('PRAGMA index_list($table)').get();
      return {for (final row in info) row.read<String>('name')};
    }

    final prefs = await columns('preferences_table');
    // Added by the model without a migration step (Phase 3.2 item 2).
    expect(prefs, contains('audio_source_id'));
    // Genuinely obsolete since 99a84aa6; must be gone for schema parity.
    expect(
      prefs.intersection({
        'audio_quality',
        'audio_source',
        'stream_music_codec',
        'download_music_codec',
        'piped_instance',
        'invidious_instance',
      }),
      isEmpty,
    );

    final sourceMatch = await columns('source_match_table');
    expect(sourceMatch, contains('source_info'));
    expect(sourceMatch, isNot(contains('source_id')));

    // Deliberately removed (insert failures); must stay gone.
    expect(await indexes('source_match_table'), isNot(contains('uniq_track_match')));

    // Quarantine table exists from v12 with the full diagnostic shape.
    final quarantine = await columns('source_match_quarantine_table');
    expect(
      quarantine,
      containsAll([
        'id',
        'track_id',
        'raw_source_id',
        'reason',
        'source_type',
        'quarantined_at_ms',
      ]),
    );

    await appDb.close();
  });
}
