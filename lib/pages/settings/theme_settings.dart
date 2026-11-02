import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/theme_ui/host_widgets/theme_ui_settings_body.dart';
import 'package:spotube/modules/theme_ui/theme_ui_bindings.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// Opens the active theme's own settings.
///
/// A theme opts in by answering `showSettings()` with a UI document; the host
/// renders its `settings.content` slot inside this standard shell and persists
/// values through the per-theme settings namespace. A theme with no method (or
/// a malformed answer) gets the empty state instead of a broken dialog.
Future<void> showThemeSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ThemeSettingsDialog(),
  );
}

class ThemeSettingsDialog extends ConsumerWidget {
  const ThemeSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(pluginThemeSettingsProvider);
    final children =
        settings.asData?.value?.slots['settings.content']?.children;
    final hasContent = children != null && children.isNotEmpty;

    return AlertDialog(
      title: Text(context.l10n.theme_settings).h4(),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(320.0, 560.0).toDouble(),
        height:
            MediaQuery.sizeOf(context).height.clamp(240.0, 520.0).toDouble(),
        child: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text(context.l10n.theme_settings_empty),
          ),
          data: (ui) {
            if (ui == null || !hasContent) {
              return Center(child: Text(context.l10n.theme_settings_empty));
            }
            return ThemeSettingsBody(ui: ui, scroll: true);
          },
        ),
      ),
      actions: [
        if (hasContent)
          Button.outline(
            leading: const Icon(SpotubeIcons.refresh),
            child: Text(context.l10n.theme_settings_reset),
            onPressed: () => ref.read(themeUiSettingsProvider.notifier).reset(),
          ),
        Button.primary(
          child: Text(context.l10n.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
