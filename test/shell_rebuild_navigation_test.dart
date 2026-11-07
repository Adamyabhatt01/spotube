// Why the playlist page used to snap back to Home.
//
// The shell changes the *depth* at which it mounts the router slot, legitimately
// and often: `ThemeBackgroundScope` returns `child` bare when no plugin
// background is painting and wraps it in `ComponentTheme` + `Stack` when one is,
// `ThemeSurfacesScope` gains and loses a `ComponentTheme`, the sidebar
// returns its `child` directly below the `sm` breakpoint and inside a `Row`
// above it, and `RootAppPage` wraps the whole thing in a `Padding`+`ClipRRect`
// for an inset-chrome theme.
//
// A widget that moves to a different depth is not updated, it is unmounted and
// rebuilt - unless it carries a [GlobalKey], which makes the same move a
// reparent. That distinction is everything one level down: auto_route 9.3 keeps
// a nested level's pages in `AutoRouterState._controller`
// (`router/widgets/auto_router.dart:103,114`), and `dispose()` drops it with
// the element (`:176`). A remounted `AutoRouter` therefore pushes its level's
// `initial: true` route (`routing_controller.dart:1831-1855`, whose
// `pendingChildren` escape hatch is cleared on first mount) instead of the page
// that was open. So one shell flip = Home, without an animation.
//
// The fix is the key on the slot in `lib/pages/root/root_app.dart`. These tests
// pin both halves: that a shell flip really is a remount, and that the key
// turns it into a move.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_background_image_provider.dart';
import 'package:spotube/modules/theme_background/theme_background_scope.dart';
import 'package:spotube/modules/theme_surfaces/theme_surfaces_scope.dart';
import 'package:spotube/pages/root/root_app.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// The provider behind [themeBackgroundImageProvider] in these tests, so the
/// background can be turned on and off exactly like a track starting to play.
final _imageSwitchProvider = StateProvider<ImageProvider?>(
  (ref) => const _PendingImageProvider(),
);

ThemeColors _colors(String fill) => ThemeColors(
      background: fill,
      foreground: fill,
      card: fill,
      cardForeground: fill,
      primary: fill,
      primaryForeground: fill,
      secondary: fill,
      secondaryForeground: fill,
      muted: fill,
      mutedForeground: fill,
      accent: fill,
      accentForeground: fill,
      destructive: fill,
      destructiveForeground: fill,
      border: fill,
      input: fill,
      ring: fill,
    );

ThemeDefinition _theme({
  ThemeBackgroundSource source = ThemeBackgroundSource.shell,
  String? tint,
}) {
  return ThemeDefinition(
    light: _colors('#ffffff'),
    dark: _colors('#000000'),
    background: ThemeBackground(source: source),
    surfaces: ThemeSurfaces(tint: tint),
  );
}

/// Resolves as an image provider but never decodes, so the layer paints nothing
/// and the test needs no network.
class _PendingImageProvider extends ImageProvider<_PendingImageProvider> {
  const _PendingImageProvider();

  @override
  Future<_PendingImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _PendingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }
}

int _mounts = 0;

/// Stands where the nested `AutoRouter` stands in the app: whatever is below the
/// shell has state worth keeping.
class _RouterSlot extends StatefulWidget {
  const _RouterSlot();

  @override
  State<_RouterSlot> createState() => _RouterSlotState();
}

class _RouterSlotState extends State<_RouterSlot> {
  @override
  void initState() {
    super.initState();
    _mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 100, height: 100);
}

class _Harness {
  _Harness(this._container, this._tester);

  final ProviderContainer _container;
  final WidgetTester _tester;

  void setBackground(ImageProvider? image) {
    _container.read(_imageSwitchProvider.notifier).state = image;
  }

  void setTheme(ThemeDefinition? theme) {
    _container.read(_themeSwitchProvider.notifier).state = theme;
  }

  Future<void> settle() => _tester.pumpAndSettle();
}

final _themeSwitchProvider = StateProvider<ThemeDefinition?>(
  (ref) => _theme(),
);

