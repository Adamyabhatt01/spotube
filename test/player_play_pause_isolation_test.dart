// Play/pause must repaint the transport button, not the card around it.
//
// Both bottom-chrome players used to read `audioPlayer.playingStream` in their
// own `build`. On Android a playback toggle therefore rebuilt (and repainted)
// the whole floating card, including its `BackdropFilter`. With the bottom nav
// bar's filter in the same scene, Impeller reused the previous inline pass and
// ghosted the wallpaper under the card (flutter/flutter#173622, fixed in the
// engine only from Flutter 3.38 / commit 84f5d26). The mini player is the
// reported surface; the docked controls sit inside the same kind of blurred
// card on the wide layout.
//
// The fix moves the playback watch into the button itself, so:
//   - the icon still follows playback (the provider mirrors the player's
//     playing stream), and
//   - a play/pause toggle neither rebuilds the card nor the controls row,
//     which keeps the repaint inside the button's own `RepaintBoundary`.
//
// These tests fail on the old wiring: the widgets read the global stream, not
// the provider, so their icon did not follow the provider state in the test.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:spotube/collections/intents.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/player/player_controls.dart';
import 'package:spotube/modules/player/player_overlay_collapsed.dart';
import 'package:spotube/modules/player/player_play_pause_button.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/scroll_motion.dart';

class _FrozenScrollInFlight extends ScrollInFlight {
  @override
  bool build() => true;
}

class _FakeAudioPlayerNotifier extends AudioPlayerNotifier {
  _FakeAudioPlayerNotifier(this.stub);

  AudioPlayerState stub;

  @override
  AudioPlayerState build() => stub;

  void emit(AudioPlayerState state) => this.state = state;
}

SpotubeFullTrackObject _testTrack(String id) {
  return SpotubeFullTrackObject(
    id: id,
    name: 'Test Track $id',
    externalUri: 'https://example.test/track/$id',
    artists: [
      SpotubeSimpleArtistObject(
        id: 'test-artist-$id',
        name: 'Test Artist',
        externalUri: 'https://example.test/artist/$id',
      ),
    ],
    album: SpotubeSimpleAlbumObject(
      id: 'test-album-$id',
      name: 'Test Album',
      externalUri: 'https://example.test/album/$id',
      artists: const [],
      albumType: SpotubeAlbumType.album,
    ),
    durationMs: 180000,
    isrc: 'TEST0000000$id',
    explicit: false,
  );
}

AudioPlayerState _playerState({
  required List<SpotubeTrackObject> tracks,
  required bool playing,
}) {
  return AudioPlayerState(
    playing: playing,
    loopMode: PlaylistMode.none,
    shuffled: false,
    collections: const [],
    currentIndex: 0,
    tracks: tracks,
  );
}

Widget _app(
  _FakeAudioPlayerNotifier player,
  Widget child, {
  bool isFetchingActiveTrack = false,
  bool scrollInFlight = false,
}) {
  return ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWith(() => player),
      queryingTrackInfoProvider.overrideWithValue(isFetchingActiveTrack),
      // PlayerProgress reads the theme's progress component style. Overriding
      // the theme keeps this widget test off the real plugin/theme chain,
      // whose async selector cannot be torn down cleanly with the test tree.
      themeDefinitionProvider.overrideWith((ref) async => null),
      if (scrollInFlight)
        scrollInFlightProvider.overrideWith(_FrozenScrollInFlight.new),
    ],
    child: Actions(
      actions: {PlayPauseIntent: PlayPauseAction()},
      child: ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: AppLayout(
          tokens: const ThemeTokens(),
          radii: const ThemeRadius(),
          layout: const ThemeLayout(),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAudioPlayerNotifier player,
  Widget child, {
  bool isFetchingActiveTrack = false,
  bool scrollInFlight = false,
}) async {
  await tester.pumpWidget(_app(
    player,
    child,
    isFetchingActiveTrack: isFetchingActiveTrack,
    scrollInFlight: scrollInFlight,
  ));
  await tester.pump();
}

Finder _cardFinder() => find.descendant(
      of: find.byType(PlayerOverlayCollapsedSection),
      matching: find.byType(SurfaceCard),
    );

Finder _controlsRootFinder() => find.descendant(
      of: find.byType(PlayerControls),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints == const BoxConstraints(maxWidth: 600),
      ),
    );

Finder _playPauseButtonFinder() => find.descendant(
      of: find.byType(PlayerPlayPauseButton),
      matching: find.byType(IconButton),
    );

Finder _transportButtonFinder(IconData icon) => find
    .ancestor(
      of: find.byIcon(icon),
      matching: find.byType(IconButton),
    )
    .first;

