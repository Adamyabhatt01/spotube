import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/dialogs/delete_downloads_dialog.dart';
import 'package:spotube/modules/library/user_downloads/download_item.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/download_manager_provider.dart';
import 'package:spotube/provider/download_wipe_provider.dart';
import 'package:auto_route/auto_route.dart';

@RoutePage()
class UserDownloadsPage extends HookConsumerWidget {
  static const name = 'user_downloads';
  const UserDownloadsPage({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final downloadQueue = ref.watch(downloadManagerProvider);
    final downloadManagerNotifier = ref.watch(downloadManagerProvider.notifier);
    final downloadCount =
        ref.watch(downloadRecordCountProvider).asData?.value ?? 0;
    final deleting = useState(false);

    final deleteAllDownloads = useCallback(() async {
      if (deleting.value) return;
      deleting.value = true;
      try {
        await showDeleteDownloadsDialog(context, ref);
      } finally {
        deleting.value = false;
      }
    }, [context, ref, deleting]);

    final actions = <Widget>[
      Button.outline(
        onPressed:
            downloadQueue.isEmpty ? null : downloadManagerNotifier.clearAll,
        child: Text(context.l10n.cancel_all),
      ),
      Button.destructive(
        leading: const Icon(SpotubeIcons.trash),
        onPressed:
            downloadCount == 0 || deleting.value ? null : deleteAllDownloads,
        child: Text(context.l10n.delete_all_downloads),
      ),
    ];

    final mediaQuery = MediaQuery.sizeOf(context);
    final title = AutoSizeText(
      context.l10n.currently_downloading(downloadQueue.length),
      maxLines: 1,
    ).semiBold();

    return ThemePageContent(
      slot: 'downloads.content',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      bindings: {
        'downloads.items': downloadQueue,
        'downloads.count': downloadQueue.length,
      },
      fallback: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            // Phones get the actions on their own line so two long labels
            // never squeeze the queue title or overflow the header.
            child: mediaQuery.smAndDown
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      title,
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ],
                  )
                : Row(
                    spacing: 8,
                    children: [
                      Expanded(child: title),
                      ...actions,
                    ],
                  ),
          ),
          Expanded(
            child: SafeArea(
              child: ListView.builder(
                itemCount: downloadQueue.length,
                padding: const EdgeInsets.only(bottom: 200),
                itemBuilder: (context, index) {
                  return DownloadItem(
                    task: downloadQueue.elementAt(index),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
