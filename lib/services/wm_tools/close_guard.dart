import 'package:window_manager/window_manager.dart';

/// Coordinates the desktop close button with the startup step that installs
/// close interception.
///
/// `setPreventClose(true)` belongs to the unawaited desktop startup step so it
/// cannot delay the first frame, but it must land before the window is shown:
/// a close in that gap destroys the window without ever running
/// `useCloseBehavior`, so minimize-to-tray silently turns into "quit". The
/// window manager awaits [ready] before `waitUntilReadyToShow`, and the close
/// handler awaits it before acting.
class CloseGuard {
  CloseGuard({Future<void> Function()? install})
      : _install = install ?? _installPreventClose;

  /// The process-wide guard used by the window manager and the close handler.
  static final CloseGuard instance = CloseGuard();

  static Future<void> _installPreventClose() =>
      windowManager.setPreventClose(true);

  final Future<void> Function() _install;
  Future<void>? _pending;

  /// Runs the installer once per process; concurrent callers share it.
  Future<void> ensureInstalled() => _pending ??= _install();

  /// Completes once interception is installed, whether it succeeded or not.
  ///
  /// A failed install has nothing left to wait for — the OS closes the window
  /// itself and the handler is never called — so the error is swallowed here
  /// rather than thrown into a close callback. The startup step that first
  /// calls [ensureInstalled] still reports the failure.
  Future<void> get ready async {
    try {
      await ensureInstalled();
    } catch (_) {
      // See the doc comment: best-effort by design.
    }
  }
}
