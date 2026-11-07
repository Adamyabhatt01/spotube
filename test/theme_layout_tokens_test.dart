// A theme plugin now owns the geometry of the media grid — card widths, cell
// heights, gutters, corner radii — and the choice of which shell the app
// draws: an inset content panel, an icon-only nav rail, a seek bar that spans
// the player. Three things have to hold for that to be safe:
//   - numbers leaving the plugin boundary are inside render ranges, whatever
//     the plugin sent;
//   - a cell is never shorter than what it has to hold, so the worst a hostile
//     theme can do is leave slack, never clip;
//   - a switch a plugin gets wrong degrades to the shape the app shipped with,
//     per field, rather than losing the whole theme.
// The default values are asserted explicitly: they are the literals this layer
// replaced, so a change here is a visible change to every existing theme.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/services/metadata/theme_sanitizer.dart';

class _Metrics {
  const _Metrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.artistCardWidth,
    required this.artistCardHeight,
    required this.artistAvatarSize,
    required this.gutter,
    required this.cardRadius,
    required this.surfaceRadius,
    required this.insetChrome,
    required this.iconOnlyNav,
    required this.progressBelow,
    required this.chromeInsetGap,
    required this.chromeInk,
    required this.background,
  });

  final double cardWidth;
  final double cardHeight;
  final double artistCardWidth;
  final double artistCardHeight;
  final double artistAvatarSize;
  final double gutter;
  final double cardRadius;
  final double surfaceRadius;
  final bool insetChrome;
  final bool iconOnlyNav;
  final bool progressBelow;
  final double chromeInsetGap;
  final Color chromeInk;
  final Color background;
}

