import 'dart:convert';

import 'package:encrypt/encrypt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/services/wm_tools/wm_tools.dart';
import 'package:uuid/uuid.dart';

abstract class KVStoreService {
  static SharedPreferences? _sharedPreferences;
  static SharedPreferences get sharedPreferences => _sharedPreferences!;
  static bool get isInitialized => _sharedPreferences != null;

  static const _themePinPrefix = 'theme.pins.';

  /// Playlist pins grouped by theme-declared pin target.
  ///
  /// The sidebar keeps its historical column in the preferences row; every
  /// other target a theme declares lives here, so one playlist can be pinned
  /// to several bars independently.
  static Map<String, List<String>> themePinTargets() {
    final result = <String, List<String>>{};
    for (final key in sharedPreferences.getKeys()) {
      if (!key.startsWith(_themePinPrefix)) continue;
      final target = key.substring(_themePinPrefix.length);
      if (target.isEmpty) continue;
      final ids = sharedPreferences.getStringList(key);
      if (ids == null || ids.isEmpty) continue;
      result[target] = List.unmodifiable(ids);
    }
    return result;
  }

  static Future<void> setThemePinTarget(String target, List<String> ids) async {
    final key = '$_themePinPrefix$target';
    if (ids.isEmpty) {
      await sharedPreferences.remove(key);
      return;
    }
    await sharedPreferences.setStringList(key, ids);
  }

  static Future<void> initialize() async {
    _sharedPreferences = await SharedPreferences.getInstance();
  }

  static bool get doneGettingStarted =>
      sharedPreferences.getBool('doneGettingStarted') ?? false;
  static Future<void> setDoneGettingStarted(bool value) async =>
      await sharedPreferences.setBool('doneGettingStarted', value);

  static bool get askedForBatteryOptimization =>
      sharedPreferences.getBool('askedForBatteryOptimization') ?? false;
  static Future<void> setAskedForBatteryOptimization(bool value) async =>
      await sharedPreferences.setBool('askedForBatteryOptimization', value);

  static List<String> get recentSearches =>
      sharedPreferences.getStringList('recentSearches') ?? [];

  /// Cap on retained recent searches. The list was prepend-only, so it grew
  /// for the app's whole lifetime in SharedPreferences — and the per-keystroke
  /// autocomplete filter re-read and fuzzy-matched all of it.
  static const int maxRecentSearches = 20;

  static Future<void> setRecentSearches(List<String> value) async =>
      await sharedPreferences.setStringList(
          'recentSearches', value.take(maxRecentSearches).toList());

  static WindowSize? get windowSize {
    final raw = sharedPreferences.getString('windowSize');

    if (raw == null) {
      return null;
    }
    return WindowSize.fromJson(jsonDecode(raw));
  }

  static Future<void> setWindowSize(WindowSize value) async =>
      await sharedPreferences.setString(
        'windowSize',
        jsonEncode(
          value.toJson(),
        ),
      );

  static String get encryptionKey {
    final value = sharedPreferences.getString('encryption');

    final key = const Uuid().v4();
    if (value == null) {
      setEncryptionKey(key);
      return key;
    }

    return value;
  }

  static Future<void> setEncryptionKey(String key) async {
    await sharedPreferences.setString('encryption', key);
  }

  static IV get ivKey {
    final iv = sharedPreferences.getString('iv');
    final value = IV.fromSecureRandom(8);

    if (iv == null) {
      setIVKey(value);

      return value;
    }

    return IV.fromBase64(iv);
  }

  static Future<void> setIVKey(IV iv) async {
    await sharedPreferences.setString('iv', iv.base64);
  }

  static double get volume => sharedPreferences.getDouble('volume') ?? 1.0;
  static Future<void> setVolume(double value) async =>
      await sharedPreferences.setDouble('volume', value);

  /// Last dragged size of a theme's `resizable` node, keyed by its
  /// `storageKey`. A non-finite stored value reads as absent rather than
  /// poisoning a constraint.
  static double resizableSize(String key, double fallback) {
    final value = sharedPreferences.getDouble('resizable.$key');
    if (value == null || !value.isFinite) return fallback;
    return value;
  }

  /// The stored size, or null when this key has never been dragged.
  static double? resizableSizeOrNull(String key) {
    final value = sharedPreferences.getDouble('resizable.$key');
    if (value == null || !value.isFinite) return null;
    return value;
  }

  static Future<void> setResizableSize(String key, double value) async {
    if (!value.isFinite) return;
    await sharedPreferences.setDouble('resizable.$key', value);
  }

  static Future<void> clearResizableSize(String key) async =>
      await sharedPreferences.remove('resizable.$key');

  /// Collapsed flag of a theme's `collapsible` shell region.
  static bool resizableCollapsed(String key) =>
      sharedPreferences.getBool('collapsed.$key') ?? false;

  static Future<void> setResizableCollapsed(String key, bool value) async =>
      await sharedPreferences.setBool('collapsed.$key', value);

  /// Stereo widening used by the "Virtual surround" equalizer tile.
  static bool get spatialAudio =>
      sharedPreferences.getBool('spatialAudio') ?? false;
  static Future<void> setSpatialAudio(bool value) async =>
      await sharedPreferences.setBool('spatialAudio', value);

  /// Mono downmix used by the "Mono audio" equalizer tile.
  static bool get monoAudio => sharedPreferences.getBool('monoAudio') ?? false;
  static Future<void> setMonoAudio(bool value) async =>
      await sharedPreferences.setBool('monoAudio', value);

  static bool get hasMigratedToDrift =>
      sharedPreferences.getBool('hasMigratedToDrift') ?? false;
  static Future<void> setHasMigratedToDrift(bool value) async =>
      await sharedPreferences.setBool('hasMigratedToDrift', value);

  static Map<String, dynamic>? get _youtubeEnginePaths {
    final jsonRaw = sharedPreferences.getString('ytDlpPath');

    if (jsonRaw == null) {
      return null;
    }

    return jsonDecode(jsonRaw);
  }

  static String? getYoutubeEnginePath(YoutubeClientEngine engine) {
    return _youtubeEnginePaths?[engine.name];
  }

  static Future<void> setYoutubeEnginePath(
    YoutubeClientEngine engine,
    String path,
  ) async {
    await sharedPreferences.setString(
      'ytDlpPath',
      jsonEncode({
        ...?_youtubeEnginePaths,
        engine.name: path,
      }),
    );
  }
}
