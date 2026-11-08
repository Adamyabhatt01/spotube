// The queue-end radio fetch fires once per tail: concurrent and repeat
// claims for the same track lose, empty/failed claims stay retryable, and a
// served tail is never refetched (a refetch could only re-append duplicates).

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/hooks/configurators/use_endless_playback.dart';

void main() {
  late EndlessRadioGate gate;

  setUp(() => gate = EndlessRadioGate());

  test('first claim wins, concurrent claim loses', () {
    expect(gate.claim('tail-1'), isTrue);
    expect(gate.claim('tail-1'), isFalse,
        reason: 'mount-at-end plus the index stream must not double-fetch');
  });

  test('a released claim is retryable', () {
    expect(gate.claim('tail-1'), isTrue);
    gate.release('tail-1');
    expect(gate.claim('tail-1'), isTrue,
        reason:
            'empty or failed fetches must not suppress the next tail event');
  });

  test('a served tail is never refetched', () {
    expect(gate.claim('tail-1'), isTrue);
    gate.serve('tail-1');
    expect(gate.claim('tail-1'), isFalse,
        reason: 're-appending duplicates that removeWhere drops is pure waste');
  });

  test('release after serve keeps the tail served', () {
    expect(gate.claim('tail-1'), isTrue);
    gate.serve('tail-1');
    gate.release('tail-1');
    expect(gate.claim('tail-1'), isFalse);
  });

  test('a new tail is unaffected by the old one', () {
    expect(gate.claim('tail-1'), isTrue);
    gate.serve('tail-1');
    expect(gate.claim('tail-2'), isTrue);
  });

  test('releasing a foreign id touches nothing', () {
    expect(gate.claim('tail-1'), isTrue);
    gate.release('tail-2');
    expect(gate.claim('tail-1'), isFalse);
    expect(gate.claim('tail-2'), isTrue);
  });
}
