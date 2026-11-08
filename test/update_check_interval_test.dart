// The launch update checks (app release + two plugin checks) run at most
// once per 24h instead of once per launch, keyed off a persisted timestamp.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/provider/metadata_plugin/updater/update_checker.dart';

void main() {
  final now = DateTime(2026, 9, 24, 12);

  test('never checked reads as due', () {
    expect(isUpdateCheckDue(0, now), isTrue);
  });

  test('a recent check suppresses the launch burst', () {
    final anHourAgo =
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    expect(isUpdateCheckDue(anHourAgo, now), isFalse);
  });

  test('a day-old check reads as due', () {
    final yesterday =
        now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    expect(isUpdateCheckDue(yesterday, now), isTrue);
  });

  test('just under the interval still suppresses', () {
    final almostDue = now
        .subtract(const Duration(hours: 23, minutes: 59))
        .millisecondsSinceEpoch;
    expect(isUpdateCheckDue(almostDue, now), isFalse);
  });

  test('clock skew into the future reads as due, not suppressed forever', () {
    final future = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
    expect(isUpdateCheckDue(future, now), isTrue);
  });
}
