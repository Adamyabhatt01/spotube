import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('probe sidebar label width', (tester) async {
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: Center(
            child: SizedBox(
              width: 200,
              child: NavigationSidebar(
                children: [
                  NavigationButton(
                    label: const Text('Local library'),
                    overflow: NavigationOverflow.ellipsis,
                    onPressed: () {},
                    child: const Icon(RadixIcons.home),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final text = tester.getSize(find.text('Local library'));
    final intrinsic = tester.getSize(find.byType(IntrinsicWidth).first);
    final button = tester.getSize(find.byType(Button).first);
    // ignore: avoid_print
    print('text=$text intrinsic=$intrinsic button=$button');
  });
}
