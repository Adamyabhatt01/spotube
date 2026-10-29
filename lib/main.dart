import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:home_widget/home_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:spotube/collections/env.dart';
import 'package:spotube/collections/http-override.dart';
import 'package:spotube/collections/intents.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/hooks/configurators/use_close_behavior.dart';
import 'package:spotube/hooks/configurators/use_deep_linking.dart';
import 'package:spotube/hooks/configurators/use_disable_battery_optimizations.dart';
import 'package:spotube/hooks/configurators/use_fix_window_stretching.dart';
import 'package:spotube/hooks/configurators/use_get_storage_perms.dart';
import 'package:spotube/hooks/configurators/use_has_touch.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/components/scroll_motion_scope.dart';
import 'package:spotube/modules/theme_background/palette_transition_scope.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_background/theme_background_scope.dart';
import 'package:spotube/services/theme_definition_cache.dart';
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
import 'package:spotube/modules/theme_shell/theme_branding.dart';
import 'package:spotube/modules/theme_shell/theme_presentation.dart';
import 'package:spotube/modules/theme_shell/resolved_layout.dart';
import 'package:spotube/modules/splash/splash_screen.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/modules/theme_ui/theme_ui_fonts.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/modules/splash/splash_prefs.dart';
import 'package:spotube/modules/theme_surfaces/theme_surfaces_scope.dart';
import 'package:spotube/provider/audio_player/audio_effects.dart';
import 'package:spotube/provider/audio_player/audio_player_streams.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/glance/glance.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/server/control_server_provider.dart';
import 'package:spotube/provider/server/control_command_delivery.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/bonsoir.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/tray_manager/tray_manager.dart';
import 'package:spotube/provider/radio/stations.dart';
import 'package:spotube/l10n/l10n.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';
import 'package:spotube/services/cli/cli.dart';
import 'package:spotube/services/control/mcp_server.dart';
import 'package:spotube/services/kv_store/encrypted_kv_store.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/memory/device_memory_profile.dart';
import 'package:spotube/services/memory/memory_budget.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/vpn/nmcli_backend.dart';
import 'package:spotube/services/wm_tools/wm_tools.dart';
import 'package:spotube/utils/migrations/sandbox.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/utils/built_in_theme_colors.dart';
import 'package:spotube/utils/theme_converter.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_process.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:yt_dlp_dart/yt_dlp_dart.dart';

/// Runs an optional startup step without ever failing startup.
///
/// Failures are reported (with [name] attribution, or via [onError] in
/// tests) and swallowed: an unavailable yt-dlp binary, Discord RPC or
/// notifier must degrade features, never prevent launch.
Future<void> guardedStartupInit(
  String name,
  Future<void> Function() init, {
  Future<void> Function(Object error, StackTrace stackTrace)? onError,
}) async {
  // Which step actually costs what, for the startup harness below. One
  // stopwatch per step is negligible (~10 steps/start) and the lines land
  // in the release log file too, so slow launches on user devices without
  // adb can still be attributed from Settings > Logs.
  final sw = Stopwatch()..start();
  try {
    await init();
  } catch (e, stack) {
    if (onError != null) {
      await onError(e, stack);
    } else {
      await AppLogger.reportError(e, stack, name);
    }
  } finally {
    _startupLog('[startup] step $name: ${sw.elapsedMilliseconds}ms');
  }
}

/// Pure startup-gate rule behind the splash poll below: the in-app splash
/// hides as soon as a themed frame can paint, or when [cap] elapses —
/// whichever comes first. Even a total theme failure resolves to the
/// built-in fallback after the cap instead of hanging on black.
///
/// The cap used to be 6 s, which is what a user without a themed plugin (or
/// with a plugin whose theme lookup failed) saw on every cold start. A
/// settled theme provider is enough to paint: `themeDefinition` resolving to
/// null is a valid answer, not something to wait out.
const startupSplashGateCap = Duration(seconds: 2);

bool startupGateAllowsApp({
  required bool themeReady,
  required Duration elapsed,
  Duration cap = startupSplashGateCap,
}) {
  return themeReady || elapsed >= cap;
}

/// Fallback painted when a widget subtree throws during build. Plain
/// widgets only (no providers/themes): the error may itself come from a
/// broken theme or provider, so this must never depend on either.
class _StartupErrorFallback extends StatelessWidget {
  const _StartupErrorFallback();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text(
            'Something went wrong starting this view.\nPlease restart the app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
  }
}

