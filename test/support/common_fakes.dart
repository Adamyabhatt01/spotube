// Shared test doubles, extracted verbatim from the test files that each
// declared their own copy. Only byte-identical, behavior-free harness lives
// here: path-provider fakes, stub notifiers and the in-memory database
// constructor. Anything with per-test behavior (stub metadata plugins with
// scripted endpoints, track factories whose payloads assertions depend on,
// the sync-vs-async authenticated notifiers) stays in its own file on
// purpose — unifying those would trade explicit fixtures for hidden coupling.

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/audio_source/quality_presets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/sourced_track/sourced_track.dart';

/// Serves temp/support/documents paths from a scratch dir. The download
/// manager, the cache manager and the local library resolve their
/// directories through path_provider, which has no plugin in unit tests.
class FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

/// A user-preferences notifier pinned to one row, so tests control settings
/// (notably `downloadLocation`) without a database round trip.
class StubPrefsNotifier extends UserPreferencesNotifier {
  StubPrefsNotifier(this.stub);

  PreferencesTableData stub;

  @override
  PreferencesTableData build() => stub;
}

/// An empty metadata-plugin state: no default plugin, so code under test
/// takes its no-plugin branches without spinning up a Hetu VM.
class EmptyMetadataPluginNotifier extends MetadataPluginNotifier {
  @override
  Future<MetadataPluginState> build() async => const MetadataPluginState();
}

/// Fixed audio-source presets so download workers immediately see the
/// test's container — no dependency on the plugin-loading rebuild lifecycle.
class FixedPresetsNotifier extends AudioSourceAvailableQualityPresetsNotifier {
  FixedPresetsNotifier(this.initial);

  final AudioSourcePresetsState initial;

  @override
  AudioSourcePresetsState build() => initial;
}

/// A sourced-track notifier that fails loudly: for tests whose tracks
/// already have their files on disk, resolving a source would mean the
/// test leaked into the network instead of short-circuiting on existence.
class NeverResolvesSourcedTrackNotifier extends SourcedTrackNotifier {
  @override
  Future<SourcedTrack> build(SpotubeFullTrackObject query) {
    throw StateError('these tests must not resolve a source');
  }
}

/// An isolated in-memory database. Production code must keep using
/// [AppDatabase.new]; this is only for tests that need a real Drift
/// connection without touching the user's db.sqlite.
AppDatabase newMemoryDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());
