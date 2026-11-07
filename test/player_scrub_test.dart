// The bottom bar's seek bar is a controlled shadcn `Slider`
// (`lib/modules/player/player_progress.dart`) that may not be fed while it
// drags: it only dispatches updates and its release when the thumb differs
// from the value it was handed, so the bar pins that value for the gesture,
// renders the thumb from the slider's own state, and lets the elapsed label
// prove the finger owns the bar. The player reports its position roughly once
// a second; these tests hold a real drag open across a position tick, assert
// the held fraction survives it, and assert the release seeks to it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/modules/theme_ui/theme_ui_node.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart' as port;
import 'package:spotube/utils/built_in_theme_colors.dart';

/// The three stream/snapshot members `useProgress` and the seek bar touch.
/// Everything else a theme path needs but this one never calls falls through
/// [noSuchMethod].
class _FakePort implements port.AudioPlayerPort {
  _FakePort(this.songLength);

  final Duration songLength;
  Duration current = Duration.zero;
  final ticks = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];

  @override
  Duration get duration => songLength;

  @override
  Duration get position => current;

  @override
  Stream<Duration> get durationStream => Stream<Duration>.fromIterable([]);

  @override
  Stream<Duration> get bufferedPositionStream => Stream<Duration>.fromIterable([
        songLength,
      ]);

  @override
  Stream<Duration> get positionTickStream => ticks.stream;

  @override
  Future<void> seek(Duration position) async {
    current = position;
    seeks.add(position);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpBar(
  WidgetTester tester,
  _FakePort player, {
  bool wavy = false,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(player.ticks.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioPlayerPortProvider.overrideWithValue(player),
        // The bar only needs the progress component style; overriding the
        // theme keeps this widget test from initializing the real plugin
        // chain (and its async selector) just to read it.
        themeDefinitionProvider.overrideWith(
          (ref) async => wavy
              ? ThemeDefinition(
                  specVersion: 4,
                  light: builtInLightThemeColors(),
                  dark: builtInDarkThemeColors(),
                  components: const {
                    'progress': {'style': 'wavy'},
                  },
                )
              : null,
        ),
        // The bar disables itself while the active track is still resolving.
        isResolvingActiveTrackProvider.overrideWith((ref) => false),
      ],
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: Scaffold(
          floatingFooter: true,
          footers: [
            SurfaceCard(
              borderRadius: BorderRadius.zero,
              child: PlayerProgress(inline: false),
            ),
          ],
          child: SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

double _barValue(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value.value;

void main() {
  testWidgets('the bar follows the finger and seeks on release',
      (tester) async {
    final player = _FakePort(const Duration(seconds: 100))
      ..current = const Duration(seconds: 30);
    await _pumpBar(tester, player);
    player.ticks.add(const Duration(seconds: 30));
    await tester.pump();
    expect(_barValue(tester), closeTo(0.3, 0.001));

    final bar = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(bar.center);
    // The move that crosses the touch slop only starts the drag — its delta is
    // consumed by the recognizer — so a value update needs a move after it.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(Offset(bar.width * 0.2, 0));
    await tester.pump();

    // The bar keeps the held fraction in its own state (the controlled value is
    // pinned to the drag start so the slider still dispatches its release),
    // and the elapsed label is the observable proof the gesture owns the bar.
    expect(find.text('00:50'), findsOneWidget);

    await gesture.up();
    await tester.pump();

    expect(player.seeks, hasLength(1));
    expect(player.seeks.single.inSeconds, closeTo(50, 1));
    expect(_barValue(tester), closeTo(0.5, 0.02));
  });

  testWidgets('the wavy bar moves the elapsed label with the finger',
      (tester) async {
    final player = _FakePort(const Duration(seconds: 100))
      ..current = const Duration(seconds: 30);
    await _pumpBar(tester, player, wavy: true);
    player.ticks.add(const Duration(seconds: 30));
    await tester.pump();

    final bar = tester.getRect(find.byType(ThemeUiWavyProgress));
    // Start on the playhead (30%) and drag to 50%. The first move is consumed
    // by the touch slop; the second is the rest of the 20% travel.
    const slop = 30.0;
    final travel = bar.width * 0.2;
    final gesture = await tester.startGesture(
      Offset(bar.left + bar.width * 0.3, bar.center.dy),
    );
    await gesture.moveBy(const Offset(slop, 0));
    await tester.pump();
    await gesture.moveBy(Offset(travel - slop, 0));
    await tester.pump();

    expect(
      find.text('00:50'),
      findsOneWidget,
      reason: 'the wavy bar reports the held fraction, not only the playhead',
    );

    await gesture.up();
    await tester.pump();

    expect(player.seeks, hasLength(1));
    expect(player.seeks.single.inSeconds, closeTo(50, 1));
  });

  testWidgets('a playhead tick during a drag does not pull the bar back',
      (tester) async {
    final player = _FakePort(const Duration(seconds: 100))
      ..current = const Duration(seconds: 30);
    await _pumpBar(tester, player);
    player.ticks.add(const Duration(seconds: 30));
    await tester.pump();

    final bar = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(bar.center);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(Offset(bar.width * 0.2, 0));
    await tester.pump();
    expect(find.text('00:50'), findsOneWidget);

    // The second the player reports while the finger is still down.
    player.ticks.add(const Duration(seconds: 31));
    await tester.pump();

    expect(
      find.text('00:50'),
      findsOneWidget,
      reason: 'the held value owns the track; the playhead may not reclaim it',
    );

    await gesture.up();
    await tester.pump();
    expect(player.seeks.last.inSeconds, closeTo(50, 1));

    // Released, the bar is the player's again.
    player.ticks.add(const Duration(seconds: 5));
    await tester.pump();
    expect(_barValue(tester), closeTo(0.05, 0.001));
  });
}
