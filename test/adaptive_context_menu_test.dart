// The two triggers the context menus rely on: a secondary (right) click opens
// the dropdown at the pointer on every platform, and a long-press opens the
// bottom sheet only where the touch seam says it should. Both report through
// the same `onSelected` value contract as `AdaptivePopSheetList`.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/components/adaptive/adaptive_context_menu.dart';
import 'package:spotube/components/adaptive/adaptive_pop_sheet_list.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';

Widget _harness(Widget child) {
  return ShadcnApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Scaffold(
      child: AppLayout(
        tokens: const ThemeTokens(),
        radii: const ThemeRadius(),
        layout: const ThemeLayout(),
        child: Center(child: child),
      ),
    ),
  );
}

Widget _targetedMenu({
  required ValueChanged<String> onSelected,
  bool? longPressEnabled,
}) {
  return AdaptiveContextMenu<String>(
    longPressEnabled: longPressEnabled,
    items: (context) => [
      const AdaptiveMenuButton(
        value: 'copy',
        leading: Icon(IconData(0xe000, fontFamily: 'MaterialIcons')),
        child: Text('Copy row'),
      ),
      const AdaptiveMenuButton(
        value: 'delete',
        leading: Icon(IconData(0xe001, fontFamily: 'MaterialIcons')),
        child: Text('Delete row'),
      ),
    ],
    onSelected: onSelected,
    child: const SizedBox(
      key: Key('context-target'),
      width: 240,
      height: 120,
      child: ColoredBox(color: Color(0xFF888888)),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click opens the menu and reports the chosen value',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(
      _harness(_targetedMenu(onSelected: (value) => chosen = value)),
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, find.byKey(const Key('context-target')));

    expect(find.text('Copy row'), findsOneWidget);
    expect(find.text('Delete row'), findsOneWidget);

    await tester.tap(find.text('Copy row'));
    await tester.pumpAndSettle();

    expect(chosen, 'copy');
    expect(find.text('Copy row'), findsNothing);
  });

  testWidgets('long-press opens the sheet only when the touch seam is on',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(
      _harness(
        _targetedMenu(
          onSelected: (value) => chosen = value,
          longPressEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('context-target')));
    await tester.pumpAndSettle();

    expect(find.text('Copy row'), findsOneWidget);

    await tester.tap(find.text('Copy row'));
    await tester.pumpAndSettle();

    expect(chosen, 'copy');
  });

  testWidgets('long-press does nothing when the touch seam is off',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        _targetedMenu(
          onSelected: (_) {},
          longPressEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('context-target')));
    await tester.pumpAndSettle();

    expect(find.text('Copy row'), findsNothing);
  });

  testWidgets('a disabled menu ignores right-clicks', (tester) async {
    await tester.pumpWidget(
      _harness(
        AdaptiveContextMenu<String>(
          enabled: false,
          items: (context) => [
            const AdaptiveMenuButton(value: 'copy', child: Text('Copy row')),
          ],
          onSelected: (_) {},
          child: const SizedBox(
            key: Key('context-target'),
            width: 240,
            height: 120,
            child: ColoredBox(color: Color(0xFF888888)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, find.byKey(const Key('context-target')));

    expect(find.text('Copy row'), findsNothing);
  });
}
