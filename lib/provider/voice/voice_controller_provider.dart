// Owns the microphone and the worker isolate: one owner per session, so the
// live listener and the settings phrase test cannot both grab the mic. Decides
// whether the engine should be running from the stored config, the models on
// disk, the microphone, and whether the app is foregrounded — and never starts
// something it cannot name in [VoiceControllerState.phase].
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/provider/dio/dio_provider.dart';
import 'package:spotube/provider/voice/voice_config_provider.dart';
import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/voice/config/voice_config.dart';
import 'package:spotube/services/voice/engine/pcm_capture_port.dart';
import 'package:spotube/services/voice/engine/voice_engine.dart';
import 'package:spotube/services/voice/matching/phrase_matcher.dart';
import 'package:spotube/services/voice/models/voice_model_downloader.dart';
import 'package:spotube/services/voice/models/voice_model_registry.dart';

enum VoiceControllerPhase {
  /// Voice is off: nothing is spawned and no microphone is open.
  disabled,

  /// Enabled, waiting for a tap. Engine kept warm after the first tap, mic
  /// closed — the privacy statement's promise that tap mode opens the
  /// microphone only on an explicit action.
  ready,

  /// Wake mode armed with the microphone open, no command window in flight.
  listening,

  /// A command window is open right now (tap, wake, or phrase test).
  windowOpen,

  /// A settings phrase test: hearing and transcribing, dispatching not.
  testing,

  /// Enabled, but the models this language/mode needs are not on disk.
  missingModels,

  /// Enabled, but the microphone is denied, muted, or the source is unusable.
  noMicrophone,

  /// The engine reported a failure or died.
  failed,
}

class VoiceControllerState {
  const VoiceControllerState({
    this.phase = VoiceControllerPhase.disabled,
    this.failure,
    this.detail,
    this.crashDisabled = false,
  });

  final VoiceControllerPhase phase;
  final VoiceFailure? failure;

  /// Capture error text, verbatim: "parec exited with code 1" says more than a
  /// category does.
  final String? detail;

  /// True when voice turned itself off because an earlier start-up died.
  final bool crashDisabled;

  bool get micOpen =>
      phase == VoiceControllerPhase.listening ||
      phase == VoiceControllerPhase.windowOpen ||
      phase == VoiceControllerPhase.testing;
}

/// Injection seams: tests drive this state machine with a fake engine and a
/// fixture capture; the app gets the real isolate and the real microphone.
final voiceEngineFactoryProvider =
    Provider<VoiceEngine Function()>((_) => IsolateVoiceEngine.new);

final voiceCaptureFactoryProvider = Provider<PcmCapturePort Function()>((ref) {
  if (Platform.isLinux) return PulsePcmCapture.new;
  if (Platform.isAndroid) return RecordPcmCapture.new;
  // Any other platform: the controller reports it instead of half-working.
  return () => throw UnsupportedError(
        'Voice capture is implemented for Linux and Android only',
      );
});

/// Where downloaded models live, outside any plugin asset area so a Flutter
/// upgrade cannot orphan 43 MB the user paid to download.
final voiceModelsDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/voice_models');
});

class VoiceController extends Notifier<VoiceControllerState> {
  static const _healthyDuration = Duration(seconds: 10);
  static const _duckVolume = 0.2;

  VoiceEngine? _engine;
  PcmCapturePort? _capture;
  StreamSubscription<VoiceEvent>? _events;
  StreamSubscription<Uint8List>? _micErrors;
  Timer? _healthyTimer;
  AppLifecycleListener? _lifecycle;
  StreamController<VoiceEvent>? _out;

  VoiceConfig _config = const VoiceConfig();
  bool _foreground = true;
  bool _testing = false;
  bool _ducked = false;
  bool _starting = false;

  /// Set while the provider is being disposed: reading another provider from a
  /// container that is already tearing down throws, and the ducked volume is
  /// runtime-only anyway — the player goes with it.
  bool _disposing = false;

  /// The microphone stopped producing (denied, missing `parec`, exited). Kept
  /// as a flag because the error arrives asynchronously and a tap in flight
  /// must not report an open window over it.
  bool _micBroken = false;

  /// A command window is in flight. Tracked as a flag, not as a phase, because
  /// the close event arrives while the phase still reads `windowOpen` and the
  /// decisions below must not race their own state.
  bool _windowOpen = false;

  /// Everything the engine reports, re-broadcast so a listener survives an
  /// engine restart — the isolate is recreated whenever the session restarts.
  Stream<VoiceEvent> get events =>
      (_out ??= StreamController<VoiceEvent>.broadcast()).stream;

  @override
  VoiceControllerState build() {
    // Read, not watch: a phrase edit in the editor must not tear down a live
    // session. The listener below pushes the change into the running worker.
    _config = ref.read(voiceConfigProvider);
    ref.listen<VoiceConfig>(voiceConfigProvider, (_, next) {
      _config = next;
      unawaited(sync());
    });

    _lifecycle?.dispose();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(_setForeground(false)),
      onInactive: () => unawaited(_setForeground(false)),
      onPause: () => unawaited(_setForeground(false)),
      onResume: () => unawaited(_setForeground(true)),
    );

    ref.onDispose(() {
      _disposing = true;
      _lifecycle?.dispose();
      _lifecycle = null;
      unawaited(_teardown());
      unawaited(_out?.close());
      _out = null;
    });

    if (_config.enabled &&
        KVStoreService.isInitialized &&
        KVStoreService.voiceCrashMarker) {
      // A start-up that died leaves the marker set (§2). The same model would
      // crash the process again — in wake mode, on every single launch.
      unawaited(KVStoreService.clearVoiceStarting());
      // Deferred: a provider may not modify another provider while it is being
      // built, and the settings page has to see the switch in the off position.
      unawaited(
        Future.microtask(
          () => ref.read(voiceConfigProvider.notifier).disableAfterCrash(),
        ),
      );
      _config = const VoiceConfig();
      return const VoiceControllerState(
        phase: VoiceControllerPhase.disabled,
        crashDisabled: true,
        detail: 'Voice was switched off after a crash during start-up.',
      );
    }

