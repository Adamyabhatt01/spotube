import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/modules/splash/splash_screen.dart';

/// Splash customization, persisted in SharedPreferences (no DB
/// migration needed). All fields degrade to built-in defaults.
class SplashPrefs {
  final SplashAnimation animation;
  final Duration duration;
  final bool useThemedBackground;

  /// Absolute path of a user-picked logo file, if any.
  final String? logoPath;

  /// Absolute path of a user-picked background file (static or
  /// animated GIF/WebP — decoded natively), if any.
  final String? backgroundPath;

  const SplashPrefs({
    this.animation = SplashAnimation.fade,
    this.duration = const Duration(milliseconds: 900),
    this.useThemedBackground = true,
    this.logoPath,
    this.backgroundPath,
  });

  static const _prefix = 'spotube.splash';

  SplashPrefs copyWith({
    SplashAnimation? animation,
    Duration? duration,
    bool? useThemedBackground,
    String? Function()? logoPath,
    String? Function()? backgroundPath,
  }) {
    return SplashPrefs(
      animation: animation ?? this.animation,
      duration: duration ?? this.duration,
      useThemedBackground: useThemedBackground ?? this.useThemedBackground,
      logoPath: logoPath != null ? logoPath() : this.logoPath,
      backgroundPath:
          backgroundPath != null ? backgroundPath() : this.backgroundPath,
    );
  }

  static SplashAnimation _animationFrom(String? name) {
    return SplashAnimation.values.asNameMap()[name] ?? SplashAnimation.fade;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix.animation', animation.name);
    await prefs.setInt('$_prefix.durationMs', duration.inMilliseconds);
    await prefs.setBool('$_prefix.themedBackground', useThemedBackground);
    if (logoPath == null) {
      await prefs.remove('$_prefix.logoPath');
    } else {
      await prefs.setString('$_prefix.logoPath', logoPath!);
    }
    if (backgroundPath == null) {
      await prefs.remove('$_prefix.backgroundPath');
    } else {
      await prefs.setString('$_prefix.backgroundPath', backgroundPath!);
    }
  }

  static Future<SplashPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Future<String?> validPath(String? path) async {
        if (path == null) return null;
        return await File(path).exists() ? path : null;
      }

      return SplashPrefs(
        animation: _animationFrom(prefs.getString('$_prefix.animation')),
        duration: Duration(
          milliseconds: prefs.getInt('$_prefix.durationMs') ?? 900,
        ),
        useThemedBackground: prefs.getBool('$_prefix.themedBackground') ?? true,
        logoPath: await validPath(prefs.getString('$_prefix.logoPath')),
        backgroundPath:
            await validPath(prefs.getString('$_prefix.backgroundPath')),
      );
    } catch (_) {
      return const SplashPrefs();
    }
  }
}

class SplashPrefsNotifier extends AsyncNotifier<SplashPrefs> {
  @override
  Future<SplashPrefs> build() async => SplashPrefs.load();

  Future<void> _update(SplashPrefs Function(SplashPrefs) fn) async {
    final next = fn(state.valueOrNull ?? const SplashPrefs());
    state = AsyncData(next);
    await next.save();
  }

  Future<void> setAnimation(SplashAnimation animation) =>
      _update((s) => s.copyWith(animation: animation));

  Future<void> setDuration(Duration duration) =>
      _update((s) => s.copyWith(duration: duration));

  Future<void> setThemedBackground(bool value) =>
      _update((s) => s.copyWith(useThemedBackground: value));

  /// Copies a picked image into app storage and records it. `kind`
  /// selects the logo or background slot; null clears the slot.
  Future<void> setFile(String kind, File? file) async {
    if (file == null) {
      if (kind == 'logo') {
        await _update((s) => s.copyWith(logoPath: () => null));
      } else {
        await _update((s) => s.copyWith(backgroundPath: () => null));
      }
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final target =
        File(p.join(dir.path, 'splash-$kind${p.extension(file.path)}'));
    await target.writeAsBytes(await file.readAsBytes(), flush: true);
    if (kind == 'logo') {
      await _update((s) => s.copyWith(logoPath: () => target.path));
    } else {
      await _update((s) => s.copyWith(backgroundPath: () => target.path));
    }
  }
}

final splashPrefsProvider =
    AsyncNotifierProvider<SplashPrefsNotifier, SplashPrefs>(
  SplashPrefsNotifier.new,
);
