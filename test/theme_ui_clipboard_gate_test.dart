// The clipboard verb is the one action that leaves the app's own data: a theme
// that can copy can put anything the user later pastes somewhere else. The
// build validator requires `clipboard.write` for it, and this pins that the
// host refuses it too, because an installed `.smplug` was not necessarily built
// by that validator.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action.dart';
import 'package:spotube/modules/theme_ui/theme_ui_action_dispatcher.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

ThemeUiDocument _document(List<String> capabilities) => ThemeUiDocument(
      specVersion: 4,
      capabilities: capabilities,
    );

Future<({ProviderContainer container, BuildContext context})> _harness(
  WidgetTester tester,
  ThemeUiDocument document,
) async {
  final container = ProviderContainer(
    overrides: [
      themeUiProvider.overrideWith((ref) async => document),
    ],
  );
  addTearDown(container.dispose);

  late BuildContext context;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return (container: container, context: context);
}

void main() {
  late List<MethodCall> clipboardCalls;

  setUp(() {
    clipboardCalls = [];
  });

  Future<void> dispatch(
    WidgetTester tester,
    ThemeUiDocument document,
    Map<String, dynamic> args,
  ) async {
    final h = await _harness(tester, document);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    await dispatchThemeUiAction(
      h.context,
      h.container,
      ThemeUiAction('copy', args),
    );
  }

  testWidgets('copy is refused without clipboard.write', (tester) async {
    await dispatch(
      tester,
      _document(['library.write', 'settings.write']),
      {'text': 'https://open.spotify.com/track/x'},
    );

    expect(clipboardCalls, isEmpty);
  });

  testWidgets('copy writes the text once the capability is declared',
      (tester) async {
    await dispatch(
      tester,
      _document(['clipboard.write']),
      {'text': 'https://open.spotify.com/track/x'},
    );

    expect(clipboardCalls, hasLength(1));
    expect(
      (clipboardCalls.single.arguments as Map)['text'],
      'https://open.spotify.com/track/x',
    );
  });

  testWidgets('an empty or absent text writes nothing', (tester) async {
    await dispatch(tester, _document(['clipboard.write']), {'text': ''});
    await dispatch(tester, _document(['clipboard.write']), {});

    expect(clipboardCalls, isEmpty);
  });
}
