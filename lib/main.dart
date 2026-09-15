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
import 'package:spotube/modules/settings/color_scheme_picker_dialog.dart';
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
import 'package:spotube/provider/metadata_plugin/updater/update_checker.dart';
import 'package:spotube/provider/server/bonsoir.dart';
import 'package:spotube/provider/server/server.dart';
import 'package:spotube/provider/tray_manager/tray_manager.dart';
import 'package:spotube/l10n/l10n.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/cli/cli.dart';
import 'package:spotube/services/kv_store/encrypted_kv_store.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/wm_tools/wm_tools.dart';
import 'package:spotube/utils/migrations/sandbox.dart';
import 'package:spotube/utils/platform.dart';
import 'package:spotube/utils/theme_converter.dart';
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
      await YtDlp.instance.setBinaryLocation(
        KVStoreService.getYoutubeEnginePath(YoutubeClientEngine.ytDlp) ??
            "yt-dlp${kIsWindows ? '.exe' : ''}",
      );
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

  AppLogger.runZoned(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    // A failed widget build shows the fallback above instead of a red
    // screen (debug) or a black hole (release splash path).
    ErrorWidget.builder = (details) => const _StartupErrorFallback();

    HttpOverrides.global = BadCertificateAllowlistOverrides();

    tz.initializeTimeZones();

    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    MediaKit.ensureInitialized();

    await migrateMacOsFromSandboxToNoSandbox();

    // force High Refresh Rate on some Android devices (like One Plus)
    if (kIsAndroid) {
      await FlutterDisplayMode.setHighRefreshRate();
    }
    if (!kIsWeb) {
      MetadataGod.initialize();
    }

    await KVStoreService.initialize();

    // Best-effort desktop integrations: a failure here must degrade the
    // feature (tray/close-behavior/media keys), never abort launch.
    if (kIsDesktop) {
      await guardedStartupInit('windowManager.setPreventClose', () async {
        await windowManager.setPreventClose(true);
      });
    }

    if (kIsWindows) {
      await guardedStartupInit('SMTCWindows.initialize', () async {
        await SMTCWindows.initialize();
      });
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
    ref.listen(
      metadataPluginUpdateCheckerProvider,
      (_, __) {},
      onError: logAsyncError,
    );
    ref.listen(
      audioSourcePluginUpdateCheckerProvider,
      (_, __) {},
      onError: logAsyncError,
    );
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

    final builtInLightScheme =
        colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.light) ??
            LegacyColorSchemes.lightSlate();

    final builtInDarkScheme =
        colorSchemeMap[accentMaterialColor.name]?.call(ThemeMode.dark) ??
            LegacyColorSchemes.darkSlate();

    // Live theme wins; cached theme seeds the first paint instantly
    // and is silently replaced when live resolves. Built-in otherwise.
    final pluginTheme =
        themeDefinition.asData?.value ?? cachedThemeDefinition.asData?.value;

    final lightColorScheme = pluginTheme == null
        ? builtInLightScheme
        : _resolveColorScheme(
            pluginTheme.light,
            brightness: Brightness.light,
            fallback: builtInLightScheme,
          );

    final darkColorScheme = pluginTheme == null
        ? builtInDarkScheme
        : _resolveColorScheme(
            pluginTheme.dark,
            brightness: Brightness.dark,
            fallback: builtInDarkScheme,
          );

    // v2 contract wiring: surfaces carry translucency into ThemeData,
    // ThemeBackgroundScope/ThemeSurfacesScope render background/tint.
    // density and the full radius scale stay parsed-but-unrendered.
    // Interim radius mapping: shadcn takes a single radius multiplier
    // (default 0.5), so scale medium proportionally against its default
    // of 10.0 until small/medium/large/pill are wired to components.
    final pluginRadius =
        pluginTheme == null ? .5 : pluginTheme.radius.medium / 20;

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

        return ThemeBackgroundScope(
          child: ThemeSurfacesScope(child: child),
        );
      },
      scaling: const AdaptiveScaling(1),
      theme: ThemeData(
        radius: pluginRadius,
        iconTheme: const IconThemeProperties(),
        colorScheme: lightColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      darkTheme: ThemeData(
        radius: pluginRadius,
        iconTheme: const IconThemeProperties(),
        colorScheme: darkColorScheme,
        surfaceOpacity: pluginTheme?.surfaces.opacity ?? .8,
        surfaceBlur: pluginTheme?.surfaces.blur ?? 10,
      ),
      materialTheme: material.ThemeData(
        brightness: switch (themeMode) {
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
        },
        splashFactory: material.NoSplash.splashFactory,
        appBarTheme: const material.AppBarTheme(
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          elevation: 0,
        ),
      ),
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
