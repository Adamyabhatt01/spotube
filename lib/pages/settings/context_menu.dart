import 'package:flutter/material.dart'
    show ListTile, ReorderableListView, ReorderableDragStartListener;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/context_menu/context_menu_action.dart';
import 'package:spotube/modules/context_menu/context_menu_builder.dart';
import 'package:spotube/modules/context_menu/context_menu_config.dart';
import 'package:spotube/modules/context_menu/context_menu_labels.dart';
import 'package:spotube/modules/context_menu/context_menu_target.dart';
import 'package:spotube/provider/context_menu/context_menu_provider.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

Future<void> showContextMenuSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ContextMenuSettingsDialog(),
  );
}

/// Settings → Appearance → Context menu.
///
/// The list is the same builder the live menus use, with `includeHidden` and
/// `evaluateWhen: false` so an owner-only or pinned-only row is still
/// configurable. Every edit persists immediately; there is no Save button to
/// forget.
class ContextMenuSettingsDialog extends ConsumerStatefulWidget {
  const ContextMenuSettingsDialog({super.key});

  @override
  ConsumerState<ContextMenuSettingsDialog> createState() =>
      _ContextMenuSettingsDialogState();
}

class _ContextMenuSettingsDialogState
    extends ConsumerState<ContextMenuSettingsDialog> {
  ContextMenuTarget _target = ContextMenuTarget.playlist;

  void _update(
    ContextMenuTargetConfig Function(ContextMenuTargetConfig current) change,
  ) {
    final current = ref.read(contextMenuConfigProvider).forTarget(_target);
    ref
        .read(contextMenuConfigProvider.notifier)
        .setTargetConfig(_target, change(current));
  }

  List<ContextMenuAction> _preview(
    BuildContext context,
    ThemeUiDocument? ui,
  ) {
    final builder = ContextMenuBuilder(
      label: contextMenuLabeler(context),
      config: ref.watch(contextMenuConfigProvider),
      pinTargets: context.layout.pinTargets,
      capabilities: ui?.capabilities.toSet() ?? const {},
      themeMenus: ui?.menus ?? const {},
    );
    return builder.build(
      ContextMenuItemContext(
        target: _target,
        flags: const {
          'owner': true,
          'pinnedTargets': <String>[],
        },
      ),
      evaluateWhen: false,
      enforceCapabilities: false,
      includeHidden: true,
    );
  }

  List<ThemePinTarget> _effectivePinTargets(BuildContext context) {
    final declared = context.layout.pinTargets;
    if (declared.isNotEmpty) return declared;
    // Mirrors the builder's fallback: an undeclared list keeps the historic
    // sidebar target, and the user must still be able to hide it.
    return [ThemePinTarget(id: 'sidebar', label: context.l10n.sidebar)];
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(contextMenuTargetConfigProvider(_target));
    final ui = ref.watch(themeUiProvider).asData?.value;
    final actions = _preview(context, ui);
    final pinTargets = _effectivePinTargets(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AlertDialog(
        title: Text(context.l10n.context_menu).h4(),
        content: SizedBox(
          width: 520,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.context_menu_description),
              const SizedBox(height: 12),
              Text(context.l10n.context_menu_target).semiBold(),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final target in ContextMenuTarget.values)
                    _targetButton(context, target),
                ],
              ),
              const SizedBox(height: 12),
              Text(context.l10n.context_menu_actions).semiBold(),
              const SizedBox(height: 4),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: actions.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final ids = [for (final action in actions) action.id];
                    if (oldIndex < 0 || oldIndex >= ids.length) return;
                    if (newIndex < 0 || newIndex >= ids.length) return;
                    final moved = ids.removeAt(oldIndex);
                    ids.insert(newIndex, moved);
                    _update((current) => current.copyWith(order: ids));
                  },
                  itemBuilder: (context, index) {
                    final action = actions[index];
                    final hidden = config.hidden.contains(action.id);
                    return ListTile(
                      key: ValueKey('context-menu-order:${action.id}'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(SpotubeIcons.dragHandle),
                      ),
                      title: Row(
                        spacing: 8,
                        children: [
                          if (contextMenuIcon(action.icon) != null)
                            Icon(contextMenuIcon(action.icon), size: 16),
                          Expanded(
                            child: Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: action.destructive
                                  ? TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .destructive,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      trailing: Switch(
                        value: !hidden,
                        onChanged: (visible) {
                          final next = Set<String>.of(config.hidden);
                          if (visible) {
                            next.remove(action.id);
                          } else {
                            next.add(action.id);
                          }
                          _update((current) => current.copyWith(hidden: next));
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                title: Text(context.l10n.context_menu_show_icons),
                trailing: Switch(
                  value: config.showIcons,
                  onChanged: (value) =>
                      _update((current) => current.copyWith(showIcons: value)),
                ),
              ),
              ListTile(
                title: Text(context.l10n.context_menu_confirm_destructive),
                trailing: Switch(
                  value: config.confirmDestructive,
                  onChanged: (value) => _update(
                    (current) => current.copyWith(confirmDestructive: value),
                  ),
                ),
              ),
              if (pinTargets.isNotEmpty) ...[
                const Divider(),
                Text(context.l10n.context_menu_hidden_pin_targets).semiBold(),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final pin in pinTargets)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: !config.hiddenPinTargets.contains(pin.id),
                            onChanged: (visible) {
                              final next =
                                  Set<String>.of(config.hiddenPinTargets);
                              if (visible) {
                                next.remove(pin.id);
                              } else {
                                next.add(pin.id);
                              }
                              _update(
                                (current) =>
                                    current.copyWith(hiddenPinTargets: next),
                              );
                            },
                          ),
                          Text(pin.label),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          Button.outline(
            onPressed: () => ref
                .read(contextMenuConfigProvider.notifier)
                .resetTarget(_target),
            child: Text(context.l10n.context_menu_reset_target),
          ),
          Button.outline(
            onPressed: () =>
                ref.read(contextMenuConfigProvider.notifier).resetAll(),
            child: Text(context.l10n.context_menu_reset_all),
          ),
          Button.primary(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Widget _targetButton(BuildContext context, ContextMenuTarget target) {
    final selected = target == _target;
    final label = switch (target) {
      ContextMenuTarget.track => context.l10n.context_menu_track,
      ContextMenuTarget.playlist => context.l10n.playlist,
      ContextMenuTarget.album => context.l10n.album,
      ContextMenuTarget.artist => context.l10n.artist,
      ContextMenuTarget.queueItem => context.l10n.queue,
      ContextMenuTarget.download => context.l10n.download,
      ContextMenuTarget.searchResult => context.l10n.search,
      ContextMenuTarget.radio => context.l10n.context_menu_radio,
    };
    final child = Text(label);
    return selected
        ? Button.primary(
            onPressed: () => setState(() => _target = target),
            child: child,
          )
        : Button.outline(
            onPressed: () => setState(() => _target = target),
            child: child,
          );
  }
}
