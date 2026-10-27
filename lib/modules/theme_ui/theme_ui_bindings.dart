import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/metadata_plugin/core/user.dart';
import 'package:spotube/provider/volume_provider.dart';

/// A point-in-time view of the data a theme UI may bind to.
///
/// The map keeps the raw values (a [Duration], a bool, a number) so a
/// `conditional` can compare them, while [display] is the human-readable form
/// a `text` node shows. Keeping the two apart matters: `player.loop` compares
/// as `loop`/`single`/`none`, but reads as `ALL`/`ONE`/`OFF` in the UI.
class ThemeUiBindings {
  final Map<String, Object?> values;

  const ThemeUiBindings(this.values);

  Object? raw(String? name) => name == null ? null : values[name];

  bool isTruthy(String? name) {
    final value = raw(name);
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    return true;
  }

  bool matches(String? name, Object? expected) {
    final value = raw(name);
    if (expected == null) return isTruthy(name);
    if (expected is bool) return isTruthy(name) == expected;
    if (expected is num && value is num) return value == expected;
    if (expected is String) {
      if (value is bool) return value.toString() == expected;
      if (value is num) return value.toString() == expected;
      return value == expected;
    }
    return value == expected;
  }

  String display(String? name) {
    final value = raw(name);
    return switch (value) {
      null => '',
      Duration duration => formatDuration(duration),
      DateTime time => '${_two(time.hour)}:${_two(time.minute)}',
      bool boolean => boolean ? 'ON' : 'OFF',
      double number => name == 'player.volume'
          ? '${(number * 100).round()}%'
          : _trimNumber(number),
      num number => _trimNumber(number.toDouble()),
      String text => switch (name) {
          'player.loop' => switch (text) {
              'loop' => 'ALL',
              'single' => 'ONE',
              'none' => 'OFF',
              _ => text.toUpperCase(),
            },
          _ => text,
        },
      _ => value.toString(),
    };
  }
}

/// Bindings a page publishes to the slots it contains.
///
/// Slot content is rendered deep inside the page's tree, so passing the map
/// explicitly through every intermediate widget would couple host widgets to
/// the theme system. The scope is read by [ThemeUiHost]'s slot builder and
/// merged over the app-wide bindings; it is empty on every host-owned page.
class ThemeUiPageBindings extends InheritedWidget {
  final Map<String, Object?> values;

  const ThemeUiPageBindings({
    required this.values,
    required super.child,
    super.key,
  });

  static Map<String, Object?>? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ThemeUiPageBindings>()
        ?.values;
  }

  /// The page's bindings without subscribing the caller.
  ///
  /// Actions run outside build, where `dependOnInheritedWidgetOfExactType`
  /// is not allowed. A collection play action reads the track list through
  /// this, once, at tap time.
  static Map<String, Object?>? read(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ThemeUiPageBindings>()
        ?.values;
  }

  @override
  bool updateShouldNotify(ThemeUiPageBindings oldWidget) {
    return oldWidget.values != values;
  }
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${_two(seconds)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _trimNumber(double value) {
  if (!value.isFinite) return '0';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The latest whole-second position tick. Auto-disposed so a theme with no
/// position-bound UI does not keep a listener after its slots unmount.
final themePlayerPositionProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.read(audioPlayerPortProvider).positionTickStream,
);

final themePlayerDurationProvider = StreamProvider.autoDispose<Duration>(
  (ref) => ref.read(audioPlayerPortProvider).durationStream,
);

/// Package metadata is a platform-channel call; one lookup per session is
/// enough, and an unavailable channel (tests, a stripped build) is "".
final themeAppVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '';
  }
});

/// Builds the binding snapshot for the current frame.
///
/// `brightness` and `themeMode` come from the widget tree because they are
/// presentation state, not provider state. Everything else is watched, so a
/// slot rebuilds on the smallest change the binding needs.
ThemeUiBindings buildThemeUiBindings(
  WidgetRef ref, {
  required Brightness brightness,
  required String themeMode,
}) {
  final player = ref.watch(audioPlayerProvider);
  final track = player.activeTrack;
  final volume = ref.watch(volumeProvider);
  final user = ref.watch(metadataPluginUserProvider).asData?.value;
  final position = ref.watch(themePlayerPositionProvider).asData?.value ??
      ref.read(audioPlayerPortProvider).position;
  final duration = ref.watch(themePlayerDurationProvider).asData?.value ??
      ref.read(audioPlayerPortProvider).duration;
  final version = ref.watch(themeAppVersionProvider).asData?.value ?? '';
  final now = DateTime.now();

  return ThemeUiBindings({
    'player.trackId': track?.id ?? '',
    'player.title': track?.name ?? '',
    'player.artist':
        track?.artists.map((artist) => artist.name).join(', ') ?? '',
    'player.album': track?.album.name ?? '',
    'player.artwork': track?.album.images.asUrlString(
          placeholder: ImagePlaceholder.albumArt,
        ) ??
        placeholderUrlMap[ImagePlaceholder.albumArt]!,
    'player.playing': player.playing,
    'player.loop': player.loopMode.name,
    'player.shuffled': player.shuffled,
    'player.position': position,
    'player.duration': duration,
    'player.volume': volume,
    'user.name': user?.name ?? '',
    'user.avatar': user?.images.asUrlString(
          placeholder: ImagePlaceholder.artist,
        ) ??
        placeholderUrlMap[ImagePlaceholder.artist]!,
    'app.version': version,
    'app.brightness': brightness.name,
    'app.themeMode': themeMode,
    'app.greeting': greetingFor(now),
    'clock.now': now,
  });
}

/// The time-of-day greeting a home screen may draw.
///
/// Pure so the bucket boundaries are testable without mocking the clock.
String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 18) return 'Good afternoon';
  return 'Good evening';
}
