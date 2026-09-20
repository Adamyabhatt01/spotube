import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide AlertDialog, IconButton;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Lets the user reorder the audio-source resolution priority. Engines and
/// installed audio-source plugins are listed in priority order; the user can
/// reorder them (drag or arrow buttons). Stable identifiers (engine labels
/// and plugin slugs) are persisted, so the order survives plugin updates.
class SettingsPlaybackSourcePriorityDialog extends ConsumerStatefulWidget {
  const SettingsPlaybackSourcePriorityDialog({super.key});

  @override
  ConsumerState<SettingsPlaybackSourcePriorityDialog> createState() =>
      _SettingsPlaybackSourcePriorityDialogState();
}

class _SettingsPlaybackSourcePriorityDialogState
    extends ConsumerState<SettingsPlaybackSourcePriorityDialog> {
  late List<String> _priority;

  @override
  void initState() {
    super.initState();
    _priority = List.of(
      ref.read(userPreferencesProvider).sourcePriority,
    );
  }

  void _persist() {
    ref
        .read(userPreferencesProvider.notifier)
        .setSourcePriority(_priority);
  }

  @override
  Widget build(BuildContext context) {
    final plugins = ref.watch(metadataPluginsProvider).valueOrNull?.plugins ??
        const <PluginConfiguration>[];
    final audioSourcePlugins = plugins
        .where((p) => p.abilities.contains(PluginAbilities.audioSource))
        .toList();

    final availableEngines = YoutubeClientEngine.values
        .where((e) => e.isAvailableForPlatform())
        .toList();

    // Build the ordered list of stable identifiers, falling back to a
    // sensible default order when none has been persisted yet.
    final orderedIds = <String>[];
    final hasPersisted = _priority.isNotEmpty;
    final ids = hasPersisted
        ? _priority
        : [
            ...availableEngines.map((e) => e.label),
            ...audioSourcePlugins.map((p) => p.slug),
          ];
    for (final id in ids) {
      final isEngine = availableEngines.any((e) => e.label == id);
      final isPlugin = audioSourcePlugins.any((p) => p.slug == id);
      if (isEngine || isPlugin) {
        orderedIds.add(id);
      }
    }

    String labelFor(String id) {
      final engine = availableEngines
          .firstWhereOrNull((e) => e.label == id);
      if (engine != null) return "${engine.label} (engine)";
      final plugin =
          audioSourcePlugins.firstWhereOrNull((p) => p.slug == id);
      if (plugin != null) return "${plugin.name} (audio source)";
      return id;
    }

    void move(int from, int to) {
      setState(() {
        final item = orderedIds.removeAt(from);
        orderedIds.insert(to, item);
        _priority = List.of(orderedIds);
        _persist();
      });
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: AlertDialog(
        title: Text(context.l10n.source_priority).h4(),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.source_priority_description),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: orderedIds.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  move(oldIndex, newIndex);
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final id = orderedIds[index];
                  return ListTile(
                    key: ValueKey(id),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(SpotubeIcons.dragHandle),
                    ),
                    title: Text(labelFor(id)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: index == 0 ? null : () => move(index, index - 1),
                        ),
                        IconButton.outline(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: index == orderedIds.length - 1
                              ? null
                              : () => move(index, index + 1),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          Button.outline(
            child: Text(context.l10n.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}