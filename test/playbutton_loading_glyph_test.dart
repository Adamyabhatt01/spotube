// Collection cards share one loading flag for "prepare playback" and "append
// to queue". That conflation turned the play button into a spinner while the
// card was only fetching a queue tail, even when the collection was already
// audible.
//
// The card receives play preparation as `isLoading` and queue work as
// `isQueueLoading`. The play glyph must also be defensive: a preparation flag
// can outlive audible playback when a downloaded/local copy starts before the
// source manifest settles.

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

Widget _card({
  bool isPlaying = false,
  bool isActuallyPlaying = false,
  bool isLoading = false,
  bool isQueueLoading = false,
}) {
  return PlaybuttonCard(
    title: 'An album',
    description: 'with a subtitle',
    isPlaying: isPlaying,
    isActuallyPlaying: isActuallyPlaying,
    isLoading: isLoading,
    isQueueLoading: isQueueLoading,
    image: const SizedBox(height: 120, width: 120),
    onTap: () {},
    onPlaybuttonPressed: () {},
    onAddToQueuePressed: () {},
  );
}

Widget _tile({
  bool isPlaying = false,
  bool isActuallyPlaying = false,
  bool isLoading = false,
}) {
  return SizedBox(
    width: 500,
    child: PlaybuttonTile(
      title: 'A playlist',
      description: 'with a subtitle',
      isPlaying: isPlaying,
      isActuallyPlaying: isActuallyPlaying,
      isLoading: isLoading,
      image: const SizedBox(height: 120, width: 120),
      onTap: () {},
      onPlaybuttonPressed: () {},
      onAddToQueuePressed: () {},
    ),
  );
}

Finder _buttonFor(IconData icon) => find
    .ancestor(
      of: find.byIcon(icon),
      matching: find.byType(IconButton),
    )
    .first;

bool _isEnabled(IconButton button) =>
    button.enabled ?? (button.onPressed != null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an audible card ignores a late preparation flag',
      (tester) async {
    await tester.pumpWidget(
      _harness(_card(
        isPlaying: true,
        isActuallyPlaying: true,
        isLoading: true,
      )),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
    expect(
      _isEnabled(tester.widget<IconButton>(_buttonFor(SpotubeIcons.pause))),
      isTrue,
      reason: 'audible playback must remain pausable',
    );
  });

  testWidgets('a paused card shows the spinner while preparing',
      (tester) async {
    await tester.pumpWidget(
      _harness(_card(isLoading: true)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(SpotubeIcons.play), findsNothing);
  });

  testWidgets('queue loading never turns the play button into a spinner',
      (tester) async {
    await tester.pumpWidget(
      _harness(_card(isQueueLoading: true)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(SpotubeIcons.play), findsOneWidget);
    expect(
      _isEnabled(tester.widget<IconButton>(_buttonFor(SpotubeIcons.play))),
      isTrue,
      reason: 'the play control is independent of the queue job',
    );
    expect(
      _isEnabled(tester.widget<IconButton>(_buttonFor(SpotubeIcons.queueAdd))),
      isFalse,
      reason: 'only the queue control should wait for the queue job',
    );
  });

  testWidgets('an audible tile ignores a late preparation flag',
      (tester) async {
    await tester.pumpWidget(
      _harness(_tile(
        isPlaying: true,
        isActuallyPlaying: true,
        isLoading: true,
      )),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(SpotubeIcons.pause), findsOneWidget);
    expect(
      _isEnabled(tester.widget<IconButton>(_buttonFor(SpotubeIcons.pause))),
      isTrue,
      reason: 'an audible tile must remain pausable',
    );
  });
}
