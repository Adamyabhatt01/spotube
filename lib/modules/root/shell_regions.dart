import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/modules/root/aside/aside_region.dart';
import 'package:spotube/modules/root/bottom_player.dart';
import 'package:spotube/modules/root/sidebar/sidebar.dart';
import 'package:spotube/modules/root/spotube_navigation_bar.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/platform.dart';

/// The router outlet.
///
/// A shell always has exactly one of these. The outlet is passed in from the
/// app root so the keyed `AutoRouter` subtree keeps its identity no matter
/// where the layout puts it.
class ContentRegion extends StatelessWidget {
  final Widget content;

  const ContentRegion({required this.content, super.key});

  @override
  Widget build(BuildContext context) => content;
}

/// The host sidebar, or the theme's replacement body.
///
/// The shell owns the region's width, so the sidebar is mounted without its
/// own content column. `MediaQuery.size` is overridden to the region's real
/// size because the sidebar's labelled/rail decision reads it.
class SidebarRegion extends ConsumerWidget {
  final String? slot;

  const SidebarRegion({this.slot, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = this.slot;
    if (slot != null) {
      return ThemeSlot(slot, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
          child: const Sidebar(
            standalone: true,
            child: SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// The right-hand panel, or a slot the shell targets instead.
class ShellAsideRegion extends ConsumerWidget {
  final String? slot;

  const ShellAsideRegion({this.slot, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = this.slot;
    if (slot != null) {
      return ThemeSlot(slot, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return const AsideRegion();
  }
}

/// The playback bar.
///
/// The seek width is taken from this region's actual width, not the window's:
/// a player docked under the content is narrower than the window and used to
/// decide volume visibility against the wrong number.
class PlayerRegion extends ConsumerWidget {
  final String? slot;

  const PlayerRegion({this.slot, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = this.slot;
    if (slot != null) {
      return ThemeSlot(slot, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return MeasuredBottomPlayer(
      child: LayoutBuilder(
        builder: (context, constraints) => PlayerSeekWidth(
          width: constraints.maxWidth,
          child: const BottomPlayer(forceBar: true),
        ),
      ),
    );
  }
}

/// The window drag strip.
///
/// Pages own their own title bars, so the host does not duplicate window
/// controls here; the strip only makes the top band draggable when a theme
/// placed one. A slot may draw decorations inside it.
class TitlebarRegion extends ConsumerWidget {
  final String? slot;

  const TitlebarRegion({this.slot, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = this.slot;
    Widget child = slot == null
        ? const SizedBox.expand()
        : ThemeSlot(
            slot,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          );
    if (!kIsDesktop) return child;

    final systemTitleBar = ref.watch(
      userPreferencesProvider.select((s) => s.systemTitleBar),
    );
    if (systemTitleBar) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: DragToMoveArea(child: child),
    );
  }
}

/// The bottom navigation bar, or the theme's replacement.
class NavbarRegion extends ConsumerWidget {
  final String? slot;

  const NavbarRegion({this.slot, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = this.slot;
    if (slot != null) {
      return ThemeSlot(slot, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return const SpotubeNavigationBar(forceVisible: true);
  }
}

/// A theme-defined region (`region: custom`).
///
/// The parser guarantees a slot; the wrapper publishes the region label to
/// screen readers.
class CustomRegion extends StatelessWidget {
  final String slot;
  final String? label;

  const CustomRegion({required this.slot, this.label, super.key});

  @override
  Widget build(BuildContext context) {
    final content = ThemeSlot(
      slot,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
    final label = this.label;
    if (label == null) return content;
    return Semantics(
      label: label,
      container: true,
      child: content,
    );
  }
}
