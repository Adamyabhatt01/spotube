// Download row context menu contracts: the file-backed rows (Open folder,
// Remove download) only appear for a completed download whose file the local
// library scan can find, user config hides/reorders like any other target,
// and Remove download confirms before deleting the file off disk.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/modules/library/user_downloads/download_context_menu.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/download_manager/download_tasks.dart';
import 'package:spotube/provider/local_tracks/local_tracks_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';

final _track = SpotubeFullTrackObject(
  id: 't1',
  name: 'Wassup',
  externalUri: 'https://example.test/track/t1',
  artists: [
    SpotubeSimpleArtistObject(
      id: 'a1',
      name: 'Flawed',
      externalUri: 'https://example.test/artist/a1',
    ),
  ],
  album: SpotubeSimpleAlbumObject(
    id: 'al1',
    name: 'Singles',
    externalUri: 'https://example.test/album/al1',
    artists: const [],
    albumType: SpotubeAlbumType.album,
  ),
  durationMs: 274000,
  isrc: '',
  explicit: false,
);

SpotubeLocalTrackObject _localTrack(String path) {
  return SpotubeLocalTrackObject(
    id: path,
    name: 'Wassup',
    externalUri: 'file://$path',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'a1',
        name: 'Flawed',
        externalUri: 'file://$path',
      ),
    ],
    album: _track.album,
    durationMs: 274000,
    path: path,
  );
}

class _StubConfigNotifier extends ContextMenuConfigNotifier {
  _StubConfigNotifier(this.config);

  final ContextMenuConfig config;

  @override
  ContextMenuConfig build() => config;
}

ProviderContainer _container({
  Map<String, List<SpotubeLocalTrackObject>> library = const {},
  ContextMenuConfig? config,
}) {
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
      localTracksProvider.overrideWith((ref) async => library),
      if (config != null)
        contextMenuConfigProvider
            .overrideWith(() => _StubConfigNotifier(config)),
    ],
  );
}

Widget _harness(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: ShadcnApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      home: Scaffold(
        child: AppLayout(
          tokens: const ThemeTokens(),
          radii: const ThemeRadius(),
          layout: const ThemeLayout(),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

DownloadTask _task(DownloadStatus status) {
  return DownloadTask(
    track: _track,
    status: status,
    cancelToken: CancelToken(),
  );
}

Widget _menu(DownloadTask task) {
  return DownloadContextMenu(
    task: task,
    child: const SizedBox(
      key: Key('download-target'),
      width: 320,
      height: 60,
      child: ColoredBox(color: Color(0xFF888888)),
    ),
  );
}

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('download-target'))),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    DownloadTask task, {
    Map<String, List<SpotubeLocalTrackObject>> library = const {},
    ContextMenuConfig? config,
  }) async {
    final container = _container(library: library, config: config);
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(_menu(task), container));
    await tester.pumpAndSettle();

    // The menu resolves state on open without subscribing; keep the scan
    // provider alive here so its first read already carries data, like in
    // the app where the downloads page has loaded the local library.
    final sub = container.listen(localTracksProvider, (_, __) {});
    addTearDown(sub.close);
    await tester.pumpAndSettle();
  }

  testWidgets('a completed download offers play, folder, remove and copy',
      (tester) async {
    await pumpMenu(
      tester,
      _task(DownloadStatus.completed),
      library: {
        '/music': [_localTrack('/music/Wassup.mp3')],
      },
    );
    await _openMenu(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Open folder'), findsOneWidget);
    expect(find.text('Remove download'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
  });

  testWidgets('file rows hide when the local scan cannot find the track',
      (tester) async {
    await pumpMenu(tester, _task(DownloadStatus.completed));
    await _openMenu(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Open folder'), findsNothing);
    expect(find.text('Remove download'), findsNothing);
  });

  testWidgets('the user can hide a download action', (tester) async {
    await pumpMenu(
      tester,
      _task(DownloadStatus.downloading),
      config: ContextMenuConfig(
        targets: {
          ContextMenuTarget.download.id: const ContextMenuTargetConfig(
            hidden: {'copyLink'},
          ),
        },
      ),
    );
    await _openMenu(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Copy Link'), findsNothing);
  });

  testWidgets('remove download confirms, then deletes the file',
      (tester) async {
    // Synchronous setup: the widget-test zone fakes the clock, so async file
    // IO would never complete there.
    final dir = Directory.systemTemp.createTempSync('spotube-menu');
    final file = File('${dir.path}/Wassup.mp3')..writeAsStringSync('audio');
    addTearDown(() => dir.deleteSync(recursive: true));

    await pumpMenu(
      tester,
      _task(DownloadStatus.completed),
      library: {
        dir.path: [_localTrack(file.path)],
      },
    );
    await _openMenu(tester);
    await tester.tap(find.text('Remove download'));
    await tester.pumpAndSettle();

    // The confirmation comes first; nothing is deleted until it is accepted.
    expect(find.text('Wassup'), findsWidgets);
    expect(file.existsSync(), isTrue);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(Button, 'Delete').last);
      await tester.pump();
      // The delete runs on the real event loop inside the menu callback.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(file.existsSync(), isFalse);
  });

  testWidgets('copy link writes the track URI', (tester) async {
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

    await pumpMenu(tester, _task(DownloadStatus.completed));
    await _openMenu(tester);
    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();

    expect(copied, 'https://example.test/track/t1');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
