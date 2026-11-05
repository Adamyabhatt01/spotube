// The voice configuration as app state: read once from KV, written back on
// every edit. Kept separate from the controller so a settings page can edit
// phrases while the engine is stopped, and so the JSON decode failure mode
// (defaults, `mode: off`) stays a pure function of the stored string.
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/voice/config/voice_config.dart';
import 'package:spotube/services/voice/matching/phrase_matcher.dart';
import 'package:spotube/services/voice/matching/text_normalizer.dart';

class VoiceConfigNotifier extends Notifier<VoiceConfig> {
  @override
  VoiceConfig build() => VoiceConfig.decode(
        KVStoreService.isInitialized
            ? KVStoreService.voiceCommandsConfigJson
            : null,
      );

  Future<void> _persist(VoiceConfig next) async {
    state = next;
    if (!KVStoreService.isInitialized) return;
    await KVStoreService.setVoiceCommandsConfigJson(next.encode());
  }

  Future<void> setMode(VoiceMode mode) => _persist(state.copyWith(mode: mode));

  /// Used by the crash-loop guard: the feature turns itself off and says why,
  /// rather than starting the same failing isolate on the next launch.
  Future<void> disableAfterCrash() => _persist(
        state.copyWith(mode: VoiceMode.off),
      );

  Future<void> setPrimaryLanguage(VoiceLanguage language) => _persist(
        state.withLanguage(
          primary: language,
          // A language cannot also be the second set.
          secondary: state.secondaryLanguage == language
              ? null
              : state.secondaryLanguage,
        ),
      );

  /// Null clears the second set. Choosing the primary language is refused
  /// rather than silently reinterpreted: the caller cannot end up with a
  /// configuration it did not ask for.
  Future<void> setSecondaryLanguage(VoiceLanguage? language) {
    if (language != null && language == state.primaryLanguage) {
      return Future.value();
    }
    return _persist(
      state.withLanguage(
        secondary: language,
        // withLanguage keeps the current primary when given null, and a real
        // primary is always non-null, so this is the unchanged value.
        primary: state.primaryLanguage,
      ),
    );
  }

  Future<void> setListenWhileMinimized(bool value) =>
      _persist(state.copyWith(listenWhileMinimized: value));

  /// An empty list means "back to the shipped defaults", which is stored as the
  /// key being absent so a later default-table update reaches the user.
  Future<void> setWakePhrases(VoiceLanguage language, List<String> phrases) {
    final trimmed = [for (final p in phrases) p.trim().toLowerCase()].toList();
    final next = Map<String, List<String>>.from(state.wakePhrases);
    if (trimmed.isEmpty) {
      next.remove(language.code);
    } else {
      next[language.code] = trimmed;
    }
    return _persist(state.copyWith(wakePhrases: next));
  }

  Future<void> setCommandPhrases(
    VoiceCommandId id,
    VoiceLanguage language,
    List<String> phrases,
  ) {
    final trimmed = [for (final p in phrases) p.trim().toLowerCase()].toList();
    final byLanguage =
        Map<String, Map<String, List<String>>>.from(state.commandPhrases);
    final byCommand = Map<String, List<String>>.from(
      byLanguage[language.code] ?? const {},
    );
    if (trimmed.isEmpty) {
      byCommand.remove(id.name);
    } else {
      byCommand[id.name] = trimmed;
    }
    if (byCommand.isEmpty) {
      byLanguage.remove(language.code);
    } else {
      byLanguage[language.code] = byCommand;
    }
    return _persist(state.copyWith(commandPhrases: byLanguage));
  }

  Future<void> resetAll() => _persist(const VoiceConfig());
}

final voiceConfigProvider =
    NotifierProvider<VoiceConfigNotifier, VoiceConfig>(
  VoiceConfigNotifier.new,
);
