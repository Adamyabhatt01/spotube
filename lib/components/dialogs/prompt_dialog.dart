import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';

Future<bool> showPromptDialog({
  required BuildContext context,
  required String title,
  required String message,
  String okText = "Ok",
  String? cancelText = "Cancel",
  bool destructive = false,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (cancelText != null)
            Button.outline(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                cancelText == "Cancel" ? context.l10n.cancel : cancelText,
              ),
            ),
          if (destructive)
            Button.destructive(
              child: Text(okText == "Ok" ? context.l10n.ok : okText),
              onPressed: () => Navigator.of(context).pop(true),
            )
          else
            Button.primary(
              child: Text(okText == "Ok" ? context.l10n.ok : okText),
              onPressed: () => Navigator.of(context).pop(true),
            ),
        ],
      );
    },
  ).then((value) => value ?? false);
}
