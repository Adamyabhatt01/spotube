// What opening the lyrics page costs, measured rather than asserted.
//
// The report was 1-2s of stutter at the moment of opening on Android. The
// first thing this file did was falsify a hypothesis about the Plain tab: it
// is NOT built at open. `IndexedStack` used to hold both tabs, and the
// non-selected one was mounted *and laid out* - `Visibility` keeps its size,
// so the Plain tab's one giant `SelectableText` was laid out as a
// 28,800-pixel-tall text block for a 120-line lyric. The finder that "proved"
// it was absent (`find.byType`, which skips offstage elements) could not see
// an offstage-but-mounted subtree, so the guard test passed for the wrong
// reason. The Plain tab now only enters the tree once it has been asked for.
//
// What is left in the widget tree is the page-wide sigma-10 `BackdropFilter`
// (a GPU cost this file cannot see), the 30-row loading shimmer repainting
// behind it, and a scroll issued from inside `itemBuilder`.
//
// The `print`ed timings are host-side and comparable only with each other on
// this machine - they say nothing about a phone, and no budget is asserted on
// them. The structural expectations are the durable half: they fail if a fix
// gets reverted, and the Plain-tab case fails if someone puts the hidden tab
// back into the tree.
//
// The fixture track carries no album images. That is deliberate: `hasArtwork`
// false skips both the backdrop `DecorationImage` and the palette fetch, so the
// page reaches its resting state without a network round trip, and the numbers
// below are the page's own cost rather than a failing HTTP client's.
//
// The logical viewport is 480 wide, not a phone's 393. This build believes it is
// Linux (`kTitlebarVisible = kIsWindows || kIsLinux`), so the page's `TitleBar`
// reserves desktop window controls that Android would not, and at 393 that
// reservation alone overflows the header for a reason that is not the code under
// test. 480 is still narrow enough to show every defect measured here: the
// shimmer's old content measured ~810px against it.

import 'dart:async';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' show MediaKit, PlaylistMode;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/shimmers/shimmer_lyrics.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/lyrics.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/pages/lyrics/lyrics.dart';
import 'package:spotube/pages/lyrics/plain_lyrics.dart';
import 'package:spotube/pages/lyrics/synced_lyrics.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

/// A played track with an empty `album.images`, for the reasons in the header.
final _fixtureTrack = SpotubeFullTrackObject(
  id: 'lyrics-fixture-track',
  name: 'Fixture Track',
  externalUri: 'https://example.test/track/lyrics-fixture-track',
  artists: [
    SpotubeSimpleArtistObject(
      id: 'fixture-artist',
      name: 'Fixture Artist',
      externalUri: 'https://example.test/artist/fixture-artist',
    ),
  ],
  album: SpotubeSimpleAlbumObject(
    id: 'fixture-album',
    name: 'Fixture Album',
    externalUri: 'https://example.test/album/fixture-album',
    artists: const [],
    albumType: SpotubeAlbumType.album,
    images: const [],
  ),
  durationMs: 180000,
  isrc: 'USFIXTURE000001',
  explicit: false,
);

class _StubPlayer extends AudioPlayerNotifier {
  _StubPlayer();

  @override
  AudioPlayerState build() => AudioPlayerState(
        playing: false,
        loopMode: PlaylistMode.none,
        shuffled: false,
        collections: const [],
        currentIndex: 0,
        tracks: [_fixtureTrack],
        hasStarted: true,
      );
}

/// Timed lines in the shape a real LRC arrives in. The 3.2s gap is what a verse
/// runs at, and it keeps the plain view's `next - current > 700ms` branch on the
/// path a real file takes.
SubtitleSimple _lyrics(int count) => SubtitleSimple(
      uri: Uri.parse('https://example.test/lyrics.lrc'),
      name: 'Fixture lyrics',
      rating: 100,
      provider: 'fixture',
      lyrics: [
        for (var i = 0; i < count; i++)
          LyricSlice(
            time: Duration(milliseconds: i * 3200),
            text: 'Line ${i + 1} of the fixture lyric file, long enough to '
                'wrap the way a real verse does',
          ),
      ],
    );

class _AnsweredLyrics extends SyncedLyricsNotifier {
  _AnsweredLyrics(this.reply);

  final SubtitleSimple reply;

  @override
  Future<SubtitleSimple> build(SpotubeTrackObject? track) async => reply;
}

class _PendingLyrics extends SyncedLyricsNotifier {
  @override
  Future<SubtitleSimple> build(SpotubeTrackObject? track) =>
      Completer<SubtitleSimple>().future;
}

