// Playlist card context menu contracts: the labels follow the playback and
// pin state, Delete only exists for owned playlists, Copy link writes the
// playlist URI, and Delete defers to the next frame so the menu can dismiss
// before the confirmation dialog opens.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/playlist/playlist_context_menu.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith(
        (ref) async => ThemeDefinition(
          specVersion: 4,
          light: builtInLightThemeColors(),
          dark: builtInDarkThemeColors(),
        ),
      ),
      themeUiProvider.overrideWith((ref) async => null),
    ],
  );
}

Widget _harness(
  Widget child,
  ProviderContainer container, {
  ThemeLayout layout = const ThemeLayout(),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        child: AppLayout(
          tokens: const ThemeTokens(),
          radii: const ThemeRadius(),
          layout: layout,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

SpotubeSimplePlaylistObject _playlist({
  String externalUri = 'https://open.spotify.com/playlist/abc',
}) {
  return SpotubeSimplePlaylistObject(
    id: 'playlist-1',
    name: 'My Playlist',
    description: 'A playlist',
    externalUri: externalUri,
    owner: SpotubeUserObject(
      id: 'owner-1',
      name: 'Owner',
      externalUri: 'https://example.test/user/owner-1',
    ),
  );
}

Widget _menu({
  required SpotubeSimplePlaylistObject playlist,
  bool isOwner = true,
  bool isPinned = false,
  bool isPlaying = false,
  VoidCallback? onPlayPause,
  VoidCallback? onTogglePin,
  Future<void> Function()? onDelete,
}) {
  return PlaylistContextMenu(
    playlist: playlist,
    isOwner: isOwner,
    isPinned: isPinned,
    isPlaying: isPlaying,
    isLoading: false,
    isQueueLoading: false,
    onOpen: () {},
    onPlayPause: onPlayPause ?? () {},
    onAddToQueue: () {},
    onTogglePin: onTogglePin ?? () {},
    onDelete: onDelete ?? () async {},
    child: const SizedBox(
      key: Key('playlist-target'),
      width: 240,
      height: 120,
      child: ColoredBox(color: Color(0xFF888888)),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('playlist-target'))),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    Widget Function() menu, {
    ThemeLayout layout = const ThemeLayout(),
  }) async {
    final container = _container();
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(menu(), container, layout: layout));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'owned playlist offers play, queue, pin, download, rename, copy and delete',
      (tester) async {
    await pumpMenu(tester, () => _menu(playlist: _playlist()));
    await _openMenu(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Pin to Sidebar'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('Delete Playlist'), findsOneWidget);
  });

  testWidgets('a playlist the user does not own keeps download but not rename',
      (tester) async {
    await pumpMenu(
      tester,
      () => _menu(playlist: _playlist(), isOwner: false),
    );
    await _openMenu(tester);

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('Delete Playlist'), findsNothing);
  });

  testWidgets('labels follow the playing and pinned state', (tester) async {
    await pumpMenu(
      tester,
      () => _menu(playlist: _playlist(), isPlaying: true, isPinned: true),
    );
    await _openMenu(tester);

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Unpin from Sidebar'), findsOneWidget);
  });

  testWidgets('several pin targets show a checked submenu', (tester) async {
    var pins = 0;
    await pumpMenu(
      tester,
      () => _menu(
        playlist: _playlist(),
        isPinned: true,
        onTogglePin: () => pins++,
      ),
      layout: const ThemeLayout(
        pinTargets: [
          ThemePinTarget(id: 'sidebar', label: 'Sidebar'),
          ThemePinTarget(id: 'bar', label: 'Top bar'),
        ],
      ),
    );
    await _openMenu(tester);

    expect(find.text('Pin to…'), findsOneWidget);
    expect(find.text('Unpin from Sidebar'), findsNothing);

    await tester.tap(find.text('Pin to…'));
    await tester.pumpAndSettle();

    expect(find.text('Unpin from Sidebar'), findsOneWidget);
    expect(find.text('Pin to Top bar'), findsOneWidget);
    // One checkmark for the target the playlist is already pinned to.
    expect(find.byIcon(RadixIcons.check), findsOneWidget);

    await tester.tap(find.text('Unpin from Sidebar'));
    await tester.pumpAndSettle();
    expect(pins, 1);
  });

  testWidgets('copy link writes the playlist URI', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await pumpMenu(tester, () => _menu(playlist: _playlist()));
    await _openMenu(tester);
    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();

    expect(copied, 'https://open.spotify.com/playlist/abc');

    // Let the confirmation toast finish its own timer before the tree tears
    // down; a pending timer fails the test binding's invariants.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('delete is deferred until the menu has dismissed',
      (tester) async {
    var deletes = 0;
    await pumpMenu(
      tester,
      () => _menu(
        playlist: _playlist(),
        onDelete: () async => deletes++,
      ),
    );
    await _openMenu(tester);
    await tester.tap(find.text('Delete Playlist'));

    // The row is gone immediately; the callback waits for the next frame.
    expect(deletes, 0);
    await tester.pumpAndSettle();
    expect(deletes, 1);
  });

  testWidgets('Shift+F10 opens the menu at the item', (tester) async {
    await pumpMenu(tester, () => _menu(playlist: _playlist()));

    // The region owns a focus node around the item; keyboard menus open on
    // the focused row only, so focus it the way tab-traversal would.
    final targetContext =
        find.byKey(const Key('playlist-target')).evaluate().single;
    Focus.of(targetContext).requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.text('Delete Playlist'), findsOneWidget);

    // Dismissing the overlay restores focus to the region, so the keyboard
    // shortcut works again without tabbing back to the item.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Delete Playlist'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Delete Playlist'), findsOneWidget);
  });
}
