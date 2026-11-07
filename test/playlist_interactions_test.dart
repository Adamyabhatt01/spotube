// Interaction contracts the Playlists section and the sidebar rely on:
//
// * a main-section playlist card/tile opens from its cover and title; explicit
//   Play is the only direct-play action;
// * the sidebar's pinned row keeps its dedicated cover-play affordance while
//   its label still navigates.
//
// `PlaylistCard` has no cover-to-play wiring to pass: the presentations expose
// no cover-play parameter at all. The sidebar builds its cover tap in
// `SidebarPinTile` itself, so that wiring is asserted at the source contract
// level rather than booting playback for a widget test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/components/playbutton_view/playbutton_tile.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';

Widget _harness(Widget child) {
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

Widget _art() => const SizedBox(
      width: 120,
      height: 120,
      child: ColoredBox(color: Color(0xFF888888)),
    );

void main() {
  testWidgets('main playlist card cover opens instead of playing',
      (tester) async {
    var opens = 0;
    var plays = 0;

    await tester.pumpWidget(
      _harness(
        PlaybuttonCard(
          title: 'A playlist',
          description: 'A description',
          isPlaying: false,
          isLoading: false,
          image: _art(),
          onTap: () => opens++,
          onPlaybuttonPressed: () => plays++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PlaybuttonCard));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(plays, 0);

    await tester.tap(find.text('A playlist'));
    await tester.pumpAndSettle();
    expect(opens, 2, reason: 'the title remains an open action too');
    expect(plays, 0);
  });

  testWidgets('main playlist card play button is the direct-play action',
      (tester) async {
    var opens = 0;
    var plays = 0;

    await tester.pumpWidget(
      _harness(
        PlaybuttonCard(
          title: 'A playlist',
          isPlaying: false,
          isLoading: false,
          image: _art(),
          onTap: () => opens++,
          onPlaybuttonPressed: () => plays++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(SpotubeIcons.play));
    await tester.pumpAndSettle();

    expect(plays, 1);
    expect(opens, 0);
  });

  testWidgets('main playlist list tile cover opens instead of playing',
      (tester) async {
    var opens = 0;
    var coverPlays = 0;
    var buttonPlays = 0;

    await tester.pumpWidget(
      _harness(
        PlaybuttonTile(
          title: 'List playlist',
          isPlaying: false,
          isLoading: false,
          image: _art(),
          onTap: () => opens++,
          onPlaybuttonPressed: () => buttonPlays++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = tester.getRect(find.byType(PlaybuttonTile));
    await tester.tapAt(Offset(tile.left + 20, tile.center.dy));
    await tester.pumpAndSettle();
    expect(opens, 1, reason: 'the list cover opens the playlist');
    expect(coverPlays, 0);

    await tester.tap(find.text('List playlist'));
    await tester.pumpAndSettle();
    expect(opens, 2, reason: 'the row label still opens too');

    await tester.tap(find.byIcon(SpotubeIcons.play));
    await tester.pumpAndSettle();
    expect(buttonPlays, 1, reason: 'explicit play remains explicit');
  });

  test('sidebar pin keeps its cover-play and label-navigation wiring', () {
    final source = File('lib/modules/root/sidebar/sidebar_pin_tile.dart')
        .readAsStringSync();

    expect(
      source,
      contains('onTap: play.isLoading && !play.isPlaying'),
      reason: 'the sidebar cover must still start/resume the playlist',
    );
    expect(
      source,
      contains('openSideBarTile(context, ref, tile)'),
      reason: 'the sidebar label must open the route or a theme screen',
    );
  });
}
