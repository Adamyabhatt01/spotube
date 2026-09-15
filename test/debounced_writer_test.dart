import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/debounced_writer.dart';

void main() {
  test('rapid burst collapses to one call with latest action', () async {
    final writer = DebouncedWriter(const Duration(milliseconds: 30));
    var calls = 0;
    var lastValue = 0;

    for (var i = 1; i <= 10; i++) {
      final value = i;
      writer(() async {
        calls++;
        lastValue = value;
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(calls, 1);
    expect(lastValue, 10);
    expect(writer.hasPending, isFalse);
  });

  test('spaced calls each execute', () async {
    final writer = DebouncedWriter(const Duration(milliseconds: 20));
    var calls = 0;

    for (var i = 0; i < 3; i++) {
      writer(() async => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(calls, 3);
  });

  test('flush runs pending action immediately', () async {
    final writer = DebouncedWriter(const Duration(seconds: 30));
    var calls = 0;

    writer(() async => calls++);
    expect(writer.hasPending, isTrue);

    await writer.flush();
    expect(calls, 1);
    expect(writer.hasPending, isFalse);
  });

  test('cancel drops pending action', () async {
    final writer = DebouncedWriter(const Duration(milliseconds: 20));
    var calls = 0;

    writer(() async => calls++);
    writer.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 0);
    expect(writer.hasPending, isFalse);
  });

  test('failing action routes to onError, not the zone', () async {
    Object? seen;
    final writer = DebouncedWriter(
      const Duration(milliseconds: 20),
      (e, _) => seen = e,
    );

    writer(() => Future<void>.error(StateError('db down')));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(seen, isStateError);
    expect(writer.hasPending, isFalse);
  });
}
