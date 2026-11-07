// A track row's play/pause glyph must follow the audio, not the selection.
//
// `TrackTile.isPlaying` means "this is the track the player is on" — it
// survives a pause, so the row stays highlighted. The glyph used to read
// that same flag as "is sounding", so pausing from the sidebar or an album
// card left the row showing "pause" with nothing playing.
//
// The tile reads the real playback state itself (`AudioPlayerState.playing`,
// kept in sync from `audioPlayer.playingStream`) rather than trusting the
// caller to pass a second flag — the caller only knows about the selection.

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/track_presentation/presentation_props.dart';
import 'package:spotube/components/track_tile/track_tile.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/querying_track_info.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/blacklist_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart'
    show SpotubeMedia;

class _StubPlayerNotifier extends AudioPlayerNotifier {
  _StubPlayerNotifier(this.initialState);

  final AudioPlayerState initialState;

  @override
  AudioPlayerState build() => initialState;

  @override
  List<Media> get backendMedias => const [];

  @override
  int get backendCurrentIndex => 0;

  @override
  Future<void> addMediaToBackend(SpotubeMedia media) async {}

  @override
  Future<void> insertMediaIntoBackend(SpotubeMedia media, int index) async {}

  @override
  Future<void> removeMediaFromBackend(int index) async {}

  @override
  Future<void> openPlaylistOnBackend(
    List<SpotubeMedia> medias, {
    required int initialIndex,
    required bool autoPlay,
  }) async {}
}

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mounts one row.
  ///
  /// [playerIsPlaying] is the real playback state; [rowIsActive] is what the
  /// caller passes the tile — "this row is the track the player is on".
  Future<void> mount(
    WidgetTester tester, {
    required bool playerIsPlaying,
    required bool rowIsActive,
    bool isFetchingActiveTrack = false,
  }) async {
    final state = AudioPlayerState(
      playing: playerIsPlaying,
      loopMode: PlaylistMode.none,
      shuffled: false,
      collections: const [],
      currentIndex: 0,
      tracks: rowIsActive ? [_track] : const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerProvider.overrideWith(() => _StubPlayerNotifier(state)),
          blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier()),
          queryingTrackInfoProvider.overrideWithValue(isFetchingActiveTrack),
        ],
        child: Data<TrackPresentationOptions>.inherit(
          data: TrackPresentationOptions(
            collection: SpotubeSimplePlaylistObject(
              id: 'pl-1',
              name: 'Playlist',
              description: '',
              externalUri: 'https://example.test/playlist/pl-1',
              owner: SpotubeUserObject(
                id: 'owner',
                name: 'Owner',
                externalUri: '',
              ),
            ),
            title: 'Playlist',
            image: '',
            routePath: '/playlist/pl-1',
            tracks: [_track],
            pagination: PaginationProps(
              hasNextPage: false,
              isLoading: false,
              onFetchMore: () {},
              onRefresh: () async {},
              onFetchAll: () async => [_track],
            ),
          ),
          child: ShadcnApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: AppLayout(
              tokens: const ThemeTokens(),
              radii: const ThemeRadius(),
              layout: const ThemeLayout(),
              child: Center(
                child: SizedBox(
                  width: 600,
                  child: TrackTile(
                    index: 0,
                    track: _track,
                    isPlaying: rowIsActive,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an active row that is sounding shows the pause glyph',
      (tester) async {
    await mount(tester, playerIsPlaying: true, rowIsActive: true);

    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
  });

  testWidgets('an active row that is paused does not show the pause glyph',
      (tester) async {
    // The regression: the row is still the active track, but nothing is
    // playing, so "pause" would be a lie.
    await mount(tester, playerIsPlaying: false, rowIsActive: true);

    expect(find.byIcon(SpotubeIcons.pause), findsNothing);
  });

  testWidgets('source resolution cannot turn audible playback into a spinner',
      (tester) async {
    await mount(
      tester,
      playerIsPlaying: true,
      rowIsActive: true,
      isFetchingActiveTrack: true,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
  });

  testWidgets('a paused resolving row shows a spinner, not a pause glyph',
      (tester) async {
    await mount(
      tester,
      playerIsPlaying: false,
      rowIsActive: true,
      isFetchingActiveTrack: true,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(SpotubeIcons.pause), findsNothing);
  });

  testWidgets('an inactive row ignores the active track resolving',
      (tester) async {
    await mount(
      tester,
      playerIsPlaying: false,
      rowIsActive: false,
      isFetchingActiveTrack: true,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a row that is not the active track shows no glyph',
      (tester) async {
    await mount(tester, playerIsPlaying: true, rowIsActive: false);

    expect(find.byIcon(SpotubeIcons.pause), findsNothing);
  });
}
