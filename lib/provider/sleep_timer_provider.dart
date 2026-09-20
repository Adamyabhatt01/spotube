import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';

class SleepTimerNotifier extends StateNotifier<Duration?> {
  SleepTimerNotifier() : super(null);

  Timer? _timer;

  void setSleepTimer(Duration duration) {
    state = duration;

    // Cancel the previous timer first: re-setting the timer used to leave the
    // old one armed, so the app exited at the earlier deadline however much
    // time the user had just asked for.
    _timer?.cancel();
    _timer = Timer(duration, () {
      exit(0);
    });
  }

  void cancelSleepTimer() {
    state = null;
    _timer?.cancel();
    _timer = null;
  }
}

final sleepTimerProvider = StateNotifierProvider<SleepTimerNotifier, Duration?>(
  (ref) => SleepTimerNotifier(),
);
