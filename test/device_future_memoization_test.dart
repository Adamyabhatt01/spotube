// PR 1 / R-20: the fresh-Future-per-build storm, pinned at the hook-shape
// level.
//
// `audioPlayer.devices`/`selectedDevice` are `Future` *getters*: every build
// of ConnectPageLocalDevices handed `useFuture` a brand-new Future, which it
// treats as a changed future — re-subscribing and setState()ing when it
// completes, which builds again. Same mechanism and same fix as the
// music-cache-dir site (see local_library_rebuild_storm_test.dart, which
// could pump the real widgets; the Connect page reads the process-global
// `audioPlayer`, so this pins the hook shape instead: memoized == settles).

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeviceListBackend {
  int futuresCreated = 0;

  // A String, not a List: `Text('${snapshot.data}')` interpolates a List as
  // `[speakers]`, which made the finder miss it.
  Future<String> get devices {
    futuresCreated++;
    return Future.value('speakers');
  }
}

/// The fixed shape (what local_devices.dart now does).
class _MemoizedPage extends HookWidget {
  const _MemoizedPage(this.backend);

  final _DeviceListBackend backend;

  @override
  Widget build(BuildContext context) {
    final future = useFuture(useMemoized(() => backend.devices));
    return Text(future.data ?? 'pending', textDirection: TextDirection.ltr);
  }
}

/// The broken shape (what it used to be), as the in-test oracle.
class _ChurningPage extends HookWidget {
  const _ChurningPage(this.backend);

  final _DeviceListBackend backend;

  @override
  Widget build(BuildContext context) {
    final future = useFuture(backend.devices);
    return Text(future.data ?? 'pending', textDirection: TextDirection.ltr);
  }
}

Future<int> _pumpWhileScheduled(WidgetTester tester, int cap) async {
  var frames = 0;
  while (WidgetsBinding.instance.hasScheduledFrame && frames < cap) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

void main() {
  testWidgets('memoized async-getter future settles; unmemoized spins',
      (tester) async {
    final churned = _DeviceListBackend();
    await tester.pumpWidget(_MemoizedPage(churned));
    // Let the memoized future resolve (microtask) and its rebuild paint.
    await tester.pump(const Duration(milliseconds: 16));
    final frames = await _pumpWhileScheduled(tester, 120);
    expect(frames, lessThan(120), reason: 'must settle, not hit the cap');
    expect(
      churned.futuresCreated,
      1,
      reason: 'one Future per element, not one per build',
    );
    expect(find.text('speakers'), findsOneWidget);

    // Oracle: the old shape really does mint a new Future on every rebuild
    // it causes — two pump cycles must produce more than one.
    final broken = _DeviceListBackend();
    await tester.pumpWidget(_ChurningPage(broken));
    await tester.pump();
    await tester.pump();
    expect(
      broken.futuresCreated,
      greaterThan(1),
      reason: 'unmemoized: resolve -> setState -> rebuild -> new Future',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
