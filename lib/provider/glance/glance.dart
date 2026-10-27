import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:spotube/services/artwork_cache_manager.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/foreground_coalescer.dart';
import 'package:spotube/utils/platform.dart';

/// The playback-server client for the background callback. Top-level finals
/// are lazy in Dart, so nothing is created until a command actually runs.
final _glanceDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
  ),
);

@pragma("vm:entry-point")
Future<void> glanceBackgroundCallback(Uri? data) async {
  try {
    if (data == null ||
        data.host != "playback" ||
        data.pathSegments.isEmpty ||
        data.queryParameters["serverAddress"] == null) {
      return;
    }

    final command = data.pathSegments.first;
    // validateStatus always true so a non-200 reaches the explicit check
    // below instead of dio's own throw — same shape as the http.get it
    // replaced.
    final res = await _glanceDio.getUri<Object>(
      Uri.parse(
        "http://${data.queryParameters["serverAddress"]}/playback/$command",
      ),
      options: Options(validateStatus: (_) => true),
    );

    if (res.statusCode != 200) {
      throw Exception("Failed to execute command: $command\nBody: ${res.data}");
    }
  } catch (e, stack) {
    // Routed through AppLogger (level gate + release file sink), with the
    // stack trace, so the failure's origin is recoverable from the log.
    AppLogger.reportError(e, stack, "GlanceBackgroundCallback");
  }
}

Future<bool?> _saveWidgetData<T>(String key, T? value) async {
  try {
    if (!kIsMobile) return null;

    return await HomeWidget.saveWidgetData<T>(key, value);
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
    return null;
  }
}

Future<void> _updateWidget() async {
  try {
    if (!kIsMobile) return;

    if (kIsAndroid) {
      await HomeWidget.updateWidget(
        androidName: 'HomePlayerWidgetReceiver',
        qualifiedAndroidName:
            'oss.krtirtho.spotube.glance.HomePlayerWidgetReceiver',
      );
    }
    if (kIsIOS) {
      await HomeWidget.updateWidget(
        name: 'HomePlayerWidget',
        iOSName: 'HomePlayerWidget',
      );
    }
  } on Exception catch (e, stack) {
    AppLogger.reportError(e, stack);
  }
}

Future<void> _sendActiveTrack(
  SpotubeTrackObject? track, {
  bool notify = true,
}) async {
  if (track == null) {
    await _saveWidgetData("activeTrack", null);
    if (notify) await _updateWidget();
    return;
  }

  final jsonTrack = track.toJson();

  final image = track.album.images.firstOrNull;
  final cachedImage = image == null
      ? null
      : image.url.startsWith("http")
          ? (await ArtworkCacheManager.instance.getSingleFile(image.url)).path
          : image.url;
  final data = {
    ...jsonTrack,
    "album": {
      ...jsonTrack["album"],
      "images": [
        if (cachedImage != null && image != null)
          {
            ...image.toJson(),
            "path": cachedImage,
          }
      ]
    }
  };

  await _saveWidgetData("activeTrack", jsonEncode(data));

  if (notify) await _updateWidget();
}

final glanceProvider = Provider((ref) {
  final server = ref.read(serverProvider);
  final player = ref.read(audioPlayerPortProvider);
  final activeTrack = ref.read(audioPlayerProvider).activeTrack;

  String? serverAddress;
  server.whenData(
    (value) => serverAddress = "${value.server.address.host}:${value.port}",
  );

  // The single writer of the widget's data. Every playback signal routes
  // through the coalescer instead, so the widget is refreshed once per
  // backgrounding rather than once per second of playback.
  Future<void> pushCurrentState() async {
    if (serverAddress != null) {
      await _saveWidgetData("playbackServerAddress", serverAddress);
    }
    await _saveWidgetData("isPlaying", player.isPlaying);
    await _saveWidgetData("position", player.position.inSeconds);
    await _saveWidgetData("duration", player.duration.inSeconds);
    await _sendActiveTrack(
      ref.read(audioPlayerProvider).activeTrack,
      notify: false,
    );
    await _updateWidget();
  }

  final pushes = ForegroundCoalescer(
    push: pushCurrentState,
    isForeground: () =>
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
  );

  // [WidgetsBinding] publishes the new state before notifying observers, so
  // [isForeground] is already accurate inside these callbacks.
  final lifecycle = AppLifecycleListener(
    onInactive: () => pushes.onForegroundChanged(false),
    onHide: () => pushes.onForegroundChanged(false),
    onPause: () => pushes.onForegroundChanged(false),
  );

  // Startup is not a playback signal: seeding the widget with the restored
  // queue's track is what lets it show anything before the first backgrounding.
  _sendActiveTrack(activeTrack);

  ref.listen(serverProvider, (prev, next) {
    next.whenData((value) {
      serverAddress = "${value.server.address.host}:${value.port}";
      pushes.request();
    });
  });

  ref.listen(
    audioPlayerProvider,
    (previous, next) async {
      try {
        if (previous?.activeTrack != next.activeTrack &&
            next.activeTrack != null) {
          await pushes.request();
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    },
  );

  final subscriptions = [
    player.playingStream.listen((_) => pushes.request()),
    // The shared tick stream is already whole-second gated; the widget only
    // renders seconds, so no gate of its own.
    player.positionTickStream.listen((_) => pushes.request()),
    player.durationStream.listen((_) => pushes.request()),
  ];

  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    lifecycle.dispose();
  });
});
