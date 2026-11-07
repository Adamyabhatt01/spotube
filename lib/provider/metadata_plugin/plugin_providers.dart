part of 'metadata_plugin_provider.dart';

final metadataPluginsProvider =
    AsyncNotifierProvider<MetadataPluginNotifier, MetadataPluginState>(
  MetadataPluginNotifier.new,
);

final metadataPluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultMetadataPluginConfig),
    );
    final youtubeEngine = ref.read(youtubeEngineProvider);

    if (defaultPlugin == null) {
      return null;
    }

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);

    return await MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
  },
);

final audioSourcePluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultAudioSourcePluginConfig),
    );
    final youtubeEngine = ref.watch(youtubeEngineProvider);

    if (defaultPlugin == null) {
      return null;
    }

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);

    return await MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
  },
);

/// The build-time static theme payload, when the selected theme shipped one.
///
/// Read off disk, never through Hetu: a theme whose payload is static costs
/// a file read instead of a VM boot. Null when the selected theme has no
/// `theme.json` (third-party or older builds), when nothing is recorded as
/// the theme default, or when the file does not decode — every miss just
/// falls back to the live `getTheme()` path.
final themeStaticPayloadProvider = FutureProvider<StaticThemePayload?>(
  (ref) async {
    final pluginKey = await ref.watch(storedThemePluginKeyProvider.future);
    return readStaticThemePayload(pluginKey);
  },
);

final themeDefinitionProvider = FutureProvider<ThemeDefinition?>(
  (ref) async {
    try {
      // Recomputes when the shell reports a possible palette change.
      // Unconditional by design: shell involvement is only known after
      // the plugin theme loads, and scheme changes are rare.
      ref.watch(shellThemeSignalProvider);

      final defaultPlugin = await ref.watch(
        metadataPluginsProvider
            .selectAsync((data) => data.defaultThemePluginConfig),
      );

      // The static payload wins: no Hetu VM is created when the theme
      // shipped one. The VM boots only for themes that did not, and then
      // only to ask `getTheme()` what the build already knew.
      final staticPayload = await ref.watch(themeStaticPayloadProvider.future);
      final ThemeDefinition? definition;
      if (staticPayload != null) {
        definition = staticPayload.definition;
      } else {
        // Reuses a memoized plugin instance instead of spinning a fresh Hetu
        // VM on every recompute (the previous code created one per signal,
        // and Hetu VMs are never released). The instance only rebuilds when
        // the default theme plugin changes.
        final plugin = await ref.watch(themePluginProvider.future);
        if (plugin == null) return null;
        definition = await plugin.theme.getTheme();
      }

      // Generic shell handoff: no shell names or paths here. When the
      // plugin declares `dynamic.source == shell`, the host shell source
      // supplies the palette and, if it renders through user config, the
      // glass the desktop actually draws with. Geometry stays plugin-owned.
      // NOTE: ref.read (not watch) is required here — this runs after
      // awaits. Reactivity comes from shellThemeSignalProvider above.
      final resolved = await resolveThemeDefinition(
        definition,
        readShellTheme: () => ref.read(themeShellSourceProvider).getTheme(),
        readShellGlass: () => ref.read(themeShellSourceProvider).getGlass(),
      );

      // Cache only successful resolutions for instant warm startup.
      // Null (failure) outcomes never touch the cache.
      if (resolved != null && defaultPlugin != null) {
        unawaited(
          writeThemeCache(
            pluginKey: themePluginKey(defaultPlugin),
            shellKey: ref.read(themeShellSourceProvider).cacheKey,
            definition: resolved,
          ),
        );
      }
      return resolved;
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace, 'themeDefinitionProvider');
      return null;
    }
  },
);

