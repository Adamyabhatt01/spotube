# Vendored `desktop_webview_window`

Upstream: <https://github.com/KRTirtho/flutter-plugins>, path
`packages/desktop_webview_window`, pinned at
`f261ff20e310d05713249b21c199a9fe17a3de6f`.

This copy exists for one reason: on Linux the package opens a second
`FlDartProject` / `FlView` for the webview title bar. Destroying that window
while the main engine is running corrupts the shared GL state on Flutter 3.38
(`FlutterEngineRemoveView ... The implicit view cannot be removed`, followed by
a SIGSEGV in `gdk_cairo_draw_from_gl`). The Spotify login flow closes the
webview as soon as it captures the cookies, so every desktop login crashed the
app.

## Local changes (Linux only)

`linux/webview_window.cc`:

1. `WebviewWindow::Close()` calls `gtk_widget_hide()` instead of
   `gtk_window_close()`, so the secondary view is never torn down while the
   main engine is alive.
2. A `delete-event` handler hides the window and returns `TRUE`, so the
   window-manager close button cannot destroy the view either.
3. The `destroy` handler forwards `onWindowClose` to Dart before invoking the
   close callback. The callback erases the wrapper, so calling it first was a
   use-after-free.

Everything else is untouched upstream code. Re-apply these three patches if
the vendored version is ever refreshed.
