import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/form/checkbox_form_field.dart';
import 'package:spotube/components/form/text_form_field.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/library/playlists.dart';
import 'package:spotube/provider/metadata_plugin/playlist/playlist.dart';

class PlaylistCreateDialog extends HookConsumerWidget {
  /// Track ids to add to the playlist
  final List<String> trackIds;
  final String? playlistId;
  const PlaylistCreateDialog({
    super.key,
    this.trackIds = const [],
    this.playlistId,
  });

  @override
  Widget build(BuildContext context, ref) {
    final userPlaylists = ref.watch(metadataPluginSavedPlaylistsProvider);
    final playlist =
        ref.watch(metadataPluginPlaylistProvider(playlistId ?? ""));
    final playlistNotifier =
        ref.watch(metadataPluginPlaylistProvider(playlistId ?? "").notifier);

    final isSubmitting = useState(false);

    final formKey = useMemoized(() => GlobalKey<FormBuilderState>(), []);

    final updatingPlaylist = useMemoized(
      () => userPlaylists.asData?.value.items
          .firstWhereOrNull((playlist) => playlist.id == playlistId),
      [
        userPlaylists.asData?.value.items,
        playlistId,
      ],
    );

    final isUpdatingPlaylist = playlistId != null;

    final l10n = context.l10n;
    final theme = Theme.of(context);

    useEffect(() {
      if (playlist.asData?.value != null) {
        formKey.currentState?.patchValue({
          'playlistName': playlist.asData!.value.name,
          'description': playlist.asData!.value.description,
          'public': playlist.asData!.value.public,
          'collaborative': playlist.asData!.value.collaborative,
        });
      }

      return;
    }, [playlist]);

    final onError = useCallback((error) {
      showToast(
        context: context,
        location: ToastLocation.topRight,
        builder: (context, overlay) {
          return SurfaceCard(
            child: Basic(
              title: Text(
                l10n.error(l10n.epic_failure),
                style: theme.typography.normal.copyWith(
                  color: theme.colorScheme.destructive,
                ),
              ),
              subtitle: Text(
                error.toString().split('\n').first,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      );
    }, [l10n, theme]);

    final onWarning = useCallback((String playlistName) {
      // The toast cannot use the dialog's own context: the dialog puts a
      // ToastLayer around itself, that layer dies with the dialog, and this
      // warning only arrives after the network has answered — long after
      // the dialog is gone. The root navigator's context lives under the
      // app's own ToastLayer and stays alive.
      final toastContext = rootNavigatorKey.currentContext ?? context;
      if (!toastContext.mounted) return;

      showToast(
        context: toastContext,
        location: ToastLocation.topRight,
        builder: (context, overlay) {
          return SurfaceCard(
            child: Basic(
              title: Text(
                l10n.warning,
                style: theme.typography.normal.copyWith(
                  color: theme.colorScheme.destructive,
                ),
              ),
              subtitle: Text(
                l10n.playlist_library_sync_failed(playlistName),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      );
    }, [l10n, theme]);

    Future<void> onCreate() async {
      if (!formKey.currentState!.saveAndValidate()) return;

      SpotubeFullPlaylistObject? result;
      try {
        isSubmitting.value = true;
        final values = formKey.currentState!.value;

        // Only the name is mandatory. Providers can fill in a cover from the
        // playlist contents, and an empty description is valid for every
        // provider (the plugin endpoint drops null arguments).
        final playlistName = (values['playlistName'] as String).trim();
        final description = (values['description'] as String?)?.trim() ?? '';
        final public = values['public'] as bool?;
        final collaborative = values['collaborative'] as bool?;

        if (isUpdatingPlaylist) {
          await playlistNotifier.modify(
            name: playlistName,
            description: description,
            public: public,
            collaborative: collaborative,
            onError: onError,
          );
          result = ref
              .read(metadataPluginPlaylistProvider(playlistId!))
              .asData
              ?.value;
        } else {
          result = await playlistNotifier.create(
            name: playlistName,
            description: description,
            public: public,
            collaborative: collaborative,
            trackIds: trackIds,
            onError: onError,
            onWarning: onWarning,
          );
        }
      } catch (_) {
        // The notifier has already reported the failure. Keep the dialog
        // open so the user can retry without losing the form values.
        return;
      } finally {
        isSubmitting.value = false;
      }

      if (!context.mounted) return;
      if (result == null) {
        context.router.maybePop();
      } else {
        context.router.maybePop<SpotubeFullPlaylistObject>(result);
      }
    }

    return AlertDialog(
      title: Text(
        isUpdatingPlaylist
            ? context.l10n.update_playlist
            : context.l10n.create_a_playlist,
      ),
      actions: [
        Button.outline(
          child: Text(context.l10n.cancel),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        Button.primary(
          onPressed: onCreate,
          enabled: !playlist.isLoading & !isSubmitting.value,
          child: Text(
            isUpdatingPlaylist ? context.l10n.update : context.l10n.create,
          ),
        ),
      ],
      content: Container(
        width: MediaQuery.of(context).size.width,
        constraints: const BoxConstraints(maxWidth: 500),
        child: FormBuilder(
          key: formKey,
          initialValue: {
            'playlistName': updatingPlaylist?.name,
            'description': updatingPlaylist?.description,
            'public': playlist.asData?.value.public ?? false,
            'collaborative': playlist.asData?.value.collaborative ?? false,
          },
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormBuilderField(
                name: 'playlistName',
                label: Text(context.l10n.playlist_name),
                placeholder: Text(context.l10n.name_of_playlist),
                validator: FormBuilderValidators.required(),
              ),
              const Gap(20),
              TextFormBuilderField(
                name: 'description',
                label: Text(context.l10n.description),
                // Optional: providers are free to derive or omit it.
                placeholder: Text(context.l10n.description),
                keyboardType: TextInputType.multiline,
                maxLines: 5,
              ),
              const Gap(20),
              CheckboxFormBuilderField(
                name: 'public',
                trailing: Text(context.l10n.public),
              ),
              const Gap(10),
              CheckboxFormBuilderField(
                name: 'collaborative',
                trailing: Text(context.l10n.collaborative),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaylistCreateDialogButton extends HookConsumerWidget {
  /// Tracks that should be added to the newly-created playlist.
  final List<String> trackIds;

  const PlaylistCreateDialogButton({super.key, this.trackIds = const []});

  showPlaylistDialog(BuildContext context) {
    showDialog(
      context: context,
      alignment: Alignment.center,
      builder: (context) => ToastLayer(
        child: PlaylistCreateDialog(trackIds: trackIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    return Button.secondary(
      leading: const Icon(SpotubeIcons.addFilled),
      child: Text(context.l10n.playlist),
      onPressed: () => showPlaylistDialog(context),
    );
  }
}
