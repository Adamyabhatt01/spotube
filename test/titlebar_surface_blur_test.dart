// A zero-sigma title bar must not create a backdrop filter layer.
//
// shadcn's AppBar builds `ClipRect` + `BackdropFilter` unconditionally, so the
// transparent-window path (which forces sigma 0) paid a backdrop pass per
// frame for a filter that blurs nothing. `TitleBarSurface` mirrors that layout
// and only creates the filter when there is a real blur.

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/titlebar/titlebar_surface.dart';

Widget _app(Widget child, {ThemeData? theme}) => ShadcnApp(
      theme: theme ?? const ThemeData(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: child,
      ),
    );

Widget _bar({double? blur}) => TitleBarSurface(
      title: const Text('Title'),
      surfaceBlur: blur,
    );

void main() {
  testWidgets('explicit zero sigma creates no backdrop filter', (tester) async {
    await tester.pumpWidget(_app(_bar(blur: 0)));

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('a theme with zero surface blur creates none either',
      (tester) async {
    await tester.pumpWidget(
      _app(_bar(), theme: const ThemeData(surfaceBlur: 0)),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a theme with no blur set creates none', (tester) async {
    await tester.pumpWidget(_app(_bar()));

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a real blur still gets its backdrop filter', (tester) async {
    await tester.pumpWidget(_app(_bar(blur: 10)));

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('a widget blur overrides a zero theme blur', (tester) async {
    await tester.pumpWidget(
      _app(_bar(blur: 4), theme: const ThemeData(surfaceBlur: 0)),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('leading, title and trailing keep the AppBar layout',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const TitleBarSurface(
          leading: [Text('L')],
          title: Text('T'),
          trailing: [Text('R')],
        ),
      ),
    );

    expect(find.text('L'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
  });
}
