// The shared keystroke debounce behind the library/blacklist filters: a
// burst of input values collapses into one settled value after the delay,
// and disposing mid-burst cancels the pending publish.

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/hooks/utils/use_debounce.dart';

void main() {
  Widget subject(String input, void Function(String settled) onSettled) {
    return HookBuilder(
      builder: (context) {
        final settled = useDebounce(
          input,
          const Duration(milliseconds: 200),
        );
        // Report through the callback (not a return) so the test observes
        // every rebuild, including the pre-settle ones.
        WidgetsBinding.instance.addPostFrameCallback((_) => onSettled(settled));
        return const SizedBox();
      },
    );
  }

  testWidgets('a burst settles on the last value only', (tester) async {
    final seen = <String>[];
    var input = 'a';

    await tester.pumpWidget(subject(input, seen.add));
    input = 'ab';
    await tester.pumpWidget(subject(input, seen.add));
    input = 'abc';
    await tester.pumpWidget(subject(input, seen.add));

    // Three synchronous rebuilds, no timer elapsed: the settled value has
    // not moved (every rebuild still reports 'a').
    expect(seen, everyElement('a'));

    await tester.pump(const Duration(milliseconds: 250));
    expect(seen.last, 'abc',
        reason: 'one timer survives the burst and publishes the last input');
  });

  testWidgets('an unchanged value publishes without waiting', (tester) async {
    final seen = <String>[];

    await tester.pumpWidget(subject('a', seen.add));
    expect(seen, ['a']);
  });

  testWidgets('disposing mid-burst cancels the publish', (tester) async {
    final seen = <String>[];

    await tester.pumpWidget(subject('a', seen.add));
    await tester.pumpWidget(subject('ab', seen.add));
    // Unmount before the 200ms timer fires.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));

    expect(seen, everyElement('a'),
        reason: 'the pending timer must not publish after dispose');
  });
}
