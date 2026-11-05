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

  static const _contextMenuConfigKey = 'contextMenu.config';

  /// Raw JSON for the user's context-menu configuration.
  ///
  /// Stored as one KV string rather than a Drift column: it is a small,
  /// per-profile UI preference, and keeping it here avoids a schema migration
  /// for a value only the menu builder reads.
  static String? get contextMenuConfigJson =>
      sharedPreferences.getString(_contextMenuConfigKey);

  static Future<void> setContextMenuConfigJson(String value) async =>
      await sharedPreferences.setString(_contextMenuConfigKey, value);

  static Future<void> clearContextMenuConfig() async =>
      await sharedPreferences.remove(_contextMenuConfigKey);

  static const _voiceCommandsConfigKey = 'voiceCommands.config';

  /// Raw JSON for the voice-commands configuration. Absent or malformed means
  /// `mode: off`, which is why the feature is inert for anyone who has never
  /// flipped its settings switch.
  static String? get voiceCommandsConfigJson =>
      sharedPreferences.getString(_voiceCommandsConfigKey);

  static Future<void> setVoiceCommandsConfigJson(String value) async =>
      await sharedPreferences.setString(_voiceCommandsConfigKey, value);

  static const _voiceStartingKey = 'voice.starting';

  /// Set before the voice worker starts, cleared after it has run healthy for
  /// a few seconds. Still being set at launch means the previous session died
  /// during startup: an onnxruntime fault is not isolate-contained, and the
  /// wake stage restarts automatically, so one bad model could crash-loop every
  /// launch. Launch then disables voice instead of retrying it.
  static bool get voiceCrashMarker =>
      sharedPreferences.getBool(_voiceStartingKey) ?? false;

  static Future<void> markVoiceStarting() async =>
      await sharedPreferences.setBool(_voiceStartingKey, true);

  static Future<void> clearVoiceStarting() async =>
      await sharedPreferences.remove(_voiceStartingKey);

  /// Prefix for one theme's own settings namespace.
  ///
  /// The contract names it `theme.<author>.<name>.<key>`; the trailing dot is
  /// part of the prefix so `theme.a.b` cannot read `theme.a.bc.*`.
  static String themeSettingsPrefix(String author, String name) =>
      'theme.$author.$name.';

  /// Every persisted setting for one theme, keyed by the theme's own key.
  ///
  /// Only scalars the settings actions accept are surfaced. A future version
  /// that stores a structured value is ignored instead of being handed to a
  /// binding that expects a string or number.
  static Map<String, Object?> themeSettings(String author, String name) {
    final prefix = themeSettingsPrefix(author, name);
    final result = <String, Object?>{};
    for (final key in sharedPreferences.getKeys()) {
      if (!key.startsWith(prefix) || key.length == prefix.length) continue;
      final value = sharedPreferences.get(key);
      if (value is bool || value is num || value is String) {
        result[key.substring(prefix.length)] = value;
      }
    }
    return result;
  }

  static Future<void> setThemeSetting(
    String author,
    String name,
    String key,
    Object? value,
  ) async {
    final storageKey = '${themeSettingsPrefix(author, name)}$key';
    if (value == null) {
      await sharedPreferences.remove(storageKey);
      return;
    }
    if (value is bool) {
      await sharedPreferences.setBool(storageKey, value);
    } else if (value is int) {
      await sharedPreferences.setInt(storageKey, value);
    } else if (value is double) {
      await sharedPreferences.setDouble(storageKey, value.isFinite ? value : 0);
    } else if (value is num) {
      await sharedPreferences.setDouble(storageKey, value.toDouble());
    } else if (value is String) {
      await sharedPreferences.setString(storageKey, value);
    }
  }

  /// Drops the whole namespace. Called by the reset action; the next build
  /// reads an empty map.
  static Future<void> clearThemeSettings(String author, String name) async {
    final prefix = themeSettingsPrefix(author, name);
    for (final key in sharedPreferences.getKeys().toList()) {
      if (key.startsWith(prefix)) await sharedPreferences.remove(key);
    }
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

  /// Requested crossfade length between tracks, in seconds. 0 disables it.
  /// KV rather than a drift column for the same reason as spatial audio: one
  /// session-independent audio toggle the effects layer composes.
  static double get crossfadeDuration {
    final value = sharedPreferences.getDouble('crossfadeDuration') ?? 0;
    return value.isFinite && value > 0 ? value : 0;
  }

  static Future<void> setCrossfadeDuration(double seconds) async {
    if (!seconds.isFinite || seconds < 0) return;
    await sharedPreferences.setDouble('crossfadeDuration', seconds);
  }

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
