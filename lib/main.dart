import 'dart:async';
import 'dart:ui';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
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
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
import 'package:spotube/modules/theme_background/palette_transition_scope.dart';
import 'package:spotube/modules/theme_background/theme_background_scope.dart';
import 'package:spotube/modules/theme_background/theme_definition_cache.dart';
import 'package:spotube/modules/splash/splash_screen.dart';
import 'package:spotube/modules/splash/splash_prefs.dart';
import 'package:spotube/modules/theme_surfaces/theme_surfaces_scope.dart';
import 'package:spotube/provider/audio_player/audio_player_streams.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/provider/glance/glance.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/bonsoir.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/tray_manager/tray_manager.dart';
import 'package:spotube/provider/lyrics/synced.dart';
import 'package:spotube/l10n/l10n.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/cli/cli.dart';
import 'package:spotube/services/kv_store/encrypted_kv_store.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/connectivity_adapter.dart';
import 'package:spotube/services/wm_tools/wm_tools.dart';
import 'package:spotube/utils/migrations/sandbox.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/perf_counters.dart';
import 'package:spotube/utils/theme_converter.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:yt_dlp_dart/yt_dlp_dart.dart';
import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart';

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
  try {
    await init();
  } catch (e, stack) {
    if (onError != null) {
      await onError(e, stack);
    } else {
      await AppLogger.reportError(e, stack, name);
    }
  }
}