Future<_Metrics> _measure(
  WidgetTester tester, {
  ThemeDefinition? theme,
  double scaling = 1,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late final _Metrics metrics;
  await tester.pumpWidget(
    ShadcnApp(
      scaling: AdaptiveScaling(scaling),
      localizationsDelegates: const [AppLocalizations.delegate],
      home: AppLayout(
        tokens: theme?.tokens ?? const ThemeTokens(),
        radii: theme?.radius ?? const ThemeRadius(),
        layout: theme?.layout ?? const ThemeLayout(),
        child: Builder(
          builder: (context) {
            metrics = _Metrics(
              cardWidth: context.gridCardWidth,
              cardHeight: context.gridCardHeight,
              artistCardWidth: context.artistCardWidth,
              artistCardHeight: playbuttonCardExtent(
                context,
                hasArtist: true,
              ),
              artistAvatarSize: context.artistAvatarSize,
              gutter: context.layoutGutter,
              cardRadius: context.cardCornerRadius,
              surfaceRadius: context.surfaceCornerRadius,
              insetChrome: context.insetChrome,
              iconOnlyNav: context.iconOnlyNav,
              progressBelow: context.progressBelow,
              chromeInsetGap: context.chromeInsetGap,
              chromeInk: context.chromeInkColor,
              background: context.theme.colorScheme.background,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return metrics;
}

ThemeDefinition _theme({
  ThemeTokens tokens = const ThemeTokens(),
  ThemeRadius radius = const ThemeRadius(),
  ThemeLayout layout = const ThemeLayout(),
  double density = 1.0,
}) {
  return ThemeDefinition(
    light: _colors('#ffffff'),
    dark: _colors('#000000'),
    tokens: tokens,
    radius: radius,
    layout: layout,
    density: density,
  );
}

ThemeColors _colors(String background) {
  return ThemeColors(
    background: background,
    foreground: background,
    card: background,
    cardForeground: background,
    primary: background,
    primaryForeground: background,
    secondary: background,
    secondaryForeground: background,
    muted: background,
    mutedForeground: background,
    accent: background,
    accentForeground: background,
    destructive: background,
    destructiveForeground: background,
    border: background,
    input: background,
    ring: background,
  );
}

/// A full definition as it would arrive off the wire, mutable so a test can
/// remove or replace one key.
Map<String, dynamic> _wire() => _theme().toJson();

void main() {
  group('AppLayout tokens', () {
    testWidgets('defaults are the numbers this layer replaced', (tester) async {
      final metrics = await _measure(tester);

      expect(metrics.cardWidth, 150);
      expect(metrics.cardHeight, 225);
      expect(metrics.artistCardWidth, 180);
      expect(metrics.artistCardHeight, 250);
      expect(metrics.gutter, 12);
      // ThemeRadius.small (6) is what covers were drawn with via shadcn's
      // borderRadiusMd at its default 0.5 multiplier.
      expect(metrics.cardRadius, 6);
    });

    testWidgets('everything tracks the active scaling', (tester) async {
      final metrics = await _measure(tester, scaling: 2);

      expect(metrics.cardWidth, 300);
      expect(metrics.cardHeight, 450);
      expect(metrics.artistCardHeight, 500);
      expect(metrics.gutter, 24);
    });

    testWidgets('a plugin resizing artist cards reaches the grid',
        (tester) async {
      final metrics = await _measure(
        tester,
        theme: _theme(
          tokens: const ThemeTokens(
            artistCardWidth: 260,
            artistCardHeight: 320,
            gutter: 20,
          ),
        ),
      );

      expect(metrics.artistCardWidth, 260);
      expect(metrics.artistAvatarSize, 260 * 0.72);
      expect(metrics.artistCardHeight, 320);
      expect(metrics.gutter, 20);
      // Unspecified siblings keep their own defaults.
      expect(metrics.cardWidth, 150);
    });

    testWidgets('a cell never ends up shorter than its own content',
        (tester) async {
      // 120px of height cannot hold a 400px cover, and an artist cell has to
      // fit the avatar the plugin just widened.
      final metrics = await _measure(
        tester,
        theme: _theme(
          tokens: const ThemeTokens(
            cardWidth: 400,
            cardHeight: 120,
            artistCardWidth: 400,
            artistCardHeight: 120,
          ),
        ),
      );

      expect(metrics.cardHeight, greaterThanOrEqualTo(metrics.cardWidth));
      expect(
        metrics.artistCardHeight,
        greaterThanOrEqualTo(metrics.artistAvatarSize),
      );
    });

    testWidgets('radii reach the surfaces Spotube draws itself',
        (tester) async {
      final metrics = await _measure(
        tester,
        theme: _theme(radius: const ThemeRadius(small: 0)),
      );
      expect(metrics.cardRadius, 0);
    });
  });

  group('ThemeLayout switches', () {
    testWidgets('the shell the app had before this existed is the default',
        (tester) async {
      final metrics = await _measure(tester);

      expect(metrics.insetChrome, isFalse);
      expect(metrics.iconOnlyNav, isFalse);
      expect(metrics.progressBelow, isFalse);
      // ThemeRadius.large, which previously had no consumer at all.
      expect(metrics.surfaceRadius, 16);
    });

    testWidgets('a plugin picks the shell, it cannot invent one',
        (tester) async {
      final metrics = await _measure(
        tester,
        theme: _theme(
          layout: const ThemeLayout(
            chrome: ThemeChrome.inset,
            nav: ThemeNav.rail,
            progress: ThemeProgress.below,
          ),
        ),
      );

      expect(metrics.insetChrome, isTrue);
      expect(metrics.iconOnlyNav, isTrue);
      expect(metrics.progressBelow, isTrue);
      expect(metrics.chromeInsetGap, 8);
    });

    testWidgets('the new sizes ride scaling like the old ones', (tester) async {
      final metrics = await _measure(
        tester,
        scaling: 2,
        theme: _theme(
          layout: const ThemeLayout(chrome: ThemeChrome.inset),
        ),
      );

      expect(metrics.chromeInsetGap, 16);
      expect(metrics.surfaceRadius, 32);
    });

    testWidgets('the backdrop is a shade of the theme background only',
        (tester) async {
      // No contract field for it, so a theme cannot end up framing its panel
      // in a colour its palette never accounted for.
      final metrics = await _measure(
        tester,
        theme: _theme(
          layout: const ThemeLayout(chrome: ThemeChrome.inset),
        ),
      );

      expect(metrics.chromeInk, isNot(metrics.background));
      expect(
        metrics.chromeInk.computeLuminance(),
        lessThan(metrics.background.computeLuminance()),
      );
    });

    test('an absent or unknown value falls back per field', () {
      expect(
        ThemeDefinition.fromJson(_wire()..remove('layout')).layout,
        const ThemeLayout(),
      );

      final typo = ThemeDefinition.fromJson(
        _wire()
          ..['layout'] = {
            'chrome': 'rounded',
            'nav': 'rail',
            'progress': 'below',
          },
      );

      expect(typo.layout.chrome, ThemeChrome.flat);
      expect(typo.layout.nav, ThemeNav.rail);
      expect(typo.layout.progress, ThemeProgress.below);
    });

    test('round-trips over the wire names, not the Dart identifiers', () {
      const layout = ThemeLayout(
        chrome: ThemeChrome.inset,
        nav: ThemeNav.rail,
        progress: ThemeProgress.below,
      );
      final definition = _theme(layout: layout);

      expect(definition.toJson()['layout'], {
        'chrome': 'inset',
        'nav': 'rail',
        'progress': 'below',
        'sidebar': 'host',
        'sidebarWidth': null,
        'aside': 'none',
        'asideWidth': null,
        'shell': null,
        'pinTargets': <Map<String, dynamic>>[],
        'player': {
          'dock': 'full',
          'showTrackDetails': true,
          'showActions': true,
          'showVolume': true,
          'showLyrics': true,
          'showProgress': true,
        },
        'enforce': <String>[],
        'navItems': <String>[],
        'navbarItems': <String>[],
        'libraryItems': <String>[],
        'home': <String, dynamic>{},
        'settings': <String, dynamic>{},
        'titlebar': <String, dynamic>{},
        'splash': <String, dynamic>{},
        'responsive': <String, dynamic>{},
      });
      expect(ThemeDefinition.fromJson(definition.toJson()).layout, layout);

      // The Dart name would be `inlinePlacement`; the protocol says `inline`.
      expect(
        ThemeLayout.fromJson(const {'progress': 'inline'}).progress,
        ThemeProgress.inlinePlacement,
      );
    });
  });

  group('sanitizeThemeDefinition geometry', () {
    test('clamps card sizes, gutters and radii into render ranges', () {
      final sanitized = sanitizeThemeDefinition(
        _theme(
          tokens: const ThemeTokens(
            cardWidth: 5000,
            cardHeight: -10,
            artistCardWidth: 0,
            artistCardHeight: 9000,
            gutter: 500,
          ),
          radius: const ThemeRadius(medium: 1e9, large: -5),
        ),
      );

      expect(sanitized.tokens.cardWidth, 400);
      expect(sanitized.tokens.cardHeight, 120);
      expect(sanitized.tokens.artistCardWidth, 80);
      expect(sanitized.tokens.artistCardHeight, 640);
      expect(sanitized.tokens.gutter, 40);
      // Radius.medium drives shadcn's whole component set, so it is bounded.
      expect(sanitized.radius.medium, 48);
      expect(sanitized.radius.large, 0);
    });

    test('density stays near neutral instead of rescaling the whole UI', () {
      expect(sanitizeThemeDefinition(_theme(density: 500)).density, 1.5);
      expect(sanitizeThemeDefinition(_theme(density: 0)).density, 1.0);
      expect(sanitizeThemeDefinition(_theme(density: -3)).density, 1.0);
      expect(
        sanitizeThemeDefinition(_theme(density: double.nan)).density,
        1.0,
      );
      expect(sanitizeThemeDefinition(_theme(density: 1.25)).density, 1.25);
    });

    test('non-finite sizes fall back instead of poisoning constraints', () {
      final sanitized = sanitizeThemeDefinition(
        _theme(
          tokens: const ThemeTokens(
            cardWidth: double.infinity,
            gutter: double.nan,
          ),
        ),
      ).tokens;

      expect(sanitized.cardWidth, 150);
      expect(sanitized.gutter, 12);
    });

    test('a font family survives only if it can name one', () {
      expect(
        sanitizeThemeDefinition(
          _theme(tokens: const ThemeTokens(fontFamily: '  Noto Sans  ')),
        ).tokens.fontFamily,
        'Noto Sans',
      );
      for (final hostile in [
        '',
        '   ',
        'A' * 65,
        '<!-- -->',
        'GeistSans; package=shadcn_flutter',
        'x\ny',
      ]) {
        expect(
          sanitizeThemeDefinition(
            _theme(tokens: ThemeTokens(fontFamily: hostile)),
          ).tokens.fontFamily,
          isNull,
          reason: 'rejected "$hostile"',
        );
      }
    });
  });
}
