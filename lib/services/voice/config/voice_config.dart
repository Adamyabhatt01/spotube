// The persisted voice-commands configuration: one KV JSON blob, versioned,
// malformed input degrading to defaults — the contextMenuConfigJson
// precedent, not Drift.
import 'dart:convert';

import '../matching/phrase_matcher.dart';
import '../matching/text_normalizer.dart';
import '../defaults/phrase_defaults.dart';

enum VoiceMode {
  off('off'),
  tapToTalk('tapToTalk'),
  wake('wake');

  const VoiceMode(this.wire);
  final String wire;

  static VoiceMode fromWire(String v) =>
      VoiceMode.values.firstWhere((e) => e.wire == v, orElse: () => off);
}

class VoiceConfig {
  static const currentVersion = 1;

  final int v;
  final VoiceMode mode;
  final VoiceLanguage primaryLanguage;

  /// Extra phrase sets merged into matching; the stage-2 model still follows
  /// [primaryLanguage] in v1.
  final VoiceLanguage? secondaryLanguage;

  /// Desktop only: keep the listener alive when the window loses focus
  /// (music-in-background is the main use case). Default off for privacy.
  final bool listenWhileMinimized;

  /// Per-language so a switch changes neither storage nor display.
  /// An absent/null inner list means "defaults for that language".
  final Map<String, List<String>> wakePhrases;
  final Map<String, Map<String, List<String>>> commandPhrases;

  const VoiceConfig({
    this.v = currentVersion,
    this.mode = VoiceMode.off,
    this.primaryLanguage = VoiceLanguage.en,
    this.secondaryLanguage,
    this.listenWhileMinimized = false,
    this.wakePhrases = const {},
    this.commandPhrases = const {},
  });

  bool get enabled => mode != VoiceMode.off;

  List<String> wakePhrasesFor(VoiceLanguage lang) =>
      wakePhrases[lang.code] ?? defaultWakePhrases(lang);

  List<String> phrasesFor(VoiceCommandId id, VoiceLanguage lang) {
    final stored = commandPhrases[lang.code]?[id.name];
    if (stored != null && stored.isNotEmpty) return stored;
    return defaultCommandPhrases(lang, id);
  }

  /// All active phrase sets for the worker: primary + secondary merged.
  Map<VoiceCommandId, List<String>> activeCommandPhrases() {
    final langs = [
      primaryLanguage,
      if (secondaryLanguage != null) secondaryLanguage!
    ];
    final out = <VoiceCommandId, List<String>>{};
    for (final id in VoiceCommandId.values) {
      out[id] = {for (final l in langs) ...phrasesFor(id, l)}.toList();
    }
    return out;
  }

  List<String> activeWakePhrases() {
    final langs = [
      primaryLanguage,
      if (secondaryLanguage != null) secondaryLanguage!
    ];
    return [for (final l in langs) ...wakePhrasesFor(l)];
  }

  /// Language changes go here, not through [copyWith]: a null secondary means
  /// "no second language", and copyWith's `??` cannot tell that from "leave it
  /// alone". Both fields are decided on every call.
  VoiceConfig withLanguage({
    VoiceLanguage? primary,
    VoiceLanguage? secondary,
  }) =>
      VoiceConfig(
        v: v,
        mode: mode,
        primaryLanguage: primary ?? primaryLanguage,
        secondaryLanguage: secondary,
        listenWhileMinimized: listenWhileMinimized,
        wakePhrases: wakePhrases,
        commandPhrases: commandPhrases,
      );

  VoiceConfig copyWith({
    VoiceMode? mode,
    VoiceLanguage? primaryLanguage,
    VoiceLanguage? secondaryLanguage,
    bool? listenWhileMinimized,
    Map<String, List<String>>? wakePhrases,
    Map<String, Map<String, List<String>>>? commandPhrases,
  }) =>
      VoiceConfig(
        v: v,
        mode: mode ?? this.mode,
        primaryLanguage: primaryLanguage ?? this.primaryLanguage,
        secondaryLanguage: secondaryLanguage ?? this.secondaryLanguage,
        listenWhileMinimized: listenWhileMinimized ?? this.listenWhileMinimized,
        wakePhrases: wakePhrases ?? this.wakePhrases,
        commandPhrases: commandPhrases ?? this.commandPhrases,
      );

  Map<String, dynamic> toJson() => {
        'v': v,
        'mode': mode.wire,
        'primaryLanguage': primaryLanguage.code,
        'secondaryLanguage': secondaryLanguage?.code,
        'listenWhileMinimized': listenWhileMinimized,
        'wakePhrases': wakePhrases,
        'commandPhrases': commandPhrases,
      };

  static VoiceConfig fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> readWake(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final e in raw.entries)
          if (e.value is List)
            e.key.toString(): [
              for (final p in (e.value as List))
                if (p is String) p,
            ],
      };
    }

    Map<String, Map<String, List<String>>> readCommands(Object? raw) {
      if (raw is! Map) return const {};
      final out = <String, Map<String, List<String>>>{};
      for (final lang in raw.entries) {
        if (lang.value is! Map) continue;
        final cmds = {
          for (final cmd in (lang.value as Map).entries)
            if (cmd.value is List &&
                VoiceCommandId.values.any((i) => i.name == cmd.key))
              cmd.key.toString(): [
                for (final p in (cmd.value as List))
                  if (p is String) p,
              ],
        };
        if (cmds.isNotEmpty) out[lang.key.toString()] = cmds;
      }
      return out;
    }

    return VoiceConfig(
      v: json['v'] is int ? json['v'] as int : currentVersion,
      mode: VoiceMode.fromWire(json['mode'] as String? ?? 'off'),
      primaryLanguage:
          VoiceLanguage.fromCode(json['primaryLanguage'] as String? ?? 'en'),
      secondaryLanguage: json['secondaryLanguage'] is String
          ? VoiceLanguage.fromCode(json['secondaryLanguage'] as String)
          : null,
      listenWhileMinimized: json['listenWhileMinimized'] == true,
      wakePhrases: readWake(json['wakePhrases']),
      commandPhrases: readCommands(json['commandPhrases']),
    );
  }

  /// Never throws: anything malformed becomes the all-defaults config, which
  /// is `mode: off` anyway.
  static VoiceConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return const VoiceConfig();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const VoiceConfig();
      return fromJson(json);
    } on FormatException {
      return const VoiceConfig();
    }
  }

  String encode() => jsonEncode(toJson());
}
