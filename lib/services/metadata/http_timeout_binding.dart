import 'package:hetu_script/external/external_class.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_std/http/http.dart';
import 'package:hetu_std/http/http.binding.dart';

/// The timeouts applied to plugin HTTP clients that declare none.
///
/// `hetu_std`'s `HttpClient` passes `null` timeouts through to `Dio`
/// whenever the plugin's `HttpBaseOptions` leaves them unset — and Dio
/// treats null as "wait forever". A plugin that omits them (or constructs
/// a bare `HttpBaseOptions()`) therefore hangs a request until the OS
/// gives up, with no timeout error for the host or the plugin to react
/// to. These are the defaults the binding fills in for exactly that
/// case; an explicit plugin value always wins.
class PluginHttpTimeouts {
  const PluginHttpTimeouts({
    this.connectSeconds = 20,
    this.receiveSeconds = 30,
    this.sendSeconds = 30,
  });

  /// Time to establish the connection.
  final int connectSeconds;

  /// Time to receive the response body.
  final int receiveSeconds;

  /// Time to send the request body.
  final int sendSeconds;
}

/// The production defaults: generous for metadata APIs, finite always.
const defaultPluginHttpTimeouts = PluginHttpTimeouts();

/// A copy of [options] with its timeout fields defaulted.
///
/// The timeouts are in seconds, matching `HttpBaseOptions` (which the
/// std binding converts with `Duration(seconds: …)`).
HttpBaseOptions applyPluginHttpTimeoutDefaults(
  HttpBaseOptions? options, {
  PluginHttpTimeouts timeouts = defaultPluginHttpTimeouts,
}) {
  return HttpBaseOptions(
    baseUrl: options?.baseUrl,
    connectTimeout: options?.connectTimeout ?? timeouts.connectSeconds,
    receiveTimeout: options?.receiveTimeout ?? timeouts.receiveSeconds,
    sendTimeout: options?.sendTimeout ?? timeouts.sendSeconds,
    followRedirects: options?.followRedirects,
    validateStatus: options?.validateStatus,
    headers: options?.headers,
    queryParameters: options?.queryParameters,
  );
}

/// An `HttpClient` external class binding that fills in timeout defaults.
///
/// Installed with `override: true` right after
/// `HetuStdLoader.loadBindings`, so every plugin VM's `HttpClient` gets
/// finite timeouts without the pinned `hetu_std` package changing a line.
/// Member access (request/head/get/post/…) is delegated to the upstream
/// binding untouched — only construction changes.
class TimeoutDefaultsHttpClientBinding extends HTExternalClass {
  TimeoutDefaultsHttpClientBinding({
    this.timeouts = defaultPluginHttpTimeouts,
  }) : super('HttpClient');

  final PluginHttpTimeouts timeouts;

  static final _upstream = HttpClientClassBinding();

  @override
  dynamic memberGet(String varName, {String? from}) {
    switch (varName) {
      case 'HttpClient':
        return (HTEntity entity, {positionalArgs, namedArgs, typeArgs}) {
          final HttpBaseOptions? raw = positionalArgs.isEmpty
              ? null
              : positionalArgs[0] as HttpBaseOptions?;
          return HttpClient(
            applyPluginHttpTimeoutDefaults(raw, timeouts: timeouts),
          );
        };
      default:
        return _upstream.memberGet(varName, from: from);
    }
  }

  @override
  dynamic instanceMemberGet(dynamic object, String varName) =>
      _upstream.instanceMemberGet(object, varName);
}

/// Replaces the stdlib `HttpClient` binding with the timeout-defaulting one.
///
/// Call after `HetuStdLoader.loadBindings(hetu)`. `override: true` replaces
/// the registration by name, so a changed upstream layout simply installs
/// ours (which delegates member access to a fresh upstream binding for the
/// same Dart classes).
void bindPluginHttpTimeoutDefaults(
  Hetu hetu, {
  PluginHttpTimeouts timeouts = defaultPluginHttpTimeouts,
}) {
  hetu.interpreter.bindExternalClass(
    TimeoutDefaultsHttpClientBinding(timeouts: timeouts),
    override: true,
  );
}
