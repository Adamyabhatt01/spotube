// Phase 8 hands the library to a theme: create / rename / delete / add-to and
// pin. Those are the first theme verbs that mutate the user's own Spotify
// account, so two things are pinned here that the audio phases never needed —
// the `library.write` gate that refuses an un-declared theme, and the
// confirmation that stands between a `deletePlaylist` action and an
// irreversible write. The plugin stack is faked exactly as playlist_create_test
// does it (no database): a scripted endpoint, a recording saved-playlists
// notifier and a no-op mirror, so each assertion is about what the dispatcher
// routed, not about the network.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/provider/metadata_plugin/core/auth.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';
import 'package:spotube/provider/playlist_download_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/metadata.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

import 'support/common_fakes.dart';

SpotubeUserObject _user(String id) => SpotubeUserObject(
      id: id,
      name: 'User $id',
      externalUri: 'https://open.spotify.com/user/$id',
    );

SpotubeFullPlaylistObject _full(String id, String name) =>
    SpotubeFullPlaylistObject(
      id: id,
      name: name,
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
      collaborative: false,
      public: false,
    );

SpotubeSimplePlaylistObject _simple(String id) => SpotubeSimplePlaylistObject(
      id: id,
      name: 'Playlist $id',
      description: '',
      externalUri: 'https://open.spotify.com/playlist/$id',
      owner: _user('me'),
      images: const [],
    );

SpotubePaginationResponseObject<SpotubeSimplePlaylistObject> _page(
  List<SpotubeSimplePlaylistObject> items,
) =>
    SpotubePaginationResponseObject(
      limit: items.length,
      nextOffset: null,
      total: items.length,
      hasMore: false,
      items: items,
    );

class _FakePlaylistEndpoint implements MetadataPluginPlaylistEndpoint {
  final createNames = <String>[];
  final updateCalls = <({String id, String? name})>[];
  int getPlaylistCalls = 0;

