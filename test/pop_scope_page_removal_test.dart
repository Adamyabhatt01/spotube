// What a `PopScope` is told when its page goes away.
//
// `lib/pages/library/library.dart` guards the library page with
// `PopScope(canPop: false, onPopInvokedWithResult: ...)`: a blocked system back
// should drop the user on Home instead of quitting. The handler used to ignore
// its `didPop` argument, which is the whole story behind "clicking a playlist
// sometimes throws me to Home/Browse" - auto_route collapses its stack by
// *deleting pages* (`routing_controller.dart:1237-1263`), and a deleted page
// reports a pop that *succeeded*. The handler then pushed Home over whatever
// the click had just opened, with no back gesture involved.
//
// These tests pin the two `didPop` values, because both are load-bearing: the
// guard is only correct if a real deletion says `true` and a blocked pop says
// `false`.
//
// The harness is a bare pages-based `Navigator` - the same shape auto_route
// drives - with a `PopScope` page whose callback records what it was told.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('deleting a page reports a pop that succeeded', (tester) async {
    final calls = <bool>[];

    Future<void> pumpPages(int count) => tester.pumpWidget(
          MaterialApp(
            home: Navigator(
              pages: [
                for (var i = 0; i < count; i++)
                  MaterialPage(child: _GuardedPage(calls: calls)),
              ],
              // A pages-based Navigator asks its owner to drop the page; the
              // list here is throwaway, the pop reporting is what's measured.
              onDidRemovePage: (page) {},
            ),
          ),
        );

    await pumpPages(2);
    expect(calls, isEmpty, reason: 'a stack that only grew pops nothing');

    await pumpPages(1);
    expect(
      calls,
      [true],
      reason:
          'the removed page is told its pop succeeded, though nobody popped',
    );
  });

  testWidgets('a pop the PopScope blocks reports didPop false', (tester) async {
    final calls = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          pages: [MaterialPage(child: _GuardedPage(calls: calls))],
          onDidRemovePage: (page) {},
        ),
      ),
    );

    // `Navigator.maybePop` is what a system back becomes; `canPop: false` on the
    // page's PopScope is what holds it.
    final handled = await tester
        .state<NavigatorState>(find.byType(Navigator).last)
        .maybePop();

    // "Handled" is not "popped": the route swallowed the back and the page is
    // still up, which is the half of the pair the handler answers with Home.
    expect(handled, isTrue);
    expect(find.byType(_GuardedPage), findsOneWidget);
    expect(
      calls,
      [false],
      reason: 'the page gets to decide where to go instead',
    );
  });
}

class _GuardedPage extends StatelessWidget {
  const _GuardedPage({required this.calls});

  final List<bool> calls;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => calls.add(didPop),
      child: const SizedBox(width: 100, height: 100),
    );
  }
}
