# Conventions

Project-specific conventions observed in the codebase. Not generic Dart advice.

## Dart / style

- Dart/Flutter, SDK `>=3.0.0 <4.0.0`. Use modern Dart (records, switches,
  extension methods). Code is formatted with `dart format`.
- Prefer immutable/freezed models for metadata (`@freezed`,
  `lib/models/metadata/`). Plain classes for lyrics models.

## Flutter / state

- Riverpod (`hooks_riverpod`) + `flutter_hooks`. Providers are the source of
  truth; widgets watch scoped slices, not whole state.
- Naming: providers end in `Provider` (e.g. `audioPlayerProvider`,
  `userPreferencesProvider`). Notifiers: `*Notifier`.
- Prefer `ref.watch(provider.select((s) => s.field))` for hot/high-frequency
  state to avoid rebuilding lists.
- Async work in providers: `FamilyAsyncNotifier` / `AsyncNotifierProviderFamily`
  where keyed per track/entity. Use `update()` as a staleness guard; use
  `ref.onDispose` to set a `cancelled` sentinel for stale scans.

## Settings / preferences

- New settings = new boolean/text column on `preferences_table`
  (`lib/models/database/tables/preferences.dart`) + entry in `defaults()`.
- Bump `schemaVersion` in `database.dart` and add a guarded `fromNToN+1` step
  (existence check via `_tableColumns(...).contains(...)`, wrap in try/catch +
  `AppLogger.reportError`). Run `make migrate`.
- Add a setter on `UserPreferencesNotifier` and a `Switch`/`ListTile` in the
  relevant settings section. Reads reactively via `userPreferencesProvider.select`.

## Database / migrations

- Drift. Schema changes require regeneration (`drift_dev make-migrations`);
  keep `drift_schemas/` and `test/drift/app_db/generated/schema_vN.dart`
  snapshots in sync (CI enforces). `test/drift/app_db/migration_test.dart`
  verifies every version pair.
- Migrations must be idempotent/guarded; quarantine corrupt rows rather than
  crash.

## Providers (lyrics)

- Implement `LyricsProvider` (`id`, `fetchLyrics`). Return **empty** `SubtitleSimple`
  on a miss/non-200 (not throw). Throw only on genuine errors; caller isolates.
- Register in `registerLyricsProviders()` in priority order; first non-empty wins.
- Cache into `lyrics_table`; note the write-only-if-empty guard.

## Error handling

- Isolate failures per provider/service; never let one provider break others.
- Report errors via `AppLogger.reportError(e, stack, context)`.
- Use sentinel exceptions (e.g. `_ScanCancelled`) for expected cancellation.

## Logging

- `AppLogger` (`lib/services/logger/logger.dart`). Do not log entire lyrics or
  full payloads.

## Testing

- `flutter_test`. Unit-test pure logic directly (e.g. `parseBetterLyricsTtml`,
  `parseTtmlTimestamp`). Provider registry tested via fake providers
  (`test/lyrics_provider_registry_test.dart`). Isolate pattern tested in
  `test/isolated_youtube_explode_test.dart`. Drift migrations in
  `test/drift/`. Hermetic (no network in unit tests).

## Dependency management

- Dependencies pinned; git deps pinned to a ref (e.g. `desktop_webview_window`).
- Avoid adding heavy native deps casually (RAM/binary budget).

## Async / concurrency

- Heavy isolate work modeled on `IsolatedYoutubeExplode`
  (`lib/services/youtube_engine/youtube_explode_engine.dart`): lazy singleton +
  single-flight init, message protocol with `[replyPort, method, args]`,
  `['ok', payload]`/`['err', msg]`, bounded handshake timeout, dispose kills
  isolate, pending calls never hang.
- Cancellation: dio `CancelToken` for downloads; `ref.onDispose` sentinel for
  provider work; isolate `dispose()` for long jobs.

## Avoid

- Creating a new expensive VM during provider recomputation (use the global cache).
- Materializing huge directory listings with `toList()` (stream/bound waves).
- Keeping full-resolution artwork unnecessarily. `UniversalImage` and
  `UniversalImage.imageProvider` take `width`/`height`; pass them whenever the
  render size is known — every branch resizes to them (`FileImage` included, via
  `ResizeImage(fit, allowUpscaling: false)`), so an unsized request is the only way
  to decode at native resolution.
- Rebuilding entire track lists for player toggles (scoped watches).
- Creating unbounded caches (bounded retention).
- Global singleton state without lifecycle justification.
- Loading entire audio files into RAM for processing.
- Assuming RSS/virtual growth automatically means a memory leak (measure RSS/PSS/heap).