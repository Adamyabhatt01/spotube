import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_std/hetu_std.dart';
import 'package:spotube/utils/platform.dart';

class MetadataAuthEndpoint {
  final Hetu hetu;

  MetadataAuthEndpoint(this.hetu);

  Stream get authStateStream =>
      hetu.eval("metadataPlugin.auth.authStateStream");

  Future<void> authenticate() async {
    await hetu.eval("metadataPlugin.auth.authenticate()");
  }

  bool isAuthenticated() {
    return hetu.eval("metadataPlugin.auth.isAuthenticated()") as bool;
  }

  /// Re-mints the access token from the stored cookies.
  ///
  /// A 401 means the token was rejected — which happens before its stated
  /// expiry, so the plugin's own refresh timer does not fire and the app
  /// would stay 401-ing until the user signed in again. The cookies may
  /// still be good, and a fresh token from them is a far better answer.
  ///
  /// Throws when the refresh fails: the caller then falls back to telling
  /// the user that the session expired.
  Future<void> refresh() async {
    await hetu.eval("metadataPlugin.auth.refresh()");
  }

  /// Whether the plugin has finished reading its stored credentials.
  ///
  /// Until it has, `isAuthenticated()` answers false — and that means "not
  /// known yet", not "signed out". The two have to be told apart: publishing
  /// "signed out" and correcting it a moment later makes every watcher of
  /// the answer rebuild, and a rebuild of the saved lists re-reads the whole
  /// library for nothing.
  bool isCredentialsLoaded() {
    try {
      return hetu.eval("metadataPlugin.auth.isLoaded()") as bool;
    } catch (_) {
      // A plugin without the answer is an older kernel: it cannot say, and
      // its `isAuthenticated()` is the only thing left to go on.
      return true;
    }
  }

  Future<void> logout() async {
    await hetu.eval("metadataPlugin.auth.logout()");
    if (kIsMobile) {
      WebStorageManager.instance().deleteAllData();
      CookieManager.instance().deleteAllCookies();
    }
    if (kIsDesktop) {
      await WebviewWindow.clearAll();
    }
  }
}