/// Deferred service initializations that must not block the first frame.
///
/// Runs once, right after first paint (still before any user interaction
/// can reach playback/notifications). Keeps process-start → first-frame
/// minimal so the pre-splash black window stays short.
Future<void> _initDeferredServices(WidgetRef ref) async {
  // Captured up front: this function awaits several seconds of work, and a
  // `ref` read at the end of it could outlive the element that handed it over.
  final preferences = ref.read(userPreferencesProvider.notifier);
  // NewPipe initializes lazily on first engine use (single-flight in
  // `NewPipeEngine._ensureInitialized`), not here: every start paid
  // `NewPipe.init(DownloaderImpl.init(OkHttpClient()))` whether or not any
  // NewPipe call followed. The engine tests inject a no-op init for the
  // same reason the search path is injectable (no platform channel there).
  await guardedStartupInit('YtDlp.setBinaryLocation', () async {
    if (kIsDesktop) {
      // A bare "yt-dlp" only resolves through the process PATH, which a
      // GUI-launched app keeps short of ~/.local/bin — so resolve an
      // absolute path here and every later call inherits it. A stored
      // custom path that no longer exists must not win: it would
      // short-circuit resolution and leave the binary unset for the
      // whole session.
      final storedPath = KVStoreService.getYoutubeEnginePath(
        YoutubeClientEngine.ytDlp,
      );
      final customPath = storedPath != null && await File(storedPath).exists()
          ? storedPath
          : null;
      final binaryPath = customPath ??
          await YtDlpEngine.resolveBinaryPath() ??
          "yt-dlp${kIsWindows ? '.exe' : ''}";
      await YtDlp.instance.setBinaryLocation(binaryPath);
      // R-11: the package spawns its binary with `Process.run`, which hands
      // back no handle, so an engine call that missed its budget was abandoned
      // while yt-dlp kept running. Swap in the killable process layer now that
      // there is a binary for it to point at.
      YtDlpProcess.install();
    }
  });
  await guardedStartupInit('FlutterDiscordRPC.initialize', () async {
    if (kIsDesktop) {
      await FlutterDiscordRPC.initialize(Env.discordAppId);
    }
  });
  await guardedStartupInit('localNotifier.setup', () async {
    if (kIsDesktop) {
      await localNotifier.setup(appName: "Spotube");
    }
  });
  await guardedStartupInit('tz.initializeTimeZones', () async {
    // No host code reads tz data (only the plugin API enum names it); the
    // ~500KB parse has no business on the pre-frame path.
    tz.initializeTimeZones();
  });
  await guardedStartupInit('MetadataGod.initialize', () async {
    // Only local-library scans and metadata writes touch the bridge, all
    // post-startup. Initializing with first paint instead of before it.
    if (!kIsWeb) {
      MetadataGod.initialize();
    }
  });
  await guardedStartupInit('Vpn.probe', () async {
    // Read-only readiness check: no connection is touched, no state is
    // changed. A missing backend only matters when the user opts in —
    // the first gated operation then fails closed with an explicit error.
    if (kIsLinux) {
      final nmcli = await RealNmcliBackend().resolveNmcliPath();
      if (nmcli == null) {
        AppLogger.log.w('Vpn automation unavailable (no nmcli on PATH)');
      } else {
        AppLogger.log.i('Vpn backend ready (nmcli at $nmcli)');
      }
    }
  });
  await guardedStartupInit('MusicCache.sweepStaleMirrors', () async {
    // A `.part` is only ever finished by the process that opened it, so the
    // ones still on disk at startup are all leftovers from a killed mirror.
    // Bounded by [staleMirrorWindow] in case a second instance is mid-write.
    if (kIsWeb) return;
    await preferences.sweepStaleMusicCacheMirrors();
  });
  _logStartupPhase('deferred services complete');
}

/// Startup harness: the wall-clock timeline from `main()` to an interactive
/// window. Phase lines go through `AppLogger.logStartupLine`, so they land
/// in the release log file too (Settings > Logs) and a slow launch on a
/// device without adb can still be attributed. The roadmap requires a
/// before/after number per startup change, and none of these phases had an
/// observable endpoint before this.
///
/// `SPOTUBE_STARTUP_LOG=<path>` additionally mirrors each line to a file in
/// debug/profile runs, because a run cut short by a signal loses whatever
/// the logger still has buffered on stdout.
final _startupClock = Stopwatch();
final _startupLogPath =
    kIsWeb || kReleaseMode ? null : Platform.environment['SPOTUBE_STARTUP_LOG'];

