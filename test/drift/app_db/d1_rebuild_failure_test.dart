// D1 regression test: a failed `_rebuildTablePreservingData` must never
// permanently lose rows, and a crash mid-rebuild must be recoverable on the
// next run.
//
// Unlike replaying the recovery SQL by hand, both tests drive the REAL
// `_rebuildTablePreservingData` through its testing seam
// (`AppDatabase.rebuildTablePreservingDataForTesting`):
//
// 1. Failure path: patchDdl produces an incompatible CREATE (fewer columns),
//    so `INSERT INTO ... SELECT *` fails mid-migration. Expect: the function
//    rethrows, the new table is dropped, `*_legacy` is renamed back, and the
//    original rows survive.
//
// 2. Retroactive recovery + stale-DDL fix: simulate a DB where a previous
//    run crashed between rename and copy (legacy table with real data + an
//    empty, differently-shaped table claiming the original name). Expect:
//    the legacy table is restored first, the DDL is RE-READ from the restored
//    table (regression guard for the stale-`ddl` fix), the patch is applied,
//    and rows survive. With the stale-`ddl` bug this test fails: the
//    tampered 3-column DDL drives the rebuild, the INSERT mismatches and the
//    migration throws.
//
// Runs against drift's isolated SchemaVerifier connections only — never the
// real db.sqlite.

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/services/logger/logger.dart';

import 'generated/schema.dart';

void main() {
  AppLogger.initialize(false);
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  Future<AppDatabase> v12Db() async {
    final schema = await verifier.schemaAt(12);
    return AppDatabase.forTesting(schema.newConnection());
  }

  Future<bool> tableExists(AppDatabase db, String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(name)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<List<String>> trackIds(AppDatabase db) async {
    final rows = await db.select(db.sourceMatchTable).get();
    return rows.map((r) => r.trackId).toList();
  }

  Future<String> tableDdl(AppDatabase db, String table) async {
    final rows = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.single.read<String>('sql');
  }

  Future<void> insertRow(AppDatabase db, String trackId) {
    return db.into(db.sourceMatchTable).insert(
          SourceMatchTableCompanion.insert(
            trackId: trackId,
            sourceInfo: const Value('{"info":"test data"}'),
            sourceType: 'youtube',
          ),
        );
  }

  test('rebuild failure restores the legacy table and keeps all rows',
      () async {
    final db = await v12Db();
    await insertRow(db, 'track-preserve');

    // Force the INSERT ... SELECT * to fail: the patched DDL recreates the
    // table with fewer columns than the legacy copy.
    await expectLater(
      db.rebuildTablePreservingDataForTesting(
        'source_match_table',
        (ddl) => 'CREATE TABLE source_match_table ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT)',
      ),
      throwsA(anything),
    );

    // Recovery path ran: new table dropped, legacy renamed back. The
    // original row survived and no *_legacy table lingers.
    expect(await trackIds(db), contains('track-preserve'));
    expect(await tableExists(db, 'source_match_table_legacy'), isFalse);

    // The restored table keeps the ORIGINAL schema (the failing patch is
    // not half-applied): the 5-column shape accepts another normal insert.
    await insertRow(db, 'track-after-recovery');
    expect(await trackIds(db), contains('track-after-recovery'));

    await db.close();
  });

  test(
      'legacy hangover is recovered, DDL re-read, and patch re-applied '
      'without losing rows', () async {
    final db = await v12Db();
    await insertRow(db, 'track-crashed-run');

    // Simulate the crash state: legacy table with the real data, plus an
    // empty, differently-shaped table squatting on the original name.
    await db.customStatement(
      'ALTER TABLE source_match_table RENAME TO source_match_table_legacy',
    );
    await db.customStatement('CREATE TABLE source_match_table ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'placeholder TEXT)');

    // A column-count-preserving patch: changes the source_info DEFAULT, a
    // marker SQLite stores verbatim in sqlite_master (unlike IF NOT EXISTS,
    // which the engine strips). INSERT ... SELECT * stays positional-valid.
    await db.rebuildTablePreservingDataForTesting(
      'source_match_table',
      (ddl) => ddl.replaceFirst("'{}'", '\'{"migrated":true}\''),
    );

    // Data survived recovery AND the subsequent rebuild.
    expect(await trackIds(db), contains('track-crashed-run'));
    expect(await tableExists(db, 'source_match_table_legacy'), isFalse);

    // The patch landed on the RESTORED (original v12-shape) table — proof
    // the DDL was re-read after recovery, not reused from the tampered
    // 3-column table (whose DDL has no '{}' to patch and whose copy would
    // fail with a column-count mismatch).
    final ddl = await tableDdl(db, 'source_match_table');
    expect(ddl, contains("'{\"migrated\":true}'"));

    await db.close();
  });
}