/// Memoized theme plugin instance. Rebuilds only when the default theme
/// plugin changes, so theme recomputes reuse the same Hetu VM instead of
/// creating a new one each time (Hetu VMs are never disposed).
///
/// The VM boots lazily: [themeDefinitionProvider] prefers the static
/// payload, so this is only reached for themes that shipped none, or for a
/// `showSettings()`/`onUiAction()`/`getUi()` call that still needs one.
final themePluginProvider = FutureProvider<MetadataPlugin?>(
  (ref) async {
    final defaultPlugin = await ref.watch(
      metadataPluginsProvider
          .selectAsync((data) => data.defaultThemePluginConfig),
    );
    if (defaultPlugin == null) return null;

    final pluginsNotifier = ref.read(metadataPluginsProvider.notifier);
    final pluginByteCode =
        await pluginsNotifier.getPluginByteCode(defaultPlugin);
    final youtubeEngine = ref.read(youtubeEngineProvider);

    final plugin = await MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );

    // A lazily booted VM has not run `getTheme()`, so its capability grant
    // is empty. The static payload already knows it; seed it so documents
    // from `showSettings()`/`onUiAction()` keep their permissions.
    final staticPayload = await ref.read(themeStaticPayloadProvider.future);
    if (staticPayload != null) {
      plugin.theme.seedPayloadCapabilities(
        staticPayload.definition.capabilities,
      );
    }
    return plugin;
  },
);

/// UI a theme answers from its optional `getUi()` method.
///
/// Kept separate from [themeUiProvider] so a shell palette refresh does not
/// re-invoke the plugin: this future only rebuilds when the plugin VM does.
final pluginThemeUiProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  final plugin = await ref.watch(themePluginProvider.future);
  if (plugin == null) return null;
  return plugin.theme.getUi();
});

/// UI a theme answers from its optional `showSettings()` method.
///
/// Cached for the same reason as [pluginThemeUiProvider]: opening the
/// settings dialog twice must not spin the Hetu VM twice. The host uses the
/// document's `settings.content` slot and persists values through the
/// per-theme settings namespace.
final pluginThemeSettingsProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  // A static payload that declares no `showSettings()` means the theme has
  // no settings; the VM stays unbooted instead of answering "nothing"
  // from a fresh process.
  final staticPayload = await ref.watch(themeStaticPayloadProvider.future);
  if (staticPayload != null && !staticPayload.needsVmForSettings) {
    return null;
  }
  final plugin = await ref.watch(themePluginProvider.future);
  if (plugin == null) return null;
  return plugin.theme.getSettings();
});

/// A UI document returned by a theme's `onUiAction()`.
///
/// It wins over the current inline/`getUi()` document for the rest of the
/// session, which is what makes a plugin-driven screen change feel like a
/// live theme rather than a one-shot re-render. Selecting another theme
/// clears it through [MetadataPluginNotifier.refreshThemeDefinition].
final themeUiOverrideProvider = StateProvider<ThemeUiDocument?>((ref) => null);

/// The declarative UI the app should draw.
///
/// A theme may carry it inline in `getTheme()` (and then it rides the theme
/// definition cache) or answer from `getUi()`. Inline wins, because it
/// arrived with the same payload the colours did.
///
/// A `specVersion: 3` payload gets no UI at all: v4 is a breaking contract and
/// there is no runtime v3 compatibility layer. The gate is here as well as in
/// `sanitizeThemeDefinition` because that one only strips the tree carried
/// inline — this is the seam that can also call into the plugin, so refusing
/// here means a v3 theme's `getUi()` is never invoked.
final themeUiProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  final override = ref.watch(themeUiOverrideProvider);
  if (override != null) return override;

  final definition = await ref.watch(themeDefinitionProvider.future);
  if (definition == null) return null;
  if (definition.specVersion == 3) return null;
  if (definition.ui != null) return definition.ui;
  // A static payload that declares no `getUi()` answers "no UI" without
  // booting the VM at all. Only a payload that declares it (and shipped
  // no tree) — or a theme with no static payload — reaches the plugin.
  final staticPayload = await ref.watch(themeStaticPayloadProvider.future);
  if (staticPayload != null && !staticPayload.needsVmForUi) return null;
  return ref.watch(pluginThemeUiProvider.future);
});

/// In-memory cache for MetadataPlugin instances (Hetu VMs).
/// Scoped to provider lifecycle with explicit disposal. Generic so the
/// failure-recovery and eviction semantics are unit-testable without a
/// real Hetu VM.