    unawaited(sync());
    return const VoiceControllerState();
  }

  Future<void> _setForeground(bool foreground) async {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      // A pause/hide is the app leaving cleanly enough to matter: an
      // ungraceful quit moments after voice started must not read as a
      // start-up crash on the next launch. A real crash never reaches here,
      // so the marker still catches those.
      if (KVStoreService.isInitialized) {
        unawaited(KVStoreService.clearVoiceStarting());
      }
      if (_windowOpen) {
        // A window in flight is closed properly, so its ducked volume is
        // restored and its partial transcript dispatched rather than dropped.
        await endTapWindow();
      }
    }
    await sync();
  }

  /// Bring the session to what [VoiceConfig] asks for, or stop it.
  Future<void> sync() async {
    if (_starting) return;

    if (!_config.enabled) {
      await _teardown();
      _setPhase(VoiceControllerPhase.disabled);
      return;
    }

    if (!voiceCommandsSupported(
      primary: _config.primaryLanguage,
      secondary: _config.secondaryLanguage,
    )) {
      // No verified model can transcribe this language: say so instead of
      // running the English recognizer against speech it cannot represent.
      await _teardown();
      state = VoiceControllerState(
        phase: VoiceControllerPhase.missingModels,
        detail: 'Voice commands are not available for this language yet.',
        crashDisabled: state.crashDisabled,
      );
      return;
    }

    final wakeStage = _config.mode == VoiceMode.wake;
    if (!await _modelsInstalled(withWakeStage: wakeStage)) {
      await _teardown();
      _setPhase(VoiceControllerPhase.missingModels);
      return;
    }

    final background = !(_foreground || _config.listenWhileMinimized);
    if (wakeStage && background) {
      // Wake mode is foreground-only unless the user opted into listening with
      // the window hidden; either way the always-on microphone stops here.
      await _teardown();
      _setPhase(VoiceControllerPhase.disabled);
      return;
    }

    if (wakeStage) {
      await _ensureRunning();
      if (_engine == null) return;
      await _ensureCapture();
      await _pushPhrases();
      _setPhase(_windowOpen
          ? VoiceControllerPhase.windowOpen
          : VoiceControllerPhase.listening);
      return;
    }

    // Tap to talk: the microphone is closed between taps, and the engine stays
    // warm so the next tap does not pay the model load time again.
    if (!_windowOpen && !_testing) {
      if (_engine != null) await _stopCapture();
      await _pushPhrases();
      _setPhase(VoiceControllerPhase.ready);
    }
  }

  void _setPhase(VoiceControllerPhase phase) {
    if (state.phase == phase) return;
    state = VoiceControllerState(
      phase: phase,
      crashDisabled: state.crashDisabled,
      detail: state.phase == VoiceControllerPhase.noMicrophone
          ? state.detail
          : null,
    );
  }

  Future<bool> _modelsInstalled({required bool withWakeStage}) async {
    final downloader = await _downloader();
    final required = requiredModelsFor(
      language: _config.primaryLanguage,
      withWakeStage: withWakeStage,
    );
    if (required.isEmpty) return false;
    for (final spec in required) {
      if (!await downloader.isInstalled(spec)) return false;
    }
    return true;
  }

  Future<VoiceModelDownloader> _downloader() async {
    final dir = await ref.read(voiceModelsDirProvider.future);
    return VoiceModelDownloader(
      dio: ref.read(appDioProvider),
      directory: dir.path,
    );
  }

  Future<void> _ensureRunning() async {
    if (_engine?.isRunning ?? false) return;
    if (_starting) return;
    _starting = true;
    try {
      final engine = ref.read(voiceEngineFactoryProvider).call();
      _engine = engine;
      await _events?.cancel();
      _events = engine.events.listen(_onEvent);

      if (KVStoreService.isInitialized) {
        await KVStoreService.markVoiceStarting();
        _healthyTimer?.cancel();
        _healthyTimer = Timer(_healthyDuration, () {
          if (KVStoreService.isInitialized) {
            unawaited(KVStoreService.clearVoiceStarting());
          }
        });
      }

      await engine.start(await _params());
      await _ensureCapture();
    } catch (error) {
      await _teardown();
      state = VoiceControllerState(
        phase: VoiceControllerPhase.failed,
        failure: VoiceFailure.engineDied,
        detail: error.toString(),
        crashDisabled: state.crashDisabled,
      );
    } finally {
      _starting = false;
    }
  }

  Future<VoiceEngineParams> _params() async {
    final dir = (await ref.read(voiceModelsDirProvider.future)).path;
    final wakeStage = _config.mode == VoiceMode.wake;
    return VoiceEngineParams(
      language: _config.primaryLanguage,
      mode: _config.mode,
      wakePhrases: _config.activeWakePhrases(),
      commandPhrases: _config.activeCommandPhrases(),
      // The streaming set is English and serves both stages (§3); a language
      // without its own verified model never gets here — the registry has no
      // entry for it and the settings page says "unavailable".
      streamingEncoderPath: modelPathFor(voiceEnStreaming, dir, 'encoder'),
      streamingDecoderPath: modelPathFor(voiceEnStreaming, dir, 'decoder'),
      streamingJoinerPath: modelPathFor(voiceEnStreaming, dir, 'joiner'),
      streamingTokensPath: modelPathFor(voiceEnStreaming, dir, 'tokens'),
      vadModelPath: wakeStage ? modelPathFor(voiceSileroVad, dir, 'vad') : null,
      suppressDispatch: _testing,
    );
  }

  Future<void> _ensureCapture() async {
    if (_capture != null) return;
    late final PcmCapturePort capture;
    try {
      capture = ref.read(voiceCaptureFactoryProvider).call();
    } on UnsupportedError catch (_) {
      state = VoiceControllerState(
        phase: VoiceControllerPhase.noMicrophone,
        detail: 'This platform has no voice microphone implementation.',
        crashDisabled: state.crashDisabled,
      );
      return;
    }
    _capture = capture;
    _micBroken = false;
    _micErrors = capture.chunks.listen(
      (bytes) => _engine?.feedPcm(bytes),
      onError: (Object error, StackTrace stack) {
        // A denied permission and a missing `parec` both land here: the mic is
        // not producing, and the settings page has to say so rather than let
        // the pill sit there hearing nothing.
        _micBroken = true;
        state = VoiceControllerState(
          phase: VoiceControllerPhase.noMicrophone,
          detail: error.toString(),
          crashDisabled: state.crashDisabled,
        );
      },
    );
    try {
      await capture.start();
    } catch (error) {
      // A capture that failed to start must not stay installed: the next
      // _ensureCapture would early-return on the non-null field and the mic
      // would be dead until teardown.
      _capture = null;
      await _micErrors?.cancel();
      _micErrors = null;
      await capture.dispose();
      _micBroken = true;
      state = VoiceControllerState(
        phase: VoiceControllerPhase.noMicrophone,
        detail: error.toString(),
        crashDisabled: state.crashDisabled,
      );
    }
  }

  /// Push the live phrase sets (and language) into a running worker. Called
  /// from [sync] so a settings edit reaches the matcher without an engine
  /// restart; the worker merges them into its params in place.
  Future<void> _pushPhrases() async {
    final engine = _engine;
    if (engine == null || !engine.isRunning) return;
    await engine.updatePhrases(
      wakePhrases: _config.activeWakePhrases(),
      commandPhrases: _config.activeCommandPhrases(),
      language: _config.primaryLanguage,
      suppressDispatch: _testing,
    );
  }

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case VoiceWindowClosedEvent():
        unawaited(_afterWindow());
      case EngineFailedEvent(:final failure):
        unawaited(_teardown());
        state = VoiceControllerState(
          phase: VoiceControllerPhase.failed,
          failure: failure,
          crashDisabled: state.crashDisabled,
        );
      case SilenceSuspectedEvent():
        state = VoiceControllerState(
          phase: VoiceControllerPhase.noMicrophone,
          detail: 'The microphone reports silence — muted, or taken by '
              'another application.',
          crashDisabled: state.crashDisabled,
        );
      case WakeDetectedEvent():
        unawaited(_beforeWindow());
      case CommandHeardEvent():
      case TranscriptTickEvent():
      case EngineStoppedEvent():
        break;
    }
    if (_out != null && !_out!.isClosed) _out!.add(event);
  }

  /// Tap-to-talk: open a window now, and close the microphone again after it.
  Future<void> beginTapWindow() async {
    if (!_config.enabled || _testing) return;
    if (!await _modelsInstalled(withWakeStage: false)) {
      _setPhase(VoiceControllerPhase.missingModels);
      return;
    }
    if (!(_engine?.isRunning ?? false)) {
      await _ensureRunning();
      if (_engine == null || !(_engine?.isRunning ?? false)) return;
    }
    await _ensureCapture();
    if (_capture == null || _micBroken) return;
    await _beforeWindow();
    _windowOpen = true;
    state = VoiceControllerState(
      phase: VoiceControllerPhase.windowOpen,
      crashDisabled: state.crashDisabled,
    );
    await _engine!.beginTapWindow();
  }

  Future<void> endTapWindow() async {
    if (_engine == null) return;
    await _engine!.endCommandWindow();
    await _afterWindow();
  }

  /// Duck for the length of a window so the recognizer hears the speaker and
  /// not the track. Every close path — endpoint, timeout, manual, teardown —
  /// goes through [_afterWindow], so a ducked volume cannot leak.
  Future<void> _beforeWindow() async {
    if (_ducked) return;
    final player = ref.read(audioPlayerPortProvider);
    if (!player.isPlaying) return;
    _ducked = true;
    await player.setVolume(_duckVolume);
  }

  Future<void> _afterWindow() async {
    _windowOpen = false;
    if (_ducked) {
      _ducked = false;
      // Restored before anything dispatches: "louder" must compute against the
      // user's level, not the ducked one (§4).
      await ref
          .read(audioPlayerPortProvider)
          .setVolume(ref.read(volumeProvider));
    }
    await sync();
  }

  Future<void> _stopCapture() async {
    final capture = _capture;
    if (capture == null) return;
    _capture = null;
    await _micErrors?.cancel();
    _micErrors = null;
    await capture.stop();
    await capture.dispose();
  }

  Future<void> _teardown() async {
    _healthyTimer?.cancel();
    _healthyTimer = null;
    await _stopCapture();
    await _events?.cancel();
    _events = null;
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await engine.stop();
      await engine.dispose();
    }
    if (_ducked) {
      _ducked = false;
      // The duck is runtime-only and the persisted level was never touched, so
      // on container disposal there is nothing to restore — and reading another
      // provider from a container that is already gone would throw here.
      if (!_disposing) {
        await ref
            .read(audioPlayerPortProvider)
            .setVolume(ref.read(volumeProvider));
      }
    }
    if (KVStoreService.isInitialized) {
      await KVStoreService.clearVoiceStarting();
    }
  }

  /// Settings phrase test: hear the user speak and show the transcription,
  /// without dispatching — "next" said in the editor must not skip the track.
  Future<void> startPhraseTest({
    List<String>? wakePhrases,
    Map<VoiceCommandId, List<String>>? commandPhrases,
  }) async {
    if (_testing) return;
    _testing = true;
    if (!await _modelsInstalled(withWakeStage: false)) {
      _testing = false;
      _setPhase(VoiceControllerPhase.missingModels);
      return;
    }
    await _ensureRunning();
    if (!(_engine?.isRunning ?? false)) {
      _testing = false;
      return;
    }
    await _engine!.updatePhrases(
      wakePhrases: wakePhrases,
      commandPhrases: commandPhrases,
      suppressDispatch: true,
    );
    await _ensureCapture();
    if (_capture == null || _micBroken) {
      _testing = false;
      return;
    }
    state = VoiceControllerState(
      phase: VoiceControllerPhase.testing,
      crashDisabled: state.crashDisabled,
    );
    await _beforeWindow();
    await _engine!.beginTapWindow();
  }

  Future<void> stopPhraseTest() async {
    if (!_testing) return;
    // Cleared first: the window-close this triggers must not be read as a
    // test session still holding the microphone open.
    _testing = false;
    _windowOpen = false;
    final engine = _engine;
    await engine?.endCommandWindow();
    if (engine != null && engine.isRunning) {
      await engine.updatePhrases(
        wakePhrases: _config.activeWakePhrases(),
        commandPhrases: _config.activeCommandPhrases(),
        suppressDispatch: false,
      );
    }
    await _afterWindow();
  }

  /// Fetches what the current config asks for. The caller owns the progress
  /// display; this only reports whether the models are now in place.
  Future<bool> installModels({
    VoiceProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final downloader = await _downloader();
    final required = requiredModelsFor(
      language: _config.primaryLanguage,
      withWakeStage: _config.mode == VoiceMode.wake,
    );
    if (required.isEmpty) return false;
    for (final spec in required) {
      final outcome = await downloader.install(
        spec,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (outcome != VoiceModelOutcome.ok &&
          outcome != VoiceModelOutcome.alreadyInstalled) {
        return false;
      }
    }
    await sync();
    return true;
  }

  Future<void> deleteModels() async {
    await _teardown();
    final downloader = await _downloader();
    for (final spec in voiceVerifiedModels) {
      await downloader.uninstall(spec);
    }
    _setPhase(
      _config.enabled
          ? VoiceControllerPhase.missingModels
          : VoiceControllerPhase.disabled,
    );
  }

  /// Drop the models a language switch made unused, so re-enabling the other
  /// language later costs nothing and the disk does not keep both.
  Future<void> pruneUnusedModels() async {
    final downloader = await _downloader();
    final keep = requiredModelsFor(
      language: _config.primaryLanguage,
      withWakeStage: _config.mode == VoiceMode.wake,
    );
    for (final spec in voiceVerifiedModels) {
      if (!keep.any((s) => s.id == spec.id)) await downloader.uninstall(spec);
    }
  }
}

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceControllerState>(
  VoiceController.new,
);
