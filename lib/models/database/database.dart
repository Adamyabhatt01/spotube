library database;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:encrypt/encrypt.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode, Colors;
import 'package:spotube/models/database/database.steps.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/market.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/kv_store/encrypted_kv_store.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:flutter/widgets.dart' hide Table, Key, View;
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
import 'package:drift/native.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';
import 'package:spotube/services/youtube_engine/youtube_explode_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'database.g.dart';

part 'tables/authentication.dart';
part 'tables/blacklist.dart';
part 'tables/preferences.dart';
part 'tables/scrobbler.dart';
part 'tables/skip_segment.dart';
part 'tables/source_match.dart';
part 'tables/audio_player_state.dart';
part 'tables/history.dart';
part 'tables/lyrics.dart';
part 'tables/metadata_plugins.dart';
part 'tables/library_snapshot.dart';
part 'tables/track_download.dart';
part 'tables/playlist_download.dart';
part 'tables/playlist_download_mirror.dart';

part 'typeconverters/color.dart';
part 'typeconverters/locale.dart';
part 'typeconverters/string_list.dart';
part 'typeconverters/encrypted_text.dart';
part 'typeconverters/map.dart';
part 'typeconverters/map_list.dart';
part 'typeconverters/subtitle.dart';

@DriftDatabase(
  tables: [
    AuthenticationTable,
    BlacklistTable,
    PreferencesTable,
    ScrobblerTable,
    SkipSegmentTable,
    SourceMatchTable,
    SourceMatchQuarantineTable,
    AudioPlayerStateTable,
    HistoryTable,
    LyricsTable,
    PluginsTable,
    LibrarySnapshotTable,
    TrackDownloadTable,
    PlaylistDownloadTable,
    PlaylistDownloadMirrorTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test-only constructor: uses the supplied executor instead of the real
  /// on-disk database (Phase 3.1). Lets drift migration tests run against
  /// the connection handed out by the SchemaVerifier instead of touching
  /// the user's db.sqlite. Production code must keep using [AppDatabase.new].
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 20;

  /// Raw DDL for the quarantine table, kept as a constant so the v11->v12
  /// step can create it idempotently (`IF NOT EXISTS`) without depending
  /// on versioned-schema views. Must stay in sync with
  /// [SourceMatchQuarantineTable]; drift's schema validation proves it.
  static const quarantineTableDdl =
      'CREATE TABLE IF NOT EXISTS source_match_quarantine_table ('
      'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      'track_id TEXT NOT NULL, '
      'raw_source_id TEXT NOT NULL, '
      'reason TEXT NOT NULL, '
      'source_type TEXT NULL, '
      'quarantined_at_ms INTEGER NOT NULL)';

  /// Marker key parking unmigratable rows inside `source_info` during
  /// v9->v10 (the quarantine table only exists from v12, so the payload
  /// cannot move there yet). v11->v12 relocates marked rows. Data-only:
  /// schema validation is unaffected.
  static const quarantineMarkerKey = 'quarantine';

  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'",
    ).get();
    return rows.isNotEmpty;
  }

  /// Drift's `Migrator.createTable` does not create the indexes declared as
  /// `@TableIndex` (only a fresh `createAll` walks those entities), and the DDL
  /// it generates for them carries no `IF NOT EXISTS`. A migration step that
  /// re-enters after the CREATE TABLE succeeded would therefore throw on the
  /// index, so index creation needs this guard where a table guard does not.
  Future<bool> _indexExists(String index) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = '$index'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<Set<String>> _tableColumns(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  Future<String?> _tableDdl(String table) async {
    final rows = await customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = '$table'",
    ).get();
    if (rows.isEmpty) return null;
    return rows.single.read<String>('sql');
  }

  /// Rebuilds [table] with DDL transformed by [patchDdl] (which returns
  /// null when no rebuild is needed), preserving all rows positionally.
  /// Used where SQLite offers no ALTER for the change (adding/changing a
  /// column DEFAULT). The legacy copy is dropped only after the copy
  /// succeeds, and a best-effort rename-back precedes any rethrow.
  Future<void> _rebuildTablePreservingData(
    String table,
    String? Function(String ddl) patchDdl,
  ) async {
    var ddl = await _tableDdl(table);
    if (ddl == null) {
      throw StateError('$table does not exist during migration');
    }
    final legacy = '${table}_legacy';
    // Retroactivity: if a previous migration left a $legacy table with
    // real data (crash between rename and copy), recover it now before
    // the normal path runs.  This prevents permanent data loss for users
    // who already hit the bug this PR fixed.
    if (await _tableExists(legacy)) {
      // The new table is the patched-empty version; drop it so the
      // rename-back can succeed, then restore the legacy table as the
      // real table.
      try {
        await customStatement('DROP TABLE IF EXISTS "$table"');
      } catch (_) {
        // If dropping fails, the state is uncertain; still try the
        // rename-back below.
      }
      try {
        await customStatement('ALTER TABLE "$legacy" RENAME TO "$table"');
      } catch (_) {
        // Recovery rename also failed — fall through to the normal
        // below, which will rethrow the original error at the caller.
      }
      // Recovery replaced the table (legacy carries the ORIGINAL, pre-patch
      // schema), so the DDL read above is stale. Re-read it so patchDdl sees
      // the restored schema; otherwise patchDdl(ddl) would see the already-
      // patched DDL, return null, and skip the migration entirely.
      ddl = await _tableDdl(table);
      if (ddl == null) {
        throw StateError('$table does not exist after legacy recovery');
      }
    }
    final patched = patchDdl(ddl);
    if (patched == null) return; // Already correct (idempotent re-run).
    await customStatement('ALTER TABLE $table RENAME TO $legacy');
    try {
      // [patched] still names the original table (DDL was read before the
      // rename), so executing it recreates the table, then data is copied.
      await customStatement(patched);
      await customStatement(
        'INSERT INTO "$table" SELECT * FROM "$legacy"',
      );
      await customStatement('DROP TABLE "$legacy"');
    } catch (e) {
      // The patched CREATE TABLE may have taken the original table name,
      // so the recovery rename below can fail with "already exists".
      // Drop the new table first so the rename-back can succeed,
      // guaranteeing original rows are always recoverable.
      try {
        await customStatement('DROP TABLE IF EXISTS "$table"');
      } catch (_) {
        // If dropping the new table fails, the state is uncertain; still
        // attempt the rename-back below.
      }
      try {
        await customStatement('ALTER TABLE "$legacy" RENAME TO "$table"');
      } catch (_) {
        // Even the recovery rename failed — report and rethrow the
        // original error so the migration does not silently succeed with
        // lost rows.
        AppLogger.reportError(e, StackTrace.current);
      }
      rethrow;
    }
  }

  /// Testing seam for [_rebuildTablePreservingData]: production callers reach
  /// it only through migration steps; tests drive the failure/recovery paths
  /// directly (mirrors [AppDatabase.forTesting] and
  /// [moveQuarantineMarkersToTable]).
  @visibleForTesting
  Future<void> rebuildTablePreservingDataForTesting(
    String table,
    String? Function(String ddl) patchDdl,
  ) =>
      _rebuildTablePreservingData(table, patchDdl);

  /// Ensures `plugin_api_version` carries the given `DEFAULT` (v8 wants
  /// `'1.0.0'`, v9+ wants `'2.0.0'`). The column predates both defaults,
  /// and SQLite has no `ALTER COLUMN ... SET DEFAULT`, so the table is
  /// rebuilt with patched DDL when the default differs. Without this,
  /// inserts relying on the default fail NOT NULL and validation fails.
  Future<void> _ensurePluginApiVersionDefault(
    String table,
    String wantedDefault,
  ) async {
    await _rebuildTablePreservingData(table, (ddl) {
      final clause =
          RegExp('"plugin_api_version"[^,)]*').firstMatch(ddl)?.group(0);
      if (clause == null) {
        throw StateError(
            'plugin_api_version missing in $table during migration');
      }
      if (clause.contains("DEFAULT '$wantedDefault'")) return null;
      final patchedClause = clause.contains('DEFAULT')
          ? clause.replaceFirst(
              RegExp("DEFAULT '[^']*'"), "DEFAULT '$wantedDefault'")
          : "$clause DEFAULT '$wantedDefault'";
      return ddl.replaceFirst(clause, patchedClause);
    });
  }

  /// Drops the stale `DEFAULT 'youtube'` from
  /// `source_match_table.source_type`. The default existed in v9 but the
  /// v10+ contract (and fresh installs) carry none; the 9->10 step never
  /// removed it, so upgraded databases diverge from the snapshot without
  /// this normalization. Data preserved.
  Future<void> _dropSourceTypeDefault() async {
    await _rebuildTablePreservingData('source_match_table', (ddl) {
      final clause = RegExp('"source_type"[^,)]*').firstMatch(ddl)?.group(0);
      if (clause == null) {
        throw StateError(
            'source_type missing in source_match_table during migration');
      }
      if (!clause.contains('DEFAULT')) return null;
      return ddl.replaceFirst(
        clause,
        clause.replaceFirst(RegExp(r"\s+DEFAULT\s+'[^']*'"), ''),
      );
    });
  }

  /// Moves v9->v10 quarantine markers from the live table into the
  /// quarantine table. Ordered INSERT-then-DELETE per row: a quarantine
  /// write failure throws BEFORE the live row is touched, so corruption
  /// is never lost silently. Idempotent: re-running moves zero rows.
  @visibleForTesting
  static Future<int> moveQuarantineMarkersToTable(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT id, track_id, source_info, source_type FROM source_match_table',
        )
        .get();
    var moved = 0;
    for (final row in rows) {
      Map<String, dynamic>? marker;
      try {
        final decoded = jsonDecode(row.read<String>('source_info'));
        if (decoded is Map<String, dynamic> &&
            decoded[quarantineMarkerKey] == true) {
          marker = decoded;
        }
      } catch (_) {
        continue; // Not a marker (app data or legacy '{}'): leave alone.
      }
      if (marker == null) continue;
      final id = row.read<int>('id');
      String? sourceType;
      try {
        sourceType = row.read<String>('source_type');
      } catch (_) {
        sourceType = null;
      }
      // Live row is deleted ONLY after this insert succeeds.
      await db.customStatement(
        'INSERT INTO source_match_quarantine_table '
        '(track_id, raw_source_id, reason, source_type, quarantined_at_ms) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          row.read<String>('track_id'),
          marker['rawSourceId'] as String? ?? '',
          marker['reason'] as String? ?? 'unknown',
          sourceType,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      await db.customStatement(
        'DELETE FROM source_match_table WHERE id = ?',
        [id],
      );
      moved++;
    }
    return moved;
  }

  /// Backfills source_info for pre-v10 cached rows.
  ///
  /// Historical rows store either {"info": {...}, "sources": [...]} JSON
  /// (DAB era) or a raw video id (invidious era) in source_id. Only the
  /// former upgrades losslessly: the embedded info object is validated
  /// and re-encoded, so the cache-hit path reads the migrated row.
  /// Anything else is parked as a [quarantineMarkerKey] marker (raw
  /// payload + reason preserved) instead of being deleted — the real
  /// quarantine table only exists from v12, so v11->v12 relocates these
  /// markers. Structural failures (unreadable table) propagate to the
  /// caller, which fails the migration loudly.
  Future<void> _backfillSourceInfoWithQuarantineMarkers() async {
    final rows = await customSelect(
      'SELECT id, source_id FROM source_match_table',
    ).get();
    for (final row in rows) {
      final id = row.read<int>('id');
      final raw = row.read<String>('source_id');
      String? reencoded;
      String? failure;
      try {
        final decoded = jsonDecode(raw);
        final info =
            (decoded as Map<String, dynamic>)['info'] as Map<String, dynamic>;
        final match = SpotubeAudioSourceMatchObject.fromJson(
          Map<String, dynamic>.from(info),
        );
        reencoded = jsonEncode(match.toJson());
      } catch (e) {
        failure = e.toString();
      }
      await customStatement(
        'UPDATE source_match_table SET source_info = ? WHERE id = ?',
        [
          reencoded ??
              jsonEncode({
                quarantineMarkerKey: true,
                'rawSourceId': raw,
                'reason': 'v9->v10 sourceInfo backfill: $failure',
              }),
          id,
        ],
      );
    }
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: stepByStep(
        from1To2: (m, schema) async {
          // Add invidiousInstance column to preferences table
          await m.addColumn(
            schema.preferencesTable,
            schema.preferencesTable.invidiousInstance,
          );
        },
        from2To3: (m, schema) async {
          await m.addColumn(
            schema.preferencesTable,
            schema.preferencesTable.cacheMusic,
          );
        },
        from3To4: (m, schema) async {
          await m.addColumn(
            schema.preferencesTable,
            schema.preferencesTable.youtubeClientEngine,
          );
        },
        from4To5: (m, schema) async {
          final columnName = schema.preferencesTable.accentColorScheme
              .escapedNameFor(SqlDialect.sqlite);
          final columnNameOld =
              '"${schema.preferencesTable.accentColorScheme.name}_old"';
          final tableName = schema.preferencesTable.actualTableName;
          await customStatement(
            "ALTER TABLE $tableName "
            "RENAME COLUMN $columnName to $columnNameOld",
          );
          await customStatement(
            "ALTER TABLE $tableName "
            "ADD COLUMN $columnName TEXT NOT NULL DEFAULT 'Slate:0xff64748b'",
          );
          await customStatement(
            "UPDATE $tableName "
            "SET $columnName = $columnNameOld",
          );
          await customStatement(
            "ALTER TABLE $tableName "
            "DROP COLUMN $columnNameOld",
          );
          await customStatement(
            "UPDATE $tableName "
            "SET $columnName = 'Slate:0xff64748b' WHERE $columnName = 'Blue:0xFF2196F3'",
          );
        },
        from5To6: (m, schema) async {
          try {
            await m.addColumn(
              schema.preferencesTable,
              schema.preferencesTable.connectPort,
            );
          } on DriftRemoteException catch (e) {
            // If the column already exists, ignore the error
            if (e.remoteCause !=
                'duplicate column name: ${schema.preferencesTable.connectPort.name}') {
              rethrow;
            }
          }
        },
        from6To7: (m, schema) async {
          await m.createTable(schema.metadataPluginsTable);
          await m.addColumn(
            schema.audioPlayerStateTable,
            schema.audioPlayerStateTable.currentIndex,
          );
          await m.addColumn(
            schema.audioPlayerStateTable,
            schema.audioPlayerStateTable.tracks,
          );
        },
        from7To8: (m, schema) async {
          try {
            // Columns added in v8; guarded by existence checks instead of
            // string-matching catchError, so unexpected failures surface.
            final pluginColumns = {
              schema.metadataPluginsTable.entryPoint.name:
                  schema.metadataPluginsTable.entryPoint,
              schema.metadataPluginsTable.apis.name:
                  schema.metadataPluginsTable.apis,
              schema.metadataPluginsTable.abilities.name:
                  schema.metadataPluginsTable.abilities,
              schema.metadataPluginsTable.repository.name:
                  schema.metadataPluginsTable.repository,
              schema.metadataPluginsTable.pluginApiVersion.name:
                  schema.metadataPluginsTable.pluginApiVersion,
            };
            for (final entry in pluginColumns.entries) {
              if (!(await _tableColumns('metadata_plugins_table'))
                  .contains(entry.key)) {
                await m.addColumn(schema.metadataPluginsTable, entry.value);
              }
            }
            // plugin_api_version existed since v7 WITHOUT a DB default;
            // v8 requires DEFAULT '1.0.0'. SQLite cannot ADD DEFAULT to
            // an existing column, so rebuild the table (data preserved)
            // when the default is missing. Without this, inserts relying
            // on the default fail NOT NULL, and schema validation fails.
            // v8 contract for the default (see helper docs).
            await _ensurePluginApiVersionDefault(
              'metadata_plugins_table',
              '1.0.0',
            );
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from8To9: (m, schema) async {
          // v8: metadata_plugins_table(selected, ...) ->
          // v9: plugins_table(selected_for_metadata,
          //                    selected_for_audio_source, ...).
          // NOTE: the pre-hardening code called
          // renameTable(schema.pluginsTable, "metadata_plugins_table"),
          // which renames the WRONG way (v9 view is already named
          // plugins_table) and only passed by swallowing the error.
          try {
            final hasNewTable = await _tableExists('plugins_table');
            final newColumns = hasNewTable
                ? await _tableColumns('plugins_table')
                : const <String>{};
            if (hasNewTable &&
                newColumns.contains('selected_for_metadata') &&
                newColumns.contains('selected_for_audio_source')) {
              return; // Already migrated (idempotent re-run).
            }
            if (!hasNewTable && await _tableExists('metadata_plugins_table')) {
              await customStatement(
                'ALTER TABLE metadata_plugins_table RENAME TO plugins_table',
              );
            }
            final columns = await _tableColumns('plugins_table');
            if (columns.contains('selected') &&
                !columns.contains('selected_for_metadata')) {
              await customStatement(
                'ALTER TABLE plugins_table '
                'RENAME COLUMN selected TO selected_for_metadata',
              );
            }
            if (!(await _tableColumns('plugins_table'))
                .contains('selected_for_audio_source')) {
              await m.addColumn(
                schema.pluginsTable,
                schema.pluginsTable.selectedForAudioSource,
              );
            }
            // The model default moved 1.0.0 -> 2.0.0 with no dedicated
            // step; v9+ schemas require DEFAULT '2.0.0'.
            await _ensurePluginApiVersionDefault('plugins_table', '2.0.0');
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from9To10: (m, schema) async {
          try {
            // Drop columns removed from the model in 99a84aa6 ("move away
            // from track source query and preferences audio quality and
            // codec") plus the dead piped/invidious instances. Each drop
            // is guarded by an existence check instead of
            // catchError-and-continue, so a half-migrated preferences
            // table fails loudly instead of looking handled.
            for (final obsoleteColumn in const [
              "piped_instance",
              "invidious_instance",
              "audio_quality",
              "audio_source",
              "stream_music_codec",
              "download_music_codec",
            ]) {
              if ((await _tableColumns('preferences_table'))
                  .contains(obsoleteColumn)) {
                await m.dropColumn(schema.preferencesTable, obsoleteColumn);
              }
            }
            if (!(await _tableColumns('preferences_table'))
                .contains('audio_source_id')) {
              await m.addColumn(
                schema.preferencesTable,
                preferencesTable.audioSourceId,
              );
            }
            if (!(await _tableColumns('source_match_table'))
                .contains('source_info')) {
              await m.addColumn(
                schema.sourceMatchTable,
                sourceMatchTable.sourceInfo,
              );
            }
            await _backfillSourceInfoWithQuarantineMarkers();
            await customStatement("DROP INDEX IF EXISTS uniq_track_match;");
            // v9 carried DEFAULT 'youtube' on source_type; v10+ (and fresh
            // installs) carry none. Normalize so upgraded databases match
            // the snapshot instead of diverging silently.
            await _dropSourceTypeDefault();
            if ((await _tableColumns('source_match_table'))
                .contains('source_id')) {
              await m.dropColumn(schema.sourceMatchTable, "source_id");
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from10To11: (m, schema) async {
          try {
            if (!(await _tableColumns('plugins_table'))
                .contains('selected_for_theme')) {
              await m.addColumn(
                schema.pluginsTable,
                schema.pluginsTable.selectedForTheme,
              );
            }
            // Databases that started at v10 may still carry the index
            // dropped in 9->10 (stale v10 snapshot era); ensure it is gone.
            await customStatement("DROP INDEX IF EXISTS uniq_track_match;");
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from11To12: (m, schema) async {
          try {
            await customStatement(quarantineTableDdl);
            // Same stale-index belt-and-braces as 10->11.
            await customStatement("DROP INDEX IF EXISTS uniq_track_match;");
            await moveQuarantineMarkersToTable(this);
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from12To13: (m, schema) async {
          try {
            if (!(await _tableColumns('preferences_table'))
                .contains('source_priority')) {
              await m.addColumn(
                schema.preferencesTable,
                preferencesTable.sourcePriority,
              );
            }
            if (!(await _tableColumns('preferences_table'))
                .contains('auto_download_quality')) {
              await m.addColumn(
                schema.preferencesTable,
                preferencesTable.autoDownloadQuality,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from13To14: (m, schema) async {
          try {
            if (!await _tableExists('library_snapshot_table')) {
              await m.createTable(schema.librarySnapshotTable);
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from14To15: (m, schema) async {
          try {
            // Guarded like every step since v12: user_version only moves after
            // the strategy returns, so a process killed between these two
            // ALTERs re-enters with one column already present, and an
            // unguarded ADD COLUMN would then throw on every later launch.
            if (!(await _tableColumns('preferences_table'))
                .contains('theme_transition')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.themeTransition,
              );
            }
            if (!(await _tableColumns('preferences_table'))
                .contains('theme_transition_ms')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.themeTransitionMs,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from15To16: (m, schema) async {
          try {
            // Three new tables, each guarded the same way library_snapshot
            // was at v14: user_version only advances after the strategy
            // returns, so a process killed between the CREATEs re-enters this
            // step with some tables already present.
            if (!await _tableExists('track_download_table')) {
              await m.createTable(schema.trackDownloadTable);
            }
            if (!await _tableExists('playlist_download_table')) {
              await m.createTable(schema.playlistDownloadTable);
            }
            if (!await _indexExists('unique_playlist_download')) {
              await m.createIndex(schema.uniquePlaylistDownload);
            }
            if (!await _indexExists('playlist_download_order')) {
              await m.createIndex(schema.playlistDownloadOrder);
            }
            if (!await _tableExists('playlist_download_mirror_table')) {
              await m.createTable(schema.playlistDownloadMirrorTable);
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from16To17: (m, schema) async {
          try {
            if (!(await _tableColumns('preferences_table'))
                .contains('volume_control_mode')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.volumeControlMode,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from17To18: (m, schema) async {
          try {
            // Same kill-between-ALTERs guard as every step since v12:
            // user_version only advances after the strategy returns.
            if (!(await _tableColumns('preferences_table'))
                .contains('last_update_check_ms')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.lastUpdateCheckMs,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from18To19: (m, schema) async {
          try {
            // Sidebar customization: library-tile order + pinned playlist
            // ids. Same kill-between-ALTERs guard as every step since v12.
            if (!(await _tableColumns('preferences_table'))
                .contains('sidebar_library_order')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.sidebarLibraryOrder,
              );
            }
            if (!(await _tableColumns('preferences_table'))
                .contains('pinned_playlist_ids')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.pinnedPlaylistIds,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
        from19To20: (m, schema) async {
          try {
            // Bottom-player dock style. Same kill-between-ALTERs guard as
            // every step since v12.
            if (!(await _tableColumns('preferences_table'))
                .contains('player_dock')) {
              await m.addColumn(
                schema.preferencesTable,
                schema.preferencesTable.playerDock,
              );
            }
          } catch (e, stack) {
            AppLogger.reportError(e, stack);
            rethrow;
          }
        },
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(join(dbFolder.path, 'db.sqlite'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    // sqlite3 defaults to /tmp, which is inaccessible on Android.
    final cacheBase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cacheBase;

    return NativeDatabase.createInBackground(file);
  });
}
