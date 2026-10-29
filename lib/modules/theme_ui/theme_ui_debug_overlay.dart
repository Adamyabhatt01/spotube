import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/theme_ui/theme_ui_binding_registry.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';

/// Turns the binding inspector on.
///
/// Off by default and independent of debug mode: a developer can flip it from
/// a debug console or a future settings row without rebuilding the app.
final themeUiDebugOverlayProvider = StateProvider<bool>((ref) => false);

/// Lists what the active document asks the host to subscribe to.
///
/// The overlay exists to answer two questions while authoring a theme: "what
/// did demand detection actually see?" and "how many sources does that
/// cost?". A name that appears here but never renders means the scan matched
/// a string the renderer does not use; a source count of zero means the theme
/// is static.
class ThemeUiBindingDebugOverlay extends ConsumerWidget {
  const ThemeUiBindingDebugOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demand = ref.watch(themeUiBindingDemandProvider);
    final names = demand.names.toList()..sort();
    final sources = demand.sources.toList()..sort();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 340,
      height: 300,
      child: SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Theme UI bindings',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.foreground,
                      ),
                    ),
                  ),
                  IconButton.ghost(
                    icon: const Icon(SpotubeIcons.close, size: 16),
                    onPressed: () => ref
                        .read(themeUiDebugOverlayProvider.notifier)
                        .state = false,
                  ),
                ],
              ),
              Text(
                '${names.length} active · ${sources.length} sources',
                style: TextStyle(fontSize: 11, color: scheme.mutedForeground),
              ),
              if (sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    sources.join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.mutedForeground,
                    ),
                  ),
                ),
              const Gap(6),
              Expanded(
                child: names.isEmpty
                    ? Text(
                        'No bindings referenced.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.mutedForeground,
                        ),
                      )
                    : ListView.builder(
                        itemCount: names.length,
                        itemBuilder: (context, index) {
                          final name = names[index];
                          final definition =
                              ThemeUiBindingRegistry.lookup(name);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.foreground,
                                    ),
                                  ),
                                ),
                                if (definition != null)
                                  Text(
                                    definition.source,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.mutedForeground,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
