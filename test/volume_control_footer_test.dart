// The desktop bottom player is a `Scaffold` footer, and shadcn positions that
// footer by measuring it with `getMaxIntrinsicHeight` — see the header of
// `player_progress_intrinsic_test.dart` for why that query, not layout, is the
// thing that black-screens the window. The volume control lives in that footer,
// and its `revealOnHover` mode swaps the slider's `Expanded` (a bounded flex
// child) for an `AnimatedSize`/`ClipRect` holding a bare shadcn `Slider`, whose
// `LayoutBuilder` refuses both an intrinsic-width query and unbounded incoming
// constraints. These tests drive the real `VolumeSlider` inside the real footer
// across every `VolumeControlMode`, including the frame where the pointer is
// actually over it, so the hover-reveal path cannot regress to a blank window.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/modules/player/volume_slider.dart';

const _windowHeight = 900.0;

/// The volume control exactly as `BottomPlayerVolume` wraps it.
Widget volumeFooter({required bool revealOnHover}) {
  return Container(
    height: 40,
    constraints: const BoxConstraints(maxWidth: 250),
    padding: const EdgeInsets.only(right: 10),
    child: VolumeSlider(
      fullWidth: true,
      revealOnHover: revealOnHover,
      value: 0.5,
      onChanged: (_) {},
    ),
  );
}

Future<void> pumpInFooter(
  WidgetTester tester, {
  required bool revealOnHover,
}) async {
  tester.view.physicalSize = const Size(1280, _windowHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: ShadcnApp(
        home: Scaffold(
          floatingFooter: true,
          footers: [volumeFooter(revealOnHover: revealOnHover)],
          child: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('always mode measures its footer without throwing',
      (tester) async {
    await pumpInFooter(tester, revealOnHover: false);
    expect(tester.takeException(), isNull);
    // Full-width always mode keeps the slider visible via its Expanded branch.
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('hover mode is inert while collapsed', (tester) async {
    await pumpInFooter(tester, revealOnHover: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover mode does not break the frame the slider is revealed',
      (tester) async {
    await pumpInFooter(tester, revealOnHover: true);
    expect(tester.takeException(), isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    // Move onto the mute button so the MouseRegion reports a pointer inside the
    // volume control, which flips `hovering` true and mounts the real slider.
    await gesture.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    // A revealed slider still answers the intrinsic query the footer is
    // positioned from (a `LayoutBuilder` refusal throws here instead).
    final sliderBox = tester.renderObject<RenderBox>(find.byType(VolumeSlider));
    final intrinsic = sliderBox.getMaxIntrinsicHeight(double.infinity);
    expect(intrinsic, greaterThan(0));
  });
}