/// Pure startup-gate rule behind the splash poll below: the in-app splash
/// hides as soon as a themed frame can paint, or when [cap] elapses —
/// whichever comes first. Even a total theme failure resolves to the
/// built-in fallback after the cap instead of hanging on black.
bool startupGateAllowsApp({
  required bool themeReady,
  required Duration elapsed,
  Duration cap = const Duration(seconds: 6),
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
Future<void> _initDeferredServices() async {
  await guardedStartupInit('NewPipeExtractor.init', () async {
    if (kIsAndroid || kIsDesktop) {
      await NewPipeExtractor.init();
    }
  });
  await guardedStartupInit('YtDlp.setBinaryLocation', () async {
    if (kIsDesktop) {
      // A bare "yt-dlp" only resolves through the process PATH, which a
      // GUI-launched app keeps short of ~/.local/bin — so resolve an
      // absolute path here and every later call inherits it.
      final binaryPath = KVStoreService.getYoutubeEnginePath(
            YoutubeClientEngine.ytDlp,
          ) ??
          await YtDlpEngine.resolveBinaryPath() ??
          "yt-dlp${kIsWindows ? '.exe' : ''}";
      await YtDlp.instance.setBinaryLocation(binaryPath);
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
}

Future<void> main(List<String> rawArgs) async {
  if (rawArgs.contains("web_view_title_bar")) {
    WidgetsFlutterBinding.ensureInitialized();
    if (runWebViewTitleBarWidget(rawArgs)) {
      return;
    }
  }
  final arguments = await startCLI(rawArgs);
  AppLogger.initialize(arguments["verbose"]);

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

  // Register lyrics providers at startup (idempotent)
  registerLyricsProviders();

  AppLogger.runZoned(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // A failed widget build shows the fallback above instead of a red
    // screen (debug) or a black hole (release splash path).
    ErrorWidget.builder = (details) => const _StartupErrorFallback();

    HttpOverrides.global = BadCertificateAllowlistOverrides();

    // The engine defaults (1000 entries, 100 MB) let a handful of large
    // backdrops push out the small artwork that is on screen constantly, and
    // nothing bounded them before. This sits under the sized decodes, not over
    // them: entries now hold far fewer bytes than they used to.
    PaintingBinding.instance.imageCache
      ..maximumSize = 700
      ..maximumSizeBytes = 64 * 1024 * 1024;

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
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    MediaKit.ensureInitialized();

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

    await KVStoreService.initialize();

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

    final database = AppDatabase();

    if (kIsDesktop) {
      await guardedStartupInit('WindowManagerTools.initialize', () async {
        await WindowManagerTools.initialize();
      });
    }

    if (kIsIOS) {
      HomeWidget.setAppGroupId("group.spotube_home_player_widget");
    }

    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => database),
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
  try {
    return ThemeConverter.toColorScheme(
      colors,
      brightness: brightness,
    );
  } catch (_) {
    return fallback;
  }
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
    final themeDefinition = ref.watch(themeDefinitionProvider);
    final cachedThemeDefinition = ref.watch(cachedThemeDefinitionProvider);
    final router = useMemoized(() => AppRouter(ref), []);
    final hasTouchSupport = useHasTouch();

    // Eagerly initialize background services and keep them alive for the
    // app lifetime. The listener bodies are intentionally empty.
    // onError note (1A.3 audit): `ref.listen` without `onError` rethrows an
    // async provider's error into the zone. These providers have real,
    // expected failure modes (port bind, mDNS, discovery, plugin I/O,
    // update-check network) with no internal try/catch, so route them to
    // the logger with attribution instead of generic zone errors.
    // The two sync providers below (audioPlayerStreamListeners, trayManager)
    // deliberately have NO onError: sync providers never enter an error
    // state, so it would be dead code. (Tray's fire-and-forget
    // `SystemTrayManager.initialize()` is a separate latent issue, out of
    // 1A scope — see tray_manager.dart.)
    void logAsyncError(Object e, StackTrace st) => AppLogger.reportError(e, st);

    ref.listen(audioPlayerStreamListenersProvider, (_, __) {});
    ref.listen(
      bonsoirProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(
      connectClientsProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(
      serverProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(trayManagerProvider, (_, __) {});
    ref.listen(
      metadataPluginsProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(
      metadataPluginProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(
      audioSourcePluginProvider,
      (_, __) {},
      onError: logAsyncError,
    );
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

      // Deferred service inits (moved out of the pre-runApp path):
      // still before any user interaction, but after first paint.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initDeferredServices());
      });

      if (kIsMobile) {
        HomeWidget.registerInteractivityCallback(glanceBackgroundCallback);
      }

      return () {
        /// For enabling hot reload for audio player
        if (!kDebugMode) return;
        audioPlayer.dispose();
        ConnectionCheckerService.instance.dispose();
      };
    }, []);
    // Branded in-app splash: hidden the moment a themed frame is
    // ready (cached theme makes this near-instant on warm starts),
    // with a safety cap so startup never hangs on theme resolution.
    final splashReady = useState(false);
    useEffect(() {
      if (splashReady.value) return null;
      final start = DateTime.now();
      Timer? timer;
      void check() {
        final elapsed = DateTime.now().difference(start);
        final themed = themeDefinition.asData?.value ??
            cachedThemeDefinition.asData?.value;
        if (startupGateAllowsApp(
          themeReady: themed != null,
          elapsed: elapsed,
        )) {
          splashReady.value = true;
        } else {
          timer = Timer(const Duration(milliseconds: 50), check);
        }
      }

      timer = Timer(const Duration(milliseconds: 50), check);
      return () => timer?.cancel();
    }, [themeDefinition, cachedThemeDefinition, splashReady.value]);

    // shadcn's ThemeData has no value equality and `Theme.updateShouldNotify`
    // compares by identity, so a freshly built instance on any rebuild notifies
    // every `Theme.of` consumer in the app. These derivations are memoized on the
    // plugin theme (a freezed value) so a theme only changes when it changed.
    final builtInLightScheme = useMemoized(
      () => colorSchemeMap[accentMaterialColor.name]
              ?.call(ThemeMode.light) ??
          LegacyColorSchemes.lightSlate(),
      [accentMaterialColor.name],
    );

    final builtInDarkScheme = useMemoized(
      () => colorSchemeMap[accentMaterialColor.name]
              ?.call(ThemeMode.dark) ??
          LegacyColorSchemes.darkSlate(),
      [accentMaterialColor.name],
    );

    // Live theme wins; cached theme seeds the first paint instantly
    // and is silently replaced when live resolves. Built-in otherwise.
    final pluginTheme =
        themeDefinition.asData?.value ?? cachedThemeDefinition.asData?.value;

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

    // v2 contract wiring: surfaces carry translucency into ThemeData,
    // ThemeBackgroundScope/ThemeSurfacesScope render background/tint, and
    // AppLayout below renders the geometry tokens (card sizes, gutters).
    // Radius mapping is deliberately lossy: shadcn takes one radius multiplier
    // (default 0.5) for its whole component set, so `medium` scales against its
    // default of 10.0 and small/large/pill only reach the surfaces Spotube
    // draws itself. Density rides the app's size/text scaling, which is what
    // every `* scale` site in the UI already reads.
    final pluginRadius =
        pluginTheme == null ? .5 : pluginTheme.radius.medium / 20;
    final pluginDensity = pluginTheme?.density ?? 1.0;
    // Also fed to `PaletteTransitionScope` below, which must scale the theme it
    // animates exactly like `ShadcnLayer` does (`shadcn_app.dart:637-645`).
    final pluginScaling = useMemoized(
      () => AdaptiveScaling.only(
        sizeScaling: pluginDensity,
        textScaling: pluginDensity,
      ),
      [pluginDensity],
    );
    final pluginTypography = useMemoized(
      () => switch (pluginTheme?.tokens.fontFamily) {
        null => const Typography.geist(),
        // A family the platform cannot resolve falls back per-glyph, so this
        // can only change the typeface, never break rendering.
        final family => const Typography.geist().copyWith(
            sans: () => TextStyle(fontFamily: family),
            base: () => TextStyle(fontSize: 16, fontFamily: family),
          ),
      },
      [pluginTheme?.tokens.fontFamily],
    );

    final appTheme = useMemoized(
      () => ThemeData(
        radius: pluginRadius,
        typography: pluginTypography,
        iconTheme: const IconThemeProperties(),
        colorScheme: lightColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      [pluginTheme, pluginRadius, pluginTypography, lightColorScheme],
    );

    final appDarkTheme = useMemoized(
      () => ThemeData(
        radius: pluginRadius,
        typography: pluginTypography,
        iconTheme: const IconThemeProperties(),
        colorScheme: darkColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      [pluginTheme, pluginRadius, pluginTypography, darkColorScheme],
    );

    final materialBrightness = switch (themeMode) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };

    final materialTheme = useMemoized(
      () => material.ThemeData(
        brightness: materialBrightness,
        splashFactory: material.NoSplash.splashFactory,
        appBarTheme: const material.AppBarTheme(
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      [materialBrightness],
    );

    // `ShadcnLayer` resolves light/dark with the same predicate
    // (`themeMode == dark || (system && platformBrightness == dark)`), which is
    // what `materialBrightness` above already computed, so handing it to the
    // scope cannot make the fade land on a different palette than the one the
    // package would have shown.
    final themeTransitionDuration = useMemoized(
      () => resolveThemeTransition(themeTransition, themeTransitionMs),
      [themeTransition, themeTransitionMs],
    );

    if (!splashReady.value) {
      final prefs = ref.watch(splashPrefsProvider).asData?.value;
      return SplashScreen(
        theme: pluginTheme,
        animation: prefs?.animation ?? SplashAnimation.fade,
        duration: prefs?.duration ?? const Duration(milliseconds: 900),
        useThemedBackground: prefs?.useThemedBackground ?? true,
        logoPath: prefs?.logoPath,
        backgroundPath: prefs?.backgroundPath,
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
      title: 'Spotube',
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
          child: AppLayout(
            tokens: pluginTheme?.tokens ?? const ThemeTokens(),
            radii: pluginTheme?.radius ?? const ThemeRadius(),
            layout: pluginTheme?.layout ?? const ThemeLayout(),
            child: ScrollMotionScope(
              child: ThemeBackgroundScope(
                child: ThemeSurfacesScope(child: child),
              ),
            ),
          ),
        );
      },
      scaling: pluginScaling,
      theme: appTheme,
      darkTheme: appDarkTheme,
      materialTheme: materialTheme,
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
        LogicalKeySet(
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.browse),
        LogicalKeySet(
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        ): HomeTabIntent(router, tab: HomeTabs.search),
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
        CloseAppIntent: CloseAppAction(),
      },
    );
  }
}
