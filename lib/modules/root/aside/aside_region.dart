import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Whether the aside has room to mount.
///
/// Needs all three: a theme that asked for the panel, a user who left it open,
/// and a window past the compact tier — the same 820 boundary the layout
/// breakpoints use. A third column inside the compact tier would squeeze the
/// content below the width it is designed for.
bool themeAsideVisible({
  required bool themeAsks,
  required bool userOpen,
  required double windowWidth,
}) =>
    themeAsks && userOpen && windowWidth > Breakpoints.md;

/// The right-hand panel a theme fills through `aside.content`.
///
/// The host owns this frame — placement, width, divider and the close
/// control — so a theme can fill a now-playing panel without being able to
/// strand the user in it. Closing persists through `asideOpen`; the shortcut
/// and `toggleAside` reopen the same panel.
class AsideRegion extends ConsumerWidget {
  const AsideRegion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: IconButton.ghost(
              icon: const Icon(SpotubeIcons.close),
              onPressed: () => ref
                  .read(userPreferencesProvider.notifier)
                  .setAsideOpen(false),
            ),
          ),
        ),
        const Expanded(
          child: ThemeSlot(
            'aside.content',
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        ),
      ],
    );
  }
}
