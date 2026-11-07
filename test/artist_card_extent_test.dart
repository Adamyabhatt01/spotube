// The artist card is the tallest card the home rows and artist grids show, and
// its cell height used to be a per-page guess: `isArtist ? 250 : 225` where
// `isArtist` meant *every* item, and `mainAxisExtent: smAndDown ? 225 : 250`
// with no theme scaling anywhere. A browse section that mixed one artist in
// with albums handed the artist card 225 - 16 of padding and clipped its badge
// row — "A RenderFlex overflowed by 3.0 pixels on the bottom" on every startup.
// Cell sizes are theme-plugin tokens now (see theme_layout_tokens_test.dart), so
// these tests also pin what happens at the ends of the ranges a plugin can ask for.
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/fake.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/modules/artist/artist_card.dart';
import 'package:spotube/provider/blacklist_provider.dart';

class _EmptyBlacklistNotifier extends BlackListNotifier {
  @override
  Future<List<BlacklistTableData>> build() async => [];
}

Future<void> _pumpAtExtent(
  WidgetTester tester, {
  required double scaling,
  required double Function(BuildContext context) extent,
  double Function(BuildContext context)? cellWidth,
  ThemeTokens? tokens,
  ThemeRadius? radii,
  Widget? card,
}) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final content = Builder(
    builder: (context) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        // The grid tile a card actually gets: maxCrossAxisExtent comes from the
        // same token, so the tile is as wide as the card asks to be.
        width: cellWidth?.call(context) ?? 260,
        height: extent(context),
        child: card ?? ArtistCard(FakeData.artist),
      ),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blacklistProvider.overrideWith(() => _EmptyBlacklistNotifier())
      ],
      child: ShadcnApp(
        scaling: AdaptiveScaling(scaling),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: AppLayout(
          tokens: tokens ?? const ThemeTokens(),
          radii: radii ?? const ThemeRadius(),
          child: content,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('artist card fits the extent declared for it', (tester) async {
    await _pumpAtExtent(
      tester,
      scaling: 1,
      extent: (context) => playbuttonCardExtent(context, hasArtist: true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the extent tracks theme scaling, so bigger fonts still fit',
      (tester) async {
    for (final scaling in [1.25, 1.5, 2.0]) {
      await _pumpAtExtent(
        tester,
        scaling: scaling,
        extent: (context) => playbuttonCardExtent(context, hasArtist: true),
      );
      expect(tester.takeException(), isNull, reason: 'scaling $scaling');
    }
  });

  testWidgets('a too-short cell shrinks the name instead of clipping the badge',
      (tester) async {
    // The old card put a Spacer between name and badge, so a cell sized for
    // albums pushed the badge out of view. The name now absorbs the squeeze.
    await _pumpAtExtent(
      tester,
      scaling: 1,
      extent: (context) => playbuttonCardExtent(context, hasArtist: false),
    );
    expect(tester.takeException(), isNull);

    final cell = tester.getRect(find.byType(ArtistCard));
    final badge = tester.getRect(find.byType(SecondaryBadge));
    expect(
      badge.bottom,
      lessThanOrEqualTo(cell.bottom + 0.1),
      reason: 'badge row must stay inside the cell',
    );
  });

  testWidgets('a plugin that widens artist cards still gets a cell that fits',
      (tester) async {
    // The request a theme plugin actually makes: wider tiles. Height is asked
    // for at 120, which cannot hold the resulting avatar, so the layout layer
    // has to raise the cell rather than clip it.
    await _pumpAtExtent(
      tester,
      scaling: 1,
      tokens: const ThemeTokens(
        artistCardWidth: 320,
        artistCardHeight: 120,
        gutter: 30,
      ),
      cellWidth: (context) => context.artistCardWidth,
      extent: (context) => playbuttonCardExtent(context, hasArtist: true),
    );
    expect(tester.takeException(), isNull);

    final cell = tester.getRect(find.byType(ArtistCard));
    final badge = tester.getRect(find.byType(SecondaryBadge));
    expect(badge.bottom, lessThanOrEqualTo(cell.bottom + 0.1));
    expect(cell.height, greaterThan(120));
  });

  testWidgets('album cards survive the extreme ends of the token ranges',
      (tester) async {
    for (final tokens in const [
      ThemeTokens(cardWidth: 80, cardHeight: 120, gutter: 0),
      ThemeTokens(cardWidth: 400, cardHeight: 600, gutter: 40),
    ]) {
      for (final radii in const [
        ThemeRadius(small: 0, medium: 0, large: 0, pill: 0),
        ThemeRadius(small: 48, medium: 48, large: 64, pill: 999),
      ]) {
        await _pumpAtExtent(
          tester,
          scaling: 1,
          tokens: tokens,
          radii: radii,
          cellWidth: (context) => context.gridCardWidth,
          extent: (context) => playbuttonCardExtent(context, hasArtist: false),
          card: const PlaybuttonCard(
            isPlaying: false,
            isLoading: false,
            title: 'A long enough title to wrap somewhere',
            description: 'and a description that goes under it',
            image: ColoredBox(color: Color(0xFF808080)),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'tokens $tokens with radii $radii',
        );
      }
    }
  });

  testWidgets('the guard is what saves it: the requested height really clips',
      (tester) async {
    // Negative control. artistCardHeight 120 is asked for and refused; handing
    // the card that literal shows the squeeze is real, so the passing cases
    // above are the guard working and not a layout that cannot overflow.
    await _pumpAtExtent(
      tester,
      scaling: 1,
      tokens: const ThemeTokens(artistCardWidth: 400, artistCardHeight: 120),
      cellWidth: (context) => context.artistCardWidth,
      extent: (context) => 120,
    );

    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('RenderFlex overflowed'),
      ),
    );
  });
}
