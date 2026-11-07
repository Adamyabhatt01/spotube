// The play/pause glyph must follow the audio, not the selection.
//
// `isPlaying` on a track row means "this is the track the player is on" —
// a paused track stays the active one, so the row stays highlighted. The
// glyph used to read that same flag as "is sounding", which is why pausing
// from the sidebar or an album card left the tile showing "pause".
//
// The glyph also has to *move*: a bare `Icon(icon: playing ? a : b)` snaps
// with no motion at all, which is what made it look stuck.

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/play_pause_icon.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';

/// The shadcn theme the app's buttons live in.
Widget _app(Widget child) {
  return ShadcnApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: AppLayout(
      tokens: const ThemeTokens(),
      radii: const ThemeRadius(),
      layout: const ThemeLayout(),
      child: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('shows the pause glyph while the audio is sounding',
      (tester) async {
    await tester.pumpWidget(
      _app(const AnimatedPlayPauseIcon(isPlaying: true)),
    );

    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
    expect(find.byIcon(SpotubeIcons.play), findsNothing);
  });

  testWidgets('shows the play glyph while the audio is stopped',
      (tester) async {
    await tester.pumpWidget(
      _app(const AnimatedPlayPauseIcon(isPlaying: false)),
    );

    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
    expect(find.byIcon(SpotubeIcons.pause), findsNothing);
  });

  testWidgets('the switch animates instead of snapping', (tester) async {
    await tester.pumpWidget(
      _app(const AnimatedPlayPauseIcon(isPlaying: true)),
    );
    await tester.pumpAndSettle();

    // Flip the state.
    await tester.pumpWidget(
      _app(const AnimatedPlayPauseIcon(isPlaying: false)),
    );
    await tester.pump();

    // Mid-transition both glyphs are on screen: that is the animation.
    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byIcon(SpotubeIcons.pause), findsNothing);
    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
  });

  // The album/playlist header puts the glyph in a Button's `leading` slot,
  // not an IconButton's `icon` slot: the two wrap it differently.
  testWidgets('renders inside a Button leading slot', (tester) async {
    await tester.pumpWidget(
      _app(
        Button.primary(
          leading: const AnimatedPlayPauseIcon(isPlaying: true),
          onPressed: () {},
          child: const Text('Play'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);

    final size = tester.getSize(find.byIcon(SpotubeIcons.pause));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });

  testWidgets('renders inside an IconButton icon slot', (tester) async {
    await tester.pumpWidget(
      _app(
        IconButton.secondary(
          icon: const AnimatedPlayPauseIcon(isPlaying: false),
          onPressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);

    final size = tester.getSize(find.byIcon(SpotubeIcons.play));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });
}
