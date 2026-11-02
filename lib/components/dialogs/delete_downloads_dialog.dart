import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/download_wipe_provider.dart';
import 'package:spotube/services/downloads/local_library_wipe.dart';
import 'package:spotube/services/logger/logger.dart';

/// Confirms and then deletes every downloaded file the app owns.
///
/// Only the download root and the music cache are touched; folders the user
/// added to the local library are excluded by [planDownloadWipe]. Returns true
/// when a wipe actually ran.
Future<bool> showDeleteDownloadsDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final wiper = ref.read(downloadWiperProvider);
  final plan = await wiper.plan();

  if (!context.mounted) return false;

  if (plan.files.isEmpty && !plan.hasRecords) {
    showToast(
      context: context,
      builder: (context, overlay) =>
          Text(context.l10n.delete_local_library_nothing_to_delete),
    );
    return false;
  }

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.delete_all_downloads),
      content: Text(
        context.l10n.delete_local_library_confirmation(
          plan.files.length,
          formatByteTotal(plan.bytes),
        ),
      ),
      actions: [
        Button.outline(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.decline),
        ),
        Button.destructive(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.accept),
        ),
      ],
    ),
  );

  if (accepted != true) return false;

  try {
    final undeletable = await wiper.wipe(plan);
    if (context.mounted) {
      showToast(
        context: context,
        builder: (context, overlay) {
          final message = undeletable == 0
              ? context.l10n.deleted_local_library(plan.files.length)
              : context.l10n.deleted_local_library_with_failures(
                  plan.files.length,
                  undeletable,
                );
          return SurfaceCard(
            child: Basic(content: Text(message)),
          );
        },
      );
    }
    return true;
  } catch (e, stack) {
    AppLogger.reportError(e, stack);
    if (context.mounted) {
      showToast(
        context: context,
        builder: (context, overlay) => SurfaceCard(
          child: Text(context.l10n.something_went_wrong),
        ),
      );
    }
    return false;
  }
}