bool _isEnabled(IconButton button) =>
    button.enabled ?? (button.onPressed != null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The widgets evaluate `audioPlayer.skipToPrevious`/`skipToNext` at build
  // time, which constructs the real service; the host provides libmpv, so the
  // same init the app's other widget tests use is enough. No media is loaded.
  setUpAll(() => MediaKit.ensureInitialized());

  testWidgets('the collapsed card follows playback without rebuilding',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      PlayerOverlayCollapsedSection(panelController: PanelController()),
    );

    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget,
        reason: 'the mini player must read the app playback state');

    final card = tester.widget<SurfaceCard>(_cardFinder());

    player.emit(_playerState(tracks: [track], playing: false));
    await tester.pump();

    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
    expect(
      identical(tester.widget<SurfaceCard>(_cardFinder()), card),
      isTrue,
      reason: 'play/pause must not rebuild the blurred card around the button',
    );

    // Positive control: a genuine track change still rebuilds the card. The
    // isolation above must come from scoping, not from the card being static.
    final nextTrack = _testTrack('b');
    player.emit(_playerState(tracks: [nextTrack], playing: false));
    await tester.pump();

    expect(find.text('Test Track b'), findsOneWidget);
    expect(
      identical(tester.widget<SurfaceCard>(_cardFinder()), card),
      isFalse,
      reason: 'the card must still rebuild when the active track changes',
    );
  });

  testWidgets('the docked controls follow playback without rebuilding',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      const PlayerControls(compact: true, progressInline: false),
    );

    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);

    final root = tester.widget<Container>(_controlsRootFinder());

    player.emit(_playerState(tracks: [track], playing: false));
    await tester.pump();

    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
    expect(
      identical(tester.widget<Container>(_controlsRootFinder()), root),
      isTrue,
      reason: 'play/pause must not rebuild the transport row around the button',
    );
  });

  testWidgets(
      'audible playback keeps the transport controls enabled while resolving',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      const PlayerControls(compact: true, progressInline: false),
      isFetchingActiveTrack: true,
    );

    for (final icon in [
      SpotubeIcons.shuffle,
      SpotubeIcons.skipBack,
      SpotubeIcons.skipForward,
      SpotubeIcons.repeat,
    ]) {
      expect(
        _isEnabled(tester.widget<IconButton>(_transportButtonFinder(icon))),
        isTrue,
        reason: 'audible playback must stay controllable while the source '
            'manifest settles',
      );
    }
  });

  testWidgets('a paused resolving track disables the transport controls',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: false),
    );

    await _pump(
      tester,
      player,
      const PlayerControls(compact: true, progressInline: false),
      isFetchingActiveTrack: true,
    );

    for (final icon in [
      SpotubeIcons.shuffle,
      SpotubeIcons.skipBack,
      SpotubeIcons.skipForward,
      SpotubeIcons.repeat,
    ]) {
      expect(
        _isEnabled(tester.widget<IconButton>(_transportButtonFinder(icon))),
        isFalse,
      );
    }
  });

  testWidgets('seek stays enabled for audible playback while resolving',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      const PlayerProgress(inline: false),
      isFetchingActiveTrack: true,
    );

    expect(
      tester.widget<Slider>(find.byType(Slider)).onChanged,
      isNotNull,
      reason: 'seeking must stay usable once audio is already sounding',
    );
  });

  testWidgets('seek waits while a paused track resolves', (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: false),
    );

    await _pump(
      tester,
      player,
      const PlayerProgress(inline: false),
      isFetchingActiveTrack: true,
    );

    expect(
      tester.widget<Slider>(find.byType(Slider)).onChanged,
      isNull,
    );
  });

  testWidgets(
      'audible playback keeps an enabled pause control while source resolves',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      PlayerOverlayCollapsedSection(panelController: PanelController()),
      isFetchingActiveTrack: true,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the source manifest can settle after audio has started');
    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
    expect(
      tester.widget<IconButton>(_playPauseButtonFinder()).onPressed,
      isNotNull,
      reason: 'the user must be able to pause audible playback',
    );
  });

  testWidgets('a paused track still shows progress while source resolves',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: false),
    );

    await _pump(
      tester,
      player,
      PlayerOverlayCollapsedSection(panelController: PanelController()),
      isFetchingActiveTrack: true,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<IconButton>(_playPauseButtonFinder()).onPressed,
      isNull,
    );
  });

  testWidgets('the collapsed card keeps its frost through a scroll',
      (tester) async {
    final track = _testTrack('a');
    final player = _FakeAudioPlayerNotifier(
      _playerState(tracks: [track], playing: true),
    );

    await _pump(
      tester,
      player,
      PlayerOverlayCollapsedSection(panelController: PanelController()),
      scrollInFlight: true,
    );

    final card = tester.widget<SurfaceCard>(_cardFinder());
    expect(card.surfaceBlur, isNot(0),
        reason: 'scrolling must not strip the frosted tint from the bar');
  });
}
