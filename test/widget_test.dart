// Spotube widget smoke test (Phase 1A harness repair).
//
// NOTE: the full `Spotube` widget is intentionally NOT pumped here.
// It requires async native initialization performed in `main()` before
// `runApp` (KVStoreService, EncryptedKvStoreService, AppDatabase,
// MediaKit.ensureInitialized, window_manager, etc.) plus live providers
// (theme definition, metadata plugins, local server, tray manager).
// Pumping it under `flutter_test` without those bindings hits
// missing-plugin channels and makes the test platform-dependent. A
// full-app test belongs in `integration_test/` with real bindings,
// not here.
//
// What this file does verify:
// 1. The `Spotube` widget still exists with its current architecture
//    (`HookConsumerWidget`, const-constructible).
// 2. The app's `rootNavigatorKey` is initialized.
// 3. The `flutter_test` + `hooks_riverpod` harness itself works.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/main.dart';

void main() {
  test('Spotube widget keeps its HookConsumerWidget architecture', () {
    const widget = Spotube();
    expect(widget, isA<HookConsumerWidget>());
    expect(widget.key, isNull);
  });

  test('root navigator key is initialized', () {
    expect(rootNavigatorKey, isA<GlobalKey<NavigatorState>>());
  });

  testWidgets('ProviderScope test harness pumps', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SizedBox())),
    );
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