Future<void> _pumpLyrics(WidgetTester tester, Override lyrics) async {
  final container = ProviderContainer(
    overrides: [
      lyrics,
      audioPlayerProvider.overrideWith(() => _StubPlayer()),
    ],
  );
  // The container is deliberately not disposed. `themeBackdropUrlProvider`
  // watches two FutureProviders through `.select`, and a selector
  // subscription's close reads back through the container - which by the time
  // `ProviderContainer.dispose` reaches that element is already marked
  // disposed, so every test here would end in `Bad state` regardless of what
  // it asserted. Production never hits it: the app's root container outlives
  // the process. A test container that is not disposed is collected with the
  // test's own isolate.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });

  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.25;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ShadcnApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: [Locale('en')],
        home: LyricsPage(),
      ),
    ),
  );
}

/// The logical page size [_pumpLyrics] sets up.
final _page = const Size(1080, 2400) / 2.25;

void main() {
  final lyrics120 = _lyrics(120);

  late Directory tempRoot;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // SyncedLyrics attaches to the playback service in a useEffect, which
    // constructs the real player. The host provides libmpv, as in the other
    // widget tests here; nothing is loaded into it.
    MediaKit.ensureInitialized();
    // A late field in AppLogger: it can only be handed once per process, and
    // the artwork fetch failure path reports through it.
    AppLogger.initialize(false);
  });

  setUp(() async {
    // The palette hook resolves its artwork through the shared cache manager,
    // which asks path_provider for a directory that has no plugin here.
    tempRoot = await Directory.systemTemp.createTemp('lyrics_open_');
    PathProviderPlatform.instance = FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  testWidgets('opening the page does not build the hidden Plain tab',
      (tester) async {
    await _pumpLyrics(
      tester,
      syncedLyricsProvider.overrideWith(() => _AnsweredLyrics(lyrics120)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // ignore: avoid_print
    print(
      '[lyrics-open] 120 lines '
      'PlainLyrics=${find.byType(PlainLyrics).evaluate().length} '
      'SelectableText=${find.byType(SelectableText).evaluate().length} '
      'SyncedLyrics=${find.byType(SyncedLyrics).evaluate().length}',
    );

    // `skipOffstage: false` is the point of this assertion. The default
    // finder skips offstage elements, and `IndexedStack` hides its
    // non-selected children that way - so the default finder reported zero
    // even while the hidden Plain tab was mounted *and laid out* (a 120-line
    // lyric came out as a 28,800-pixel-tall text block). Flutter has no
    // "mounted but never laid out" primitive - `Offstage` lays its child out
    // with the same constraints - so the Plain tab is simply not in the tree
    // until it has been asked for.
    expect(
      find.byType(PlainLyrics, skipOffstage: false),
      findsNothing,
      reason: 'the Plain tab must not be built before it is asked for: it is '
          'one giant, non-lazy SelectableText, and laying it out costs a '
          'paragraph as tall as the whole lyric file',
    );
    expect(
      find.byType(SelectableText, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('switching to the Plain tab renders the whole lyric',
      (tester) async {
    await _pumpLyrics(
      tester,
      syncedLyricsProvider.overrideWith(() => _AnsweredLyrics(lyrics120)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Plain'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('Line 120 of the fixture'), findsOneWidget);
  });

  testWidgets('the loading shimmer fits the page and builds only what it shows',
      (tester) async {
    await _pumpLyrics(
      tester,
      syncedLyricsProvider.overrideWith(() => _PendingLyrics()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShimmerLyrics), findsOneWidget);
    final bones = find.bySubtype<Bone>();
    final widest = bones
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).width)
        .fold<double>(0, max);
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(ShimmerLyrics),
        matching: find.byType(ListView),
      ),
    );
    final rows =
        (list.childrenDelegate as SliverChildBuilderDelegate).childCount ?? 0;
    final visible = ShimmerLyrics.rowsFor(_page);
    // ignore: avoid_print
    print(
      '[lyrics-shimmer] rows=$rows widest=${widest.toStringAsFixed(1)}px '
      'page=${_page.width.toStringAsFixed(1)}px rows that fit=$visible',
    );

    // The old row was four lorem words in a centered Row: ~810px of content, so
    // every row threw an overflow assertion and the loading screen drew error
    // stripes down its sides.
    expect(widest, lessThanOrEqualTo(_page.width));

    expect(
      rows,
      lessThanOrEqualTo(visible),
      reason:
          'this list is neither scrollable nor height-bounded, so every row '
          'it is given is laid out and painted - behind the page-wide backdrop '
          'blur, for the whole duration of the fetch cascade',
    );
  });

  testWidgets('first frame cost with a full-size lyric payload',
      (tester) async {
    for (final count in const [40, 120, 300]) {
      final payload = _lyrics(count);
      final sw = Stopwatch()..start();
      await _pumpLyrics(
        tester,
        syncedLyricsProvider.overrideWith(() => _AnsweredLyrics(payload)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      sw.stop();
      // ignore: avoid_print
      print('[lyrics-open] n=$count first-frame=${sw.elapsedMilliseconds}ms');
    }
  });
}
