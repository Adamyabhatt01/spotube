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

final themeDefinitionProvider = FutureProvider<ThemeDefinition?>(
  (ref) async {
    try {
      // Recomputes when the shell reports a possible palette change.
      // Unconditional by design: shell involvement is only known after
      // the plugin theme loads, and scheme changes are rare.
      ref.watch(shellThemeSignalProvider);

      // Reuses a memoized plugin instance instead of spinning a fresh Hetu
      // VM on every recompute (the previous code created one per signal,
      // and Hetu VMs are never released). The instance only rebuilds when
      // the default theme plugin changes.
      final plugin = await ref.watch(themePluginProvider.future);
      if (plugin == null) return null;

      final defaultPlugin = await ref.watch(
        metadataPluginsProvider
            .selectAsync((data) => data.defaultThemePluginConfig),
      );
      if (defaultPlugin == null) return null;

      final definition = await plugin.theme.getTheme();

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
      if (resolved != null) {
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

    return MetadataPlugin.create(
      youtubeEngine,
      defaultPlugin,
      pluginByteCode,
    );
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
final themeUiProvider = FutureProvider<ThemeUiDocument?>((ref) async {
  final override = ref.watch(themeUiOverrideProvider);
  if (override != null) return override;

  final definition = await ref.watch(themeDefinitionProvider.future);
  if (definition == null) return null;
  if (definition.ui != null) return definition.ui;
  return ref.watch(pluginThemeUiProvider.future);
});

/// In-memory cache for MetadataPlugin instances (Hetu VMs).
/// Scoped to provider lifecycle with explicit disposal. Generic so the
/// failure-recovery and eviction semantics are unit-testable without a
/// real Hetu VM.
