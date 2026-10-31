import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/modules/theme_shell/theme_navigation.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// A routed page owned by the active theme.
///
/// One route serves every page: auto_route generates routes at build time, so
/// a theme can declare pages but never register routes. The body is the theme's
/// `page.<id>` slot inside the normal shell, and a page whose document goes
/// away (theme switch, unknown parent) removes itself rather than stranding the
/// user on an empty route.
@RoutePage()
class ThemePage extends HookConsumerWidget {
  static const name = 'theme_page';

  final String pageId;

  const ThemePage({super.key, @PathParam('pageId') required this.pageId});

  @override
  Widget build(BuildContext context, ref) {
    final async = ref.watch(themeUiProvider);
    final page = routableThemePage(async.asData?.value, pageId);

    // Only a resolved document may declare the page gone: while the theme is
    // still loading, popping would kill the page the app just opened.
    final missing = async.hasValue && page == null;
    useEffect(
      () {
        if (missing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _pop(context);
          });
        }
        return null;
      },
      [missing],
    );
    if (page == null) return const SizedBox.shrink();

    final title = themePageTitle(page);
    return Scaffold(
      headers: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 8),
            child: Row(
              children: [
                if (page.showBack) ...[
                  IconButton.ghost(
                    icon: const Icon(SpotubeIcons.angleLeft),
                    onPressed: () => _pop(context),
                  ),
                  const Gap(6),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: ThemePageContent(
        slot: 'page.${page.id}',
        bindings: {
          'page.id': page.id,
          'page.title': title,
        },
        fallback: const SizedBox.shrink(),
      ),
    );
  }

  /// Pops this page when it is mounted on a router.
  ///
  /// Widget tests and previews mount the page without one; there is nothing to
  /// pop and [context.router] would assert, so the absence of a router is a
  /// no-op rather than an error.
  static void _pop(BuildContext context) {
    try {
      final router = context.router;
      unawaited(router.maybePop());
    } on Object {
      // No router above this widget.
    }
  }
}
