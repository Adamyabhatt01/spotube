// The play/add overlays on a grid card fade in when the pointer hovers it. On
// touch there is no hover state to follow, so the animated target is a constant
// and each card still mounts two AnimatedScale + AnimatedOpacity pairs - four
// controllers and four tickers - that can never animate during the scroll that
// created the card. The mobile path therefore renders the button directly and
// keeps the hidden one at zero opacity so the slot (and the play button's
// position while loading) is unchanged.
//
// kIsMobile comes from the host process's Platform, so a test on Linux can only
// ever drive the desktop branch; the mobile shape is asserted through
// `hoverReveal`'s `animated` flag, which is where the branch actually lives.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/playbutton_view/playbutton_card.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';

const _hidden = 0.7;

Widget _harness(Widget child, {Set<WidgetState> states = const {}}) {
  return ShadcnApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: AppLayout(
      tokens: const ThemeTokens(),
      radii: const ThemeRadius(),
      layout: const ThemeLayout(),
      child: WidgetStatesProvider(
        states: states,
        child: Center(child: child),
      ),
    ),
  );
}

Widget _card({bool isPlaying = false, bool isLoading = false}) {
  return PlaybuttonCard(
    title: 'An album',
    description: 'with a subtitle',
    isPlaying: isPlaying,
    isLoading: isLoading,
    image: const SizedBox(height: 120, width: 120),
    onTap: () {},
    onPlaybuttonPressed: () {},
    onAddToQueuePressed: () {},
  );
}

/// The card's own wrapper is the outermost of the animations around a button;
/// [IconButton] contributes its own, nearer, pair.
AnimatedScale _scaleOn(WidgetTester tester, IconData icon) => tester.widget(
      find
          .ancestor(
            of: find.byIcon(icon),
            matching: find.byType(AnimatedScale),
          )
          .first,
    );

AnimatedOpacity _fadeOn(WidgetTester tester, Finder target) => tester.widget(
      find.ancestor(of: target, matching: find.byType(AnimatedOpacity)).first,
    );

void main() {
  const queue = SpotubeIcons.queueAdd;
  const play = SpotubeIcons.play;

  group('the pointer branch', () {
    testWidgets('an idle card keeps both overlays faded out', (tester) async {
      await tester.pumpWidget(_harness(_card()));
      await tester.pumpAndSettle();

      expect(_scaleOn(tester, queue).scale, _hidden);
      expect(_fadeOn(tester, find.byIcon(queue)).opacity, 0);
      expect(_scaleOn(tester, play).scale, _hidden);
      expect(_fadeOn(tester, find.byIcon(play)).opacity, 0);
    });

    testWidgets('hover reveals them, as before', (tester) async {
      await tester.pumpWidget(
        _harness(_card(), states: {WidgetState.hovered}),
      );
      await tester.pumpAndSettle();

      expect(_scaleOn(tester, queue).scale, 1);
      expect(_fadeOn(tester, find.byIcon(queue)).opacity, 1);
      expect(_scaleOn(tester, play).scale, 1);
      expect(_fadeOn(tester, find.byIcon(play)).opacity, 1);
    });

    testWidgets('a loading card hides the add button and keeps the play slot',
        (tester) async {
      await tester.pumpWidget(_harness(_card(isLoading: true)));
      // pumpAndSettle would never return: the spinner on a loading card runs
      // forever. The targets are plain widget properties, so one frame is all
      // the assertions below need.
      await tester.pump();

      // The two conditions were folded into `hovered` + the same terms; these
      // are the values they produced before the fold, on an idle pointer.
      expect(_fadeOn(tester, find.byIcon(queue)).opacity, 0);
      expect(
        _fadeOn(tester, find.byType(CircularProgressIndicator)).opacity,
        1,
      );
    });
  });

  group('the touch branch', () {
    testWidgets('mounts no implicit animations at all', (tester) async {
      await tester.pumpWidget(
        _harness(
          Column(
            children: [
              hoverReveal(
                shown: true,
                duration: const Duration(milliseconds: 300),
                animated: false,
                child: const SizedBox(key: Key('shown'), height: 34, width: 50),
              ),
              const Gap(5),
              hoverReveal(
                shown: false,
                duration: const Duration(milliseconds: 300),
                animated: false,
                child: const SizedBox(key: Key('gone'), height: 34, width: 50),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedScale), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);

      // The same two buttons, unanimated, keep the geometry the animation gave:
      // the hidden one still occupies its row, so the button beside it does not
      // jump while the card loads.
      expect(find.byKey(const Key('gone')), findsOneWidget);
      expect(
        tester.widget<Opacity>(
          find.ancestor(
            of: find.byKey(const Key('gone')),
            matching: find.byType(Opacity),
          ),
        ).opacity,
        0,
      );
      expect(tester.getSize(find.byKey(const Key('shown'))), const Size(50, 34));
      expect(tester.getSize(find.byKey(const Key('gone'))), const Size(50, 34));
    });

    testWidgets('the animated shape is the one the pointer branch builds',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          Row(
            children: [
              hoverReveal(
                shown: false,
                duration: const Duration(milliseconds: 150),
                animated: true,
                child: const SizedBox(height: 34, width: 50),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Negative control: `animated: false` above removes wrappers that exist,
      // not wrappers that were never in the helper.
      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsOneWidget);
    });
  });
}