Future<_Harness> _pump(
  WidgetTester tester,
  Widget Function(Widget child) shell,
) async {
  final container = ProviderContainer(
    overrides: [
      themeDefinitionProvider.overrideWith(
        (ref) => Future.value(ref.watch(_themeSwitchProvider)),
      ),
      themeBackgroundImageProvider.overrideWith(
        // Family form since the provider is keyed by quantized decode side;
        // the fake image is size-independent, so every key shares it.
        (ref, arg) => ref.watch(_imageSwitchProvider),
      ),
      themeBackdropActiveProvider.overrideWith(
        // The scope's gate, mirrored with the leaf swapped for the fake image:
        // the theme still resolving a frame late is the flip under test.
        (ref) {
          final source = ref.watch(
            themeDefinitionProvider.select(
              (s) => s.asData?.value?.background.source,
            ),
          );
          return source == ThemeBackgroundSource.shell &&
              ref.watch(_imageSwitchProvider) != null;
        },
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Theme(
        data: const ThemeData.dark(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: shell(const _RouterSlot())),
        ),
      ),
    ),
  );

  final harness = _Harness(container, tester);
  await harness.settle();
  return harness;
}

void main() {
  setUp(() => _mounts = 0);

  group('a shell that changes shape', () {
    testWidgets('unmounts an unkeyed router slot', (tester) async {
      final harness = await _pump(
        tester,
        (slot) => ThemeBackgroundScope(child: slot),
      );
      // Two already, before anything was touched: the theme resolves a frame
      // after first paint, so the scope goes from bare `child` to wrapped and
      // the slot is rebuilt on the way to looking exactly the same.
      expect(_mounts, 2, reason: 'the theme arriving late is itself a flip');

      // The flip a trackless-then-playing album-art theme causes.
      harness.setBackground(null);
      await harness.settle();

      expect(
        _mounts,
        3,
        reason: 'without a key every flip is a rebuild, state and all',
      );
    });

    testWidgets('only moves the keyed router slot the app uses',
        (tester) async {
      final harness = await _pump(
        tester,
        (slot) => ThemeBackgroundScope(
          child: MediaQuery(
            // The same key object the app's shell puts on its router slot, so
            // dropping it there breaks this test.
            key: appRouterSlotKey,
            data: MediaQueryData.fromView(tester.view),
            child: slot,
          ),
        ),
      );
      expect(_mounts, 1);

      harness.setBackground(null);
      await harness.settle();
      expect(_mounts, 1, reason: 'the slot survived the shape change');

      harness.setBackground(const _PendingImageProvider());
      await harness.settle();
      expect(_mounts, 1, reason: 'and it survives the way back');
    });

    testWidgets('so does the surfaces scope', (tester) async {
      final harness = await _pump(
        tester,
        (slot) => ThemeSurfacesScope(
          child: MediaQuery(
            key: appRouterSlotKey,
            data: MediaQueryData.fromView(tester.view),
            child: slot,
          ),
        ),
      );
      harness.setTheme(_theme(tint: '#80112233'));
      await harness.settle();
      expect(_mounts, 1, reason: 'gaining a tint must not rebuild the slot');

      harness.setTheme(_theme());
      await harness.settle();
      expect(_mounts, 1, reason: 'losing the tint must not rebuild it either');
    });
  });

  group('theme resolution', () {
    test('a recompute keeps the last theme reachable through asData', () async {
      // Pinned because it is the obvious wrong diagnosis: a reload is *not* a
      // hole in the shell, riverpod serves the previous value while loading.
      final container = ProviderContainer(
        overrides: [
          themeDefinitionProvider.overrideWith((ref) => Future.value(_theme())),
        ],
      );
      addTearDown(container.dispose);

      await container.read(themeDefinitionProvider.future);
      container.invalidate(themeDefinitionProvider);
      final reloading = container.read(themeDefinitionProvider);

      expect(reloading.isLoading, isTrue);
      expect(reloading.asData?.value, isNotNull);
    });
  });
}