void _startupLog(String line) {
  AppLogger.logStartupLine(line);
  final path = _startupLogPath;
  if (path != null) {
    File(path).writeAsStringSync(
      '$line\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

void _logStartupPhase(String phase) {
  if (!_startupClock.isRunning) _startupClock.start();
  _startupLog('[startup] $phase: ${_startupClock.elapsedMilliseconds}ms');
}

Future<void> main(List<String> rawArgs) async {
  if (rawArgs.contains("web_view_title_bar")) {
    WidgetsFlutterBinding.ensureInitialized();
    if (runWebViewTitleBarWidget(rawArgs)) {
      return;
    }
  }
  final invocation = await startCLI(rawArgs);
  final arguments = invocation.arguments;
  AppLogger.initialize(arguments["verbose"]);
  // Startup harness reference point. Everything before it (engine bootstrap,
  // plugin registration, CLI parsing) is not code these phases can change.
  _logStartupPhase('main');

  // A control command drives an ALREADY-RUNNING instance rather than
  // starting a second one. If no instance is reachable, this process
  // becomes the instance and answers the command itself once the UI is up
  // — so `spotube --play "x"` works whether or not the app is running.
  final controlRequest = invocation.controlRequest;
  if (controlRequest != null && controlRequest.command == 'mcp.serve') {
    // The MCP server is a separate process that drives the running app over
    // the local control channel. It never hosts the app itself, so it costs
    // the running instance nothing.
    await runSpotubeMcpServer();
    return;
  }
  if (controlRequest != null) {
    final delivered = await sendControlCommand(controlRequest);
    if (delivered) {
      // The running instance answered: this process has nothing left to do.
      exit(0);
    }
    // No instance was reachable. Fall through: this process becomes the
    // instance, and the command is answered below once the providers are
    // up. The UI is still shown, so the user sees what happened.
  }

  // Opt-in perf counter dump for a debug/profile run: set
  // SPOTUBE_PERF_COUNTERS to an ISO duration (e.g. 00:00:10) and the counters
  // are logged on that interval. Absent variable or release build => no timer,
  // and every counter call site is a no-op anyway (kPerfCountersEnabled).
  if (!kIsWeb &&
      !kReleaseMode &&
      Platform.environment.containsKey('SPOTUBE_PERF_COUNTERS')) {
    final interval = Duration(
      seconds:
          int.tryParse(Platform.environment['SPOTUBE_PERF_COUNTERS']!) ?? 10,
    );
    PerfCounters.startDumpTimer(interval: interval, log: AppLogger.log.t);
  }

  AppLogger.runZoned(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    _logStartupPhase('binding');

    // A failed widget build shows the fallback above instead of a red
    // screen (debug) or a black hole (release splash path).
    ErrorWidget.builder = (details) => const _StartupErrorFallback();

    // Framework build/layout/paint errors never reach the zone's
    // PlatformDispatcher handler (that only sees uncaught async errors), so
    // without this the album/playlist crash fallback is all the user sees and
    // Settings > Logs has no stack trace. Keep the debug console output too.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        AppLogger.reportError(
          details.exception,
          details.stack,
          details.context?.toDescription() ?? 'FlutterError',
        ),
      );
    };

    // Cover the window before any of the pre-frame work below. The native
    // splash used to be preserved after the image-cache setup, which is
    // small but needless uncovered time on a cold Android start.
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    HttpOverrides.global = BadCertificateAllowlistOverrides();

    // The engine defaults (1000 entries, 100 MB) let a handful of large
    // backdrops push out the small artwork that is on screen constantly, and
    // nothing bounded them before. This sits under the sized decodes, not over
    // them: entries now hold far fewer bytes than they used to.
    //
    // The byte budget is device-aware: a 64 MB image cache is a large share
    // of an old phone's per-app heap and a rounding error on a desktop, so
    // the cap follows what the platform says the app may keep. The probe is
    // synchronous for the Linux/Android path (a /proc read) and falls back to
    // a fixed value where the platform publishes nothing.
    //
    // Start the shared-preferences load first so its platform channel call
    // overlaps the probe instead of adding to it. Both are independent and
    // must finish before runApp (the DB and the first theme read need
    // preferences; the image cache needs the probe).
    final kvStoreInit = KVStoreService.initialize();
    final memoryProfile = await DeviceMemoryProbe().resolve();
    MemoryBudget.install(memoryProfile);
    PaintingBinding.instance.imageCache
      ..maximumSize = 700
      ..maximumSizeBytes = memoryProfile.imageCacheBudgetBytes;
    _logStartupPhase('memoryProfile');

    // Timezone data moved to _initDeferredServices (post-paint): nothing on
    // the pre-frame path consumes it.
    // Kept pre-frame on purpose, with reasons:
    // - MediaKit: the queue-restore provider build can reach the backend on
    //   first frame (syncSavedState is fire-and-forget at build).
    // - EncryptedKvStore: the first DB read (first frame) decrypts through
    //   encryptionKeySync, which throws on a null key.
    // - migrateMacOs: must precede AppDatabase construction (already
    //   fast-paths when there is nothing to migrate).
    // - MetadataGod: only local scans/metadata writes use it (post-startup),
    //   initialized post-paint in _initDeferredServices.
    MediaKit.ensureInitialized();
    _logStartupPhase('mediaKit');

    await migrateMacOsFromSandboxToNoSandbox();

    // force High Refresh Rate on some Android devices (like One Plus).
    // Fire-and-forget: the mode applies whenever the platform gets to it;
    // nothing frames on it.
    if (kIsAndroid) {
      unawaited(guardedStartupInit(
        'FlutterDisplayMode.setHighRefreshRate',
        () => FlutterDisplayMode.setHighRefreshRate(),
      ));
    }

    await kvStoreInit;
    _logStartupPhase('kvStore');

    // Best-effort desktop integrations: failures degrade the feature
    // (tray/close-behavior/media keys), never abort launch — and none of
    // them block first frame either.
    if (kIsDesktop) {
      unawaited(guardedStartupInit('windowManager.setPreventClose', () async {
        await windowManager.setPreventClose(true);
      }));
    }

    if (kIsWindows) {
      unawaited(guardedStartupInit('SMTCWindows.initialize', () async {
        await SMTCWindows.initialize();
      }));
    }

    try {
      await EncryptedKvStoreService.initialize();
    } catch (e, stack) {
      await AppLogger.reportError(
          e, stack, 'EncryptedKvStoreService.initialize');
    }
    _logStartupPhase('secureStore');

    final database = AppDatabase();
    _logStartupPhase('database');

    if (kIsDesktop) {
      // ~28 ms of the pre-runApp path (measured): it only registers the
      // window-manager plugin, and every tray/window call happens after the
      // first frame, by which time it is long done.
      unawaited(guardedStartupInit('WindowManagerTools.initialize', () async {
        await WindowManagerTools.initialize();
      }));
    }

    if (kIsIOS) {
      HomeWidget.setAppGroupId("group.spotube_home_player_widget");
    }

    _logStartupPhase('pre-runApp');

    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => database),
          if (controlRequest != null)
            pendingControlRequestProvider.overrideWithValue(controlRequest),
        ],
        observers: const [
          AppLoggerProviderObserver(),
        ],
        child: const Spotube(),
      ),
    );
  });
}