  @override
  Future<SpotubeFullPlaylistObject?> create(
    String userId, {
    required String name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    createNames.add(name);
    return _full('new-id', name);
  }

  @override
  Future<void> update(
    String playlistId, {
    String? name,
    String? description,
    bool? public,
    bool? collaborative,
  }) async {
    updateCalls.add((id: playlistId, name: name));
  }

  @override
  Future<SpotubeFullPlaylistObject> getPlaylist(String id) async {
    getPlaylistCalls++;
    return _full(id, 'Playlist $id');
  }

  // create() follows the new playlist into the library in the background; the
  // fake accepts it so that unawaited work does not surface as a test error.
  @override
  Future<void> save(String playlistId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the dispatcher asked the library to do. `addTracks`, `delete`
/// and `updatePlaylist` are overridden so the calls stop here instead of
/// reaching the plugin or a database.
class _FakeSavedPlaylists extends MetadataPluginSavedPlaylistsNotifier {
  final addTrackCalls = <({String playlistId, List<String> trackIds})>[];
  final deleteCalls = <String>[];

  @override
  Future<SpotubePaginationResponseObject<SpotubeSimplePlaylistObject>>
      build() async => _page(const []);

  @override
  Future<void> addTracks(String playlistId, List<String> trackIds) async {
    addTrackCalls.add((playlistId: playlistId, trackIds: List.of(trackIds)));
  }

  @override
  Future<void> delete(String playlistId) async => deleteCalls.add(playlistId);

  @override
  void updatePlaylist(SpotubeSimplePlaylistObject playlist) {}
}

class _AlwaysAuthenticated extends MetadataPluginAuthenticatedNotifier {
  @override
  Future<bool> build() async => true;
}

/// `modify` writes the new metadata through the offline mirror only when the
/// playlist is loaded; `implements` (rather than `extends`) so no database or
/// download manager is needed to stand it up.
class _FakeMirror implements PlaylistMirrorService {
  final updateCalls = <SpotubeSimplePlaylistObject>[];

  @override
  Future<void> updateMetadata(SpotubeSimplePlaylistObject playlist) async =>
      updateCalls.add(playlist);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMetadataPlugin implements MetadataPlugin {
  _FakeMetadataPlugin(this.playlist);

  @override
  final MetadataPluginPlaylistEndpoint playlist;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ThemeDefinition _theme() => ThemeDefinition(
      specVersion: 4,
      light: builtInLightThemeColors(),
      dark: builtInDarkThemeColors(),
    );

ProviderContainer _container({
  required ThemeUiDocument ui,
  required _FakePlaylistEndpoint playlist,
  required _FakeSavedPlaylists saved,
  required _FakeMirror mirror,
}) {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith((ref) async => _theme()),
      themeUiProvider.overrideWith((ref) async => ui),
      themeUiAssetsProvider.overrideWith((ref) async => const ThemeUiAssets()),
      themeUiFontsProvider.overrideWith((ref) async {}),
      userPreferencesProvider.overrideWith(
        () => StubPrefsNotifier(PreferencesTable.defaults()),
      ),
      metadataPluginProvider.overrideWith(
        (ref) async => _FakeMetadataPlugin(playlist),
      ),
      metadataPluginUserProvider.overrideWith((ref) async => _user('me')),
      metadataPluginAuthenticatedProvider.overrideWith(
        () => _AlwaysAuthenticated(),
      ),
      metadataPluginSavedPlaylistsProvider.overrideWith(() => saved),
      playlistMirrorServiceProvider.overrideWithValue(mirror),
      playlistCoverRefreshDelayProvider.overrideWithValue(Duration.zero),
    ],
  );
}

void main() {
  group('parser', () {
    test('the four library-write verbs are host-known', () {
      for (final verb in [
        'createPlaylist',
        'renamePlaylist',
        'deletePlaylist',
        'addToPlaylist',
      ]) {
        expect(
          ThemeUiAction.tryParse({'type': verb}),
          isNotNull,
          reason: verb,
        );
      }
    });
  });

  group('actions', () {
    Future<
        ({
          BuildContext context,
          WidgetRef ref,
          ProviderContainer container,
        })> pump(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      late BuildContext capturedContext;
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: AppLayout(
              tokens: const ThemeTokens(),
              radii: const ThemeRadius(),
              layout: const ThemeLayout(),
              child: Consumer(
                builder: (context, ref, _) {
                  capturedContext = context;
                  capturedRef = ref;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (
        context: capturedContext,
        ref: capturedRef,
        container: container,
      );
    }

    // Reading the playlist family arms riverpod's five-minute auto-dispose
    // timer; run the fake clock past it so the test ends with none pending.
    Future<void> flush(WidgetTester tester) =>
        tester.pump(const Duration(minutes: 6));

    testWidgets('createPlaylist without library.write is refused',
        (tester) async {
      final playlist = _FakePlaylistEndpoint();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.read']),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('createPlaylist', {'name': 'Quiet'}),
      );
      expect(playlist.createNames, isEmpty);
    });

    testWidgets('createPlaylist with library.write passes a trimmed name',
        (tester) async {
      final playlist = _FakePlaylistEndpoint();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('createPlaylist', {'name': '  Road trip  '}),
      );
      await flush(tester);

      expect(playlist.createNames, ['Road trip']);
    });

    testWidgets('createPlaylist ignores a blank or absent name',
        (tester) async {
      final playlist = _FakePlaylistEndpoint();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('createPlaylist', {'name': '   '}),
      );
      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('createPlaylist'),
      );
      expect(playlist.createNames, isEmpty);
    });

    testWidgets('renamePlaylist updates the name and the local mirror',
        (tester) async {
      final playlist = _FakePlaylistEndpoint();
      final mirror = _FakeMirror();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: mirror,
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('renamePlaylist', {
          'playlist': 'pl-7',
          'name': 'Renamed',
        }),
      );

      expect(playlist.updateCalls, [(id: 'pl-7', name: 'Renamed')]);
      expect(mirror.updateCalls.map((p) => p.name), contains('Renamed'));
      await flush(tester);
    });

    testWidgets('renamePlaylist without the capability or a name is a no-op',
        (tester) async {
      final playlist = _FakePlaylistEndpoint();
      final denied = _container(
        ui: const ThemeUiDocument(),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: _FakeMirror(),
      );
      addTearDown(denied.dispose);
      final deniedCtx = await pump(tester, denied);
      await dispatchThemeUiAction(
        deniedCtx.context,
        deniedCtx.container,
        const ThemeUiAction(
            'renamePlaylist', {'playlist': 'pl-7', 'name': 'X'}),
      );
      expect(playlist.updateCalls, isEmpty);

      final allowed = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: playlist,
        saved: _FakeSavedPlaylists(),
        mirror: _FakeMirror(),
      );
      addTearDown(allowed.dispose);
      final allowedCtx = await pump(tester, allowed);
      await dispatchThemeUiAction(
        allowedCtx.context,
        allowedCtx.container,
        const ThemeUiAction('renamePlaylist', {'playlist': 'pl-7'}),
      );
      expect(playlist.updateCalls, isEmpty);
    });

    testWidgets('addToPlaylist resolves ids, dedupes and caps the batch',
        (tester) async {
      final saved = _FakeSavedPlaylists();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: _FakePlaylistEndpoint(),
        saved: saved,
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('addToPlaylist', {
          'playlist': 'pl-1',
          'track': 't-1',
        }),
      );
      expect(saved.addTrackCalls.single.playlistId, 'pl-1');
      expect(saved.addTrackCalls.single.trackIds, ['t-1']);

      // A repeated id collapses; the target may be named by an object; non-
      // string and empty entries are dropped.
      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        ThemeUiAction('addToPlaylist', {
          'playlist': _simple('pl-2'),
          'trackIds': ['a', 'a', 'b', 3, '', 'c'],
        }),
      );
      expect(saved.addTrackCalls.last.playlistId, 'pl-2');
      expect(saved.addTrackCalls.last.trackIds, ['a', 'b', 'c']);

      // Above the cap the batch is truncated, not rejected outright.
      final many = [for (var i = 0; i < 80; i++) 'x$i'];
      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        ThemeUiAction('addToPlaylist', {'playlist': 'pl-3', 'trackIds': many}),
      );
      expect(saved.addTrackCalls.last.trackIds, hasLength(50));
    });

    testWidgets('addToPlaylist needs a target and at least one track',
        (tester) async {
      final saved = _FakeSavedPlaylists();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: _FakePlaylistEndpoint(),
        saved: saved,
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('addToPlaylist', {'track': 't-1'}),
      );
      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('addToPlaylist', {'playlist': 'pl-1'}),
      );
      expect(saved.addTrackCalls, isEmpty);
    });

    testWidgets('deletePlaylist only deletes once the prompt is confirmed',
        (tester) async {
      final saved = _FakeSavedPlaylists();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: _FakePlaylistEndpoint(),
        saved: saved,
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      final dispatched = dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('deletePlaylist', {'playlist': 'pl-x'}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The prompt is on screen and nothing has been deleted yet.
      expect(find.text('Delete'), findsOneWidget);
      expect(saved.deleteCalls, isEmpty);

      await tester.tap(find.text('Delete'));
      await dispatched;

      expect(saved.deleteCalls, ['pl-x']);
      await flush(tester);
    });

    testWidgets('deletePlaylist leaves the playlist alone when dismissed',
        (tester) async {
      final saved = _FakeSavedPlaylists();
      final container = _container(
        ui: const ThemeUiDocument(capabilities: ['library.write']),
        playlist: _FakePlaylistEndpoint(),
        saved: saved,
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      final dispatched = dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('deletePlaylist', {'playlist': 'pl-x'}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final cancel = AppLocalizations.of(ctx.context)!.cancel;
      await tester.tap(find.text(cancel));
      await dispatched;

      expect(saved.deleteCalls, isEmpty);
    });

    testWidgets('deletePlaylist without the capability never prompts',
        (tester) async {
      final saved = _FakeSavedPlaylists();
      final container = _container(
        ui: const ThemeUiDocument(),
        playlist: _FakePlaylistEndpoint(),
        saved: saved,
        mirror: _FakeMirror(),
      );
      addTearDown(container.dispose);
      final ctx = await pump(tester, container);

      await dispatchThemeUiAction(
        ctx.context,
        ctx.container,
        const ThemeUiAction('deletePlaylist', {'playlist': 'pl-x'}),
      );
      await tester.pump();

      expect(find.text('Delete'), findsNothing);
      expect(saved.deleteCalls, isEmpty);
    });
  });
}
