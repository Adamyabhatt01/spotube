import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/hooks/configurators/use_window_listener.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/wm_tools/close_guard.dart';

import 'package:local_notifier/local_notifier.dart';
import 'package:spotube/utils/platform.dart';
import 'package:window_manager/window_manager.dart';

final closeNotification = !kIsDesktop
    ? null
    : (LocalNotification(
        title: 'Spotube',
        body: 'Running in background. Minimized to System Tray',
        actions: [
          LocalNotificationAction(text: 'Close The App'),
        ],
      )..onClickAction = (value) {
        exit(0);
      });

void useCloseBehavior(WidgetRef ref) {
  useWindowListener(
    onWindowClose: () async {
      // Backstop for the window-manager ordering: if a close arrives while
      // the unawaited install is still in flight, decide only after
      // interception is actually in place.
      await CloseGuard.instance.ready;
      final preferences = ref.read(userPreferencesProvider);
      if (preferences.closeBehavior == CloseBehavior.minimizeToTray) {
        await windowManager.hide();
        closeNotification?.show();
      } else {
        exit(0);
      }
    },
  );
}