ColorScheme _resolveColorScheme(
  ThemeColors colors, {
  required Brightness brightness,
  required ColorScheme fallback,
}) {
  // Every role is resolved on its own now, so this cannot fail: a role the
  // theme did not send, or sent unreadably, falls back to the built-in
  // palette instead of taking the whole theme down with it.
  return ThemeConverter.toColorScheme(
    colors,
    brightness: brightness,
    fallback: fallback,
  );
}

class Spotube extends HookConsumerWidget {
  const Spotube({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final themeMode =
        ref.watch(userPreferencesProvider.select((s) => s.themeMode));
    final locale = ref.watch(userPreferencesProvider.select((s) => s.locale));
    final accentMaterialColor =
        ref.watch(userPreferencesProvider.select((s) => s.accentColorScheme));
    final themeTransition = ref.watch(
      userPreferencesProvider.select((s) => s.themeTransition),
    );
    final themeTransitionMs = ref.watch(
      userPreferencesProvider.select((s) => s.themeTransitionMs),
    );
    final userPlayerDock =
        ref.watch(userPreferencesProvider.select((s) => s.playerDock));
    final themeDefinition = ref.watch(themeDefinitionProvider);
    final cachedThemeDefinition = ref.watch(cachedThemeDefinitionProvider);

    final router = useMemoized(() => AppRouter(ref), []);
    final hasTouchSupport = useHasTouch();

    // Live theme wins; cached theme seeds the first paint instantly
    // and is silently replaced when live resolves. Built-in otherwise.
    final pluginTheme =
        themeDefinition.asData?.value ?? cachedThemeDefinition.asData?.value;

    // A resolved `null` (no theme plugin configured, or the plugin answered
    // without one) is a valid first-paint answer. Waiting for `pluginTheme !=
    // null` instead kept the splash up until the 6 s cap on every cold start
    // for those users — the actual "app takes seconds to open" symptom.
    final themeResolutionSettled =
        !themeDefinition.isLoading && !cachedThemeDefinition.isLoading;

    // Branded in-app splash: hidden the moment a themed frame is ready, with a
    // safety cap so startup never hangs on theme resolution.
    //
    // The gate is evaluated in `build` rather than by a poll: both theme
    // providers above are watched, so the rebuild that carries a resolved theme
    // re-runs this check in that same frame. Polling on a 50ms timer only added
    // up to one interval of latency between "a theme exists" and "the app is
    // visible" on every start. The timer is kept for the cap alone — with no
    // theme arriving there is no rebuild to trigger, and the cap has to fire on
    // a clock instead.
    final gateStart = useMemoized(() => Stopwatch()..start(), []);
    final splashCapTick = useState(0);
    useEffect(() {
      final timer = Timer(
        startupSplashGateCap,
        () => splashCapTick.value++,
      );
      return timer.cancel;
    }, [splashCapTick.value]);
    final splashReady = startupGateAllowsApp(
      themeReady: pluginTheme != null || themeResolutionSettled,
      elapsed: gateStart.elapsed,
    );
    useEffect(() {
      if (!splashReady) return null;
      _logStartupPhase(
        'splashReady (themed=${pluginTheme != null}, gate=${gateStart.elapsedMilliseconds}ms)',
      );
      return null;
    }, [splashReady]);

    // Eagerly initialize background services and keep them alive for the app
    // lifetime. The listener bodies are intentionally empty.
    //
    // R-02: these are subscribed from a post-frame effect behind the splash
    // gate instead of inline in `build`. None of them can be observed while the
    // splash still covers the window — no playback request, device pick, tray
    // click or plugin-backed screen exists before the first themed frame — and
    // registering them in `build` put their provider construction inside the
    // frame that produces that content, competing with the heaviest build the
    // app does. `listenManual` is the documented way to subscribe outside
    // `build`; the subscriptions stay attached for the widget's life.
    // onError note (1A.3 audit): listening without `onError` rethrows an async
    // provider's error into the zone. These providers have real, expected
    // failure modes (port bind, mDNS, discovery, plugin I/O, update-check
    // network) with no internal try/catch, so route them to the logger with
    // attribution instead of generic zone errors. The two sync providers
    // (audioPlayerStreamListeners, trayManager) deliberately have NO onError:
    // sync providers never enter an error state, so it would be dead code.
    // (Tray's fire-and-forget `SystemTrayManager.initialize()` is a separate
    // latent issue, out of 1A scope — see tray_manager.dart.)
    useEffect(() {
      if (!splashReady) return null;
      void logAsyncError(Object e, StackTrace st) =>
          AppLogger.reportError(e, st);

      // A control command this process was started to deliver (the CLI was
      // asked to drive an instance and none was running). Answered once the
      // app is up, through the same handler the control channel uses.
      final pendingRequest = ref.read(pendingControlRequestProvider);
      if (pendingRequest != null) {
        unawaited(deliverPendingControlRequest(ref, pendingRequest));
      }

      final subscriptions = [
        ref.listenManual(audioPlayerStreamListenersProvider, (_, __) {}),
        ref.listenManual(
          bonsoirProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        ref.listenManual(
          connectClientsProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        ref.listenManual(
          serverProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        ref.listenManual(trayManagerProvider, (_, __) {}),
        ref.listenManual(
          metadataPluginsProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        ref.listenManual(
          metadataPluginProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        ref.listenManual(
          audioSourcePluginProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
        // Keeps the internet-radio directory registry pointed at the
        // installed radio plugins for the app's lifetime. Subscribed here
        // (behind the splash gate) instead of inline in build: it reads the
        // installed-plugin list and registers directory providers, none of
        // which can be observed before the app is visible.
        ref.listenManual(radioPluginDirectorySyncProvider, (_, __) {}),
        // The local control channel: a second `spotube --play ...` finds this
        // instance through it, and the MCP server drives the same endpoint.
        // Local only (Unix socket/loopback), and it needs the player and the
        // metadata plugin, so it belongs on the post-splash path too.
        ref.listenManual(
          controlServerProvider,
          (_, __) {},
          onError: logAsyncError,
        ),
      ];
      return () {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      };
    }, [splashReady]);
    // The two plugin update checks are deliberately not started here: they are
    // network calls that each can pull a plugin VM online, and a root-widget
    // listener began them before the first frame. useGlobalSubscriptions runs
    // them once the app has been idle for a few seconds, and Settings >
    // Plugins watches the same (keepAlive) providers.
    // Retains the active + next-up sourced-track manifests for the app
    // lifetime (see sourcedTrackRetentionProvider); rebuilds only on
    // queue structural changes.
    ref.watch(sourcedTrackRetentionProvider);

    useFixWindowStretching();
    useDisableBatteryOptimizations();
    useDeepLinking(ref, router);
    useCloseBehavior(ref);
    useGetStoragePermissions(ref);

    useEffect(() {
      // First frame is already themed via the cached theme (whenever
      // one exists), so the splash leaves immediately instead of
      // holding a black window while live resolution runs behind it.
      FlutterNativeSplash.remove();
      _logStartupPhase('firstFrame');

      // Deferred service inits (moved out of the pre-runApp path):
      // still before any user interaction, but after first paint.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initDeferredServices(ref));
      });

      if (kIsMobile) {
        HomeWidget.registerInteractivityCallback(glanceBackgroundCallback);
      }

      final player = ref.read(audioPlayerPortProvider);
      // Applies the persisted equalizer/normalization chain to the music
      // player and keeps it in sync for the app's lifetime.
      ref.read(audioEffectsProvider);

      return () {
        /// For enabling hot reload for audio player
        if (!kDebugMode) return;
        player.dispose();
        ConnectionCheckerService.instance.dispose();
      };
    }, []);

    // shadcn's ThemeData has no value equality and `Theme.updateShouldNotify`
    // compares by identity, so a freshly built instance on any rebuild notifies
    // every `Theme.of` consumer in the app. These derivations are memoized on the
    // plugin theme (a freezed value) so a theme only changes when it changed.
    final builtInLightScheme = useMemoized(
      () =>
          colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.light) ??
          LegacyColorSchemes.lightSlate(),
      [accentMaterialColor.name],
    );

    final builtInDarkScheme = useMemoized(
      () =>
          colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.dark) ??
          LegacyColorSchemes.darkSlate(),
      [accentMaterialColor.name],
    );

    final lightColorScheme = useMemoized(
      () => pluginTheme == null
          ? builtInLightScheme
          : _resolveColorScheme(
              pluginTheme.light,
              brightness: Brightness.light,
              fallback: builtInLightScheme,
            ),
      [pluginTheme, builtInLightScheme],
    );

    final darkColorScheme = useMemoized(
      () => pluginTheme == null
          ? builtInDarkScheme
          : _resolveColorScheme(
              pluginTheme.dark,
              brightness: Brightness.dark,
              fallback: builtInDarkScheme,
            ),
      [pluginTheme, builtInDarkScheme],
    );

    // The status colours and the sixth chart colour: shadcn's ColorScheme
    // has no slot for them, so they are resolved here and published beside
    // it through AppLayout.
    final lightSemanticColors = useMemoized(
      () => pluginTheme == null
          ? builtInLightSemanticColors
          : ThemeConverter.toSemanticColors(
              pluginTheme.light,
              fallback: builtInLightSemanticColors,
            ),
      [pluginTheme],
    );

    final darkSemanticColors = useMemoized(
      () => pluginTheme == null
          ? builtInDarkSemanticColors
          : ThemeConverter.toSemanticColors(
              pluginTheme.dark,
              fallback: builtInDarkSemanticColors,
            ),
      [pluginTheme],
    );

    // v2 contract wiring: surfaces carry translucency into ThemeData,
    // ThemeBackgroundScope/ThemeSurfacesScope render background/tint, and
    // AppLayout below renders the geometry tokens (card sizes, gutters).
    // Radius mapping is deliberately lossy: shadcn takes one radius multiplier
    // (default 0.5) for its whole component set, so `medium` scales against its
    // default of 10.0 and small/large/pill only reach the surfaces Spotube
    // draws itself. Density rides the app's size/text scaling, which is what
    // every `* scale` site in the UI already reads.
    final pluginDensity = pluginTheme?.density ?? 1.0;
    // The v3 presentation blocks are resolved per palette because a style may
    // name a colour role; the two presentations differ only in those colours.
    final lightPresentation = useMemoized(
      () => resolveThemePresentation(pluginTheme, scheme: lightColorScheme),
      [pluginTheme, lightColorScheme],
    );
    final darkPresentation = useMemoized(
      () => resolveThemePresentation(pluginTheme, scheme: darkColorScheme),
      [pluginTheme, darkColorScheme],
    );
    final pluginRadius =
        (pluginTheme?.radius.medium ?? 10) / 20 * lightPresentation.radiusScale;
    // Also fed to `PaletteTransitionScope` below, which must scale the theme it
    // animates exactly like `ShadcnLayer` does (`shadcn_app.dart:637-645`).
    final pluginScaling = useMemoized(
      () => AdaptiveScaling.only(
        sizeScaling: pluginDensity * lightPresentation.sizeScale,
        textScaling: pluginDensity * lightPresentation.textScale,
      ),
      [pluginDensity, lightPresentation],
    );

    final appTheme = useMemoized(
      () => ThemeData(
        radius: pluginRadius,
        typography: lightPresentation.typography,
        iconTheme: lightPresentation.iconTheme,
        colorScheme: lightColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      [pluginTheme, pluginRadius, lightPresentation, lightColorScheme],
    );

    final appDarkTheme = useMemoized(
      () => ThemeData(
        radius: pluginRadius,
        typography: darkPresentation.typography,
        iconTheme: darkPresentation.iconTheme,
        colorScheme: darkColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      [pluginTheme, pluginRadius, darkPresentation, darkColorScheme],
    );

    final materialBrightness = switch (themeMode) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };

    final materialScheme = materialBrightness == Brightness.dark
        ? darkColorScheme
        : lightColorScheme;
    final materialPresentation = materialBrightness == Brightness.dark
        ? darkPresentation
        : lightPresentation;

    // The kit bridges derive Material and Cupertino from the same palette and
    // type ladder the shadcn theme uses, instead of the package's seed-colour
    // fallback. A node that asks for `kit: "material"` therefore still paints
    // in the active theme.
    final materialTheme = useMemoized(
      () => buildMaterialKitTheme(
        scheme: materialScheme,
        typography: materialPresentation.typography,
        brightness: materialBrightness,
      ),
      [materialScheme, materialPresentation, materialBrightness],
    );

    final cupertinoTheme = useMemoized(
      () => buildCupertinoKitTheme(
        scheme: materialScheme,
        typography: materialPresentation.typography,
        brightness: materialBrightness,
      ),
      [materialScheme, materialPresentation, materialBrightness],
    );

    final themeAssets = ref.watch(themeUiAssetsProvider).asData?.value;
    // Theme fonts are registered through a FontLoader, which is asynchronous
    // and does not invalidate text layout by itself. Watching here rebuilds
    // the shell once the faces are ready: shadcn measures navigation labels
    // with `IntrinsicWidth`, so a label measured against the fallback face and
    // then painted with Inter is clipped on both edges.
    ref.watch(themeUiFontsProvider);
    final branding = ThemeBranding.from(pluginTheme);
    final appTitle = branding.windowTitle;
    // One resolved layout for every consumer: splash, shell and pages all see
    // the same breakpoint variant, footer dock and volume decision.
    final resolvedLayout = resolveLayout(
      pluginTheme?.layout ?? const ThemeLayout(),
      width: MediaQuery.sizeOf(context).width,
      userDock: userPlayerDock,
    );
    final themeLayout = resolvedLayout.layout;
    final splashSpec = themeLayout.splash;
    final rawSplashLogo = splashSpec['logo'];
    final themeSplashLogo = rawSplashLogo is String
        ? themeAssets?.resolve(rawSplashLogo)
        : themeAssets?.resolve(branding.logoAsset);
    final rawSplashText = splashSpec['text'];
    final splashText = rawSplashText is String &&
            rawSplashText.trim().isNotEmpty &&
            rawSplashText.trim().length <= 40
        ? rawSplashText.trim()
        : null;

    // The GTK shell starts with its own "spotube" title; MaterialApp's title
    // only reaches the task switcher. Set the actual window title too so a
    // theme's `branding.windowTitle` is visible in the compositor.
    useEffect(() {
      if (kIsDesktop) {
        // MaterialApp's own Title updates the platform title during build;
        // call after that frame so the theme's title wins the race.
        unawaited(() async {
          // The first frame can be produced before the Wayland surface is
          // mapped; a title set before that point never reaches the
          // compositor. Wait until the frame is actually on screen.
          await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
          await windowManager.setTitle(appTitle);
        }());
      }
      return null;
    }, [appTitle]);

    // `ShadcnLayer` resolves light/dark with the same predicate
    // (`themeMode == dark || (system && platformBrightness == dark)`), which is
    // what `materialBrightness` above already computed, so handing it to the
    // scope cannot make the fade land on a different palette than the one the
    // package would have shown.
    final themeTransitionDuration = useMemoized(
      () => resolveThemeTransition(themeTransition, themeTransitionMs),
      [themeTransition, themeTransitionMs],
    );

    if (!splashReady) {
      final prefs = ref.watch(splashPrefsProvider).asData?.value;
      return SplashScreen(
        theme: pluginTheme,
        animation: prefs?.animation ?? SplashAnimation.fade,
        duration: prefs?.duration ?? const Duration(milliseconds: 900),
        useThemedBackground: prefs?.useThemedBackground ?? true,
        logoPath: prefs?.logoPath ?? themeSplashLogo?.path,
        backgroundPath: prefs?.backgroundPath,
        brandText: splashText,
      );
    }

    return ShadcnApp.router(
      supportedLocales: L10n.all,
      locale: locale.languageCode == "system" ? null : locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router.config(),
      debugShowCheckedModeBanner: false,
      title: appTitle,
      builder: (context, child) {
        child = ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: hasTouchSupport
                ? {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                  }
                : null,
          ),
          child: child!,
        );

        if (kIsLinux) {
          child = DragToResizeArea(
            resizeEdgeSize: 2.5,
            child: child,
          );
        }

        return PaletteTransitionScope(
          theme: appTheme,
          darkTheme: appDarkTheme,
          scaling: pluginScaling,
          brightness: materialBrightness,
          duration: themeTransitionDuration,
          // The scope itself stays provider-free (frame-exact clock); the
          // one watch lives here with the other preference watches.
          realTransparent: ref.watch(realTransparencyActiveProvider),
          child: AppLayout(
            tokens: pluginTheme?.tokens ?? const ThemeTokens(),
            radii: pluginTheme == null
                ? const ThemeRadius()
                : pluginTheme.radius.copyWith(
                    small: pluginTheme.radius.small *
                        lightPresentation.radiusScale,
                    medium: pluginTheme.radius.medium *
                        lightPresentation.radiusScale,
                    large: pluginTheme.radius.large *
                        lightPresentation.radiusScale,
                    pill:
                        pluginTheme.radius.pill * lightPresentation.radiusScale,
                  ),
            spacing: lightPresentation.spacing,
            motion: lightPresentation.motion,
            spacingScale: lightPresentation.spacingScale,
            // Breakpoint variants are resolved at the window width, so a
            // theme's `responsive` override reaches every consumer through
            // the same `context.layout` the base layout uses.
            layout: resolvedLayout.layout,
            playerDock: resolvedLayout.playerDock,
            volumeOverride: resolvedLayout.volumeOverride,
            semanticColors: materialBrightness == Brightness.dark
                ? darkSemanticColors
                : lightSemanticColors,
            child: ThemeUiRuntimeScopeHost(
              child: ScrollMotionScope(
                child: ThemeBackgroundScope(
                  child: ThemeSurfacesScope(child: child),
                ),
              ),
            ),
          ),
        );
      },
      scaling: pluginScaling,
      theme: appTheme,
      darkTheme: appDarkTheme,
      materialTheme: materialTheme,
      cupertinoTheme: cupertinoTheme,
      themeMode: themeMode,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts.map((key, value) {
          return MapEntry(
            LogicalKeySet.fromSet(key.triggers?.toSet() ?? {}),
            value,
          );
        }),
        LogicalKeySet(LogicalKeyboardKey.space): PlayPauseIntent(ref),
        LogicalKeySet(LogicalKeyboardKey.comma, LogicalKeyboardKey.control):
            NavigationIntent(router, "/settings"),
        // Cmd on macOS, Ctrl everywhere else; both are registered so a
        // theme's own sidebar chrome works the same on every desktop.
        LogicalKeySet(LogicalKeyboardKey.keyB, LogicalKeyboardKey.control):
            ToggleSidebarIntent(ref),
        LogicalKeySet(LogicalKeyboardKey.keyB, LogicalKeyboardKey.meta):
            ToggleSidebarIntent(ref),
        LogicalKeySet(
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): ToggleAsideIntent(ref),
        LogicalKeySet(
          LogicalKeyboardKey.keyB,
          LogicalKeyboardKey.meta,
          LogicalKeyboardKey.shift,
        ): ToggleAsideIntent(ref),
        LogicalKeySet(
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.browse),
        LogicalKeySet(
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.search, ref: ref),
        LogicalKeySet(
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.lyrics),
        LogicalKeySet(
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.userPlaylists),
        LogicalKeySet(
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.userArtists),
        LogicalKeySet(
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.userAlbums),
        LogicalKeySet(
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.userLocalLibrary),
        LogicalKeySet(
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.userDownloads),
        LogicalKeySet(
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): CloseAppIntent(),
      },
      actions: {
        ...WidgetsApp.defaultActions,
        PlayPauseIntent: PlayPauseAction(),
        NavigationIntent: NavigationAction(),
        HomeTabIntent: HomeTabAction(),
        ToggleSidebarIntent: ToggleSidebarAction(),
        ToggleAsideIntent: ToggleAsideAction(),
        CloseAppIntent: CloseAppAction(),
      },
    );
  }
}
