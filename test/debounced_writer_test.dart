import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/debounced_writer.dart';

// All timing is virtual (fake_async): these tests never sleep and cannot
// flake under CI load, regardless of wall-clock scheduling.
void main() {
  test('rapid burst collapses to one call with latest action', () {
    fakeAsync((async) {
      final writer = DebouncedWriter(const Duration(milliseconds: 30));
      var calls = 0;
      var lastValue = 0;

      for (var i = 1; i <= 10; i++) {
        final value = i;
        writer(() async {
          calls++;
          lastValue = value;
        });
        async.elapse(const Duration(milliseconds: 5));
      }

      async.elapse(const Duration(milliseconds: 100));
      expect(calls, 1);
      expect(lastValue, 10);
      expect(writer.hasPending, isFalse);
    });
  });

  test('spaced calls each execute', () {
    fakeAsync((async) {
      final writer = DebouncedWriter(const Duration(milliseconds: 20));
      var calls = 0;

      for (var i = 0; i < 3; i++) {
        writer(() async => calls++);
        async.elapse(const Duration(milliseconds: 50));
      }

      expect(calls, 3);
    });
  });

  test('flush runs pending action immediately', () {
    fakeAsync((async) {
      final writer = DebouncedWriter(const Duration(seconds: 30));
      var calls = 0;

      writer(() async => calls++);
      expect(writer.hasPending, isTrue);

      var flushed = false;
      writer.flush().then((_) => flushed = true);
      async.flushMicrotasks();
      expect(flushed, isTrue);
      expect(calls, 1);
      expect(writer.hasPending, isFalse);
    });
  });

  test('cancel drops pending action', () {
    fakeAsync((async) {
      final writer = DebouncedWriter(const Duration(milliseconds: 20));
      var calls = 0;

      writer(() async => calls++);
      writer.cancel();

      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 0);
      expect(writer.hasPending, isFalse);
    });
  });

  test('failing action routes to onError, not the zone', () {
    fakeAsync((async) {
      Object? seen;
      final writer = DebouncedWriter(
        const Duration(milliseconds: 20),
        (e, _) => seen = e,
      );

      writer(() => Future<void>.error(StateError('db down')));
      async.elapse(const Duration(milliseconds: 60));

      expect(seen, isStateError);
      expect(writer.hasPending, isFalse);
    });
  });
}
