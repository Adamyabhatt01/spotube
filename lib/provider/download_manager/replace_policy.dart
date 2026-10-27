import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/components/dialogs/replace_downloaded_dialog.dart';
import 'package:spotube/models/metadata/metadata.dart';

/// Resolves whether already-downloaded files should be replaced.
///
/// Asked at most once per decision: the answer is stored in
/// [replaceDownloadedFileState], so the bulk prefilter and the per-track
/// safety net share a single user decision. Concurrent callers await the same
/// completer instead of being answered `false` behind the user's back — the
/// decision, once made, is every waiter's answer.
class ReplacePolicyGate {
  final Ref ref;

  /// Set while the replace-file dialog is open.
  Completer<bool>? _inFlight;

  ReplacePolicyGate(this.ref);

  Future<bool> resolve(SpotubeTrackObject track) async {
    final replaceAll = ref.read(replaceDownloadedFileState);
    if (replaceAll != null) return replaceAll;
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight.future;
    if (rootNavigatorKey.currentContext == null) {
      return false;
    }
    final completer = _inFlight = Completer<bool>();
    try {
      final answer = await showDialog<bool>(
            context: rootNavigatorKey.currentContext!,
            builder: (context) => ReplaceDownloadedDialog(
              track: track,
            ),
          ) ??
          false;
      completer.complete(answer);
      return answer;
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.complete(false);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _inFlight = null;
    }
  }
}
