import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/logger/logger.dart';

class ConnectionCheckerService {
  final _connectionStreamController = StreamController<bool>.broadcast();
  final Dio dio;
  Timer? _periodicTimer;

  /// Seam for tests: resolution goes through this field so a probe can be
  /// driven without real DNS.
  @visibleForTesting
  Future<List<InternetAddress>> Function(String host) lookup =
      InternetAddress.lookup;

  /// The two subscriptions the constructor opens. Nothing cancels them
  /// today, which is invisible for a process-lifetime singleton but keeps
  /// [dispose] from actually being a shutdown.
  StreamSubscription<bool>? _ownStateSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static final _instance = ConnectionCheckerService._();

  static ConnectionCheckerService get instance => _instance;

  /// The 30 s retry probe has no audience while the app is backgrounded:
  /// `paused` and `hidden` both skip it (hidden — occluded window on
  /// desktop, stopped-but-cached task on Android — was the gap). Every
  /// other state, including `inactive` and `null`, keeps probing exactly
  /// as before.
  @visibleForTesting
  static bool probeSkipsState(AppLifecycleState? state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden;

  static Dio _defaultDio() => Dio(
        // A probe with no ceiling can hold a 30 s retry loop hostage:
        // default-connect timeouts are OS-dependent (minutes), and every
        // connectivity event would then pile another probe on top.
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  /// A service with no probe wiring — just the ceiling-carrying [dio] and the
  /// [lookup] seam — so the single-flight and timeout behavior is testable
  /// without the plugin-backed constructor side effects.
  @visibleForTesting
  ConnectionCheckerService.forTesting({Dio? dio})
      : dio = dio ?? _defaultDio();

  ConnectionCheckerService._() : dio = _defaultDio() {
    _start();
  }

  void _start() {
    _ownStateSubscription =
        onConnectivityChanged.listen((connected) {
      try {
        if (!connected && _periodicTimer == null) {
          _periodicTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
            if (probeSkipsState(WidgetsBinding.instance.lifecycleState)) {
              return;
            }
            await isConnected;
          });
        } else {
          _periodicTimer?.cancel();
          _periodicTimer = null;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((event) async {
      await isConnected;
    });
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _ownStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _connectionStreamController.close();
  }

  final vpnNames = [
    'tun',
    'tap',
    'ppp',
    'pptp',
    'l2tp',
    'ipsec',
    'vpn',
    'wireguard',
    'openvpn',
    'softether',
    'proton',
    'strongswan',
    'cisco',
    'forticlient',
    'fortinet',
    'hideme',
    'hidemy',
    'hideman',
    'hidester',
    'lightway',
  ];

  Future<bool> isVpnActive() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.any,
    );

    if (interfaces.isEmpty) {
      return false;
    }

    return interfaces.any(
      (interface) => vpnNames.any(
        (name) => interface.name.toLowerCase().contains(name),
      ),
    );
  }

  Future<bool> doesConnectTo(String address) async {
    try {
      final result = await lookup(address).timeout(
        const Duration(seconds: 5),
        onTimeout: () => const [],
      );
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
      return false;
    } on SocketException catch (_) {
      try {
        final response = await dio.head('https://$address');
        return (response.statusCode ?? 500) <= 400;
      } on DioException catch (_) {
        return false;
      }
    }
  }

  Future<bool> _isConnected() async {
    return await doesConnectTo('google.com') ||
        await doesConnectTo('www.baidu.com') || // for China
        await isVpnActive();
  }

  bool isConnectedSync = true;

  /// In-flight probe, if any. Connectivity floods and the 30 s retry timer
  /// used to start overlapping probes whenever one outran its ceiling;
  /// concurrent callers now piggyback on the single running probe instead.
  Future<bool>? _probing;

  Future<bool> get isConnected {
    return _probing ??= _probe().whenComplete(() => _probing = null);
  }

  Future<bool> _probe() async {
    final connected = await _isConnected();
    if (connected != isConnectedSync) {
      _connectionStreamController.add(connected);
    }
    isConnectedSync = connected;
    return connected;
  }

  Stream<bool> get onConnectivityChanged => _connectionStreamController.stream;
}

/// Latest connectivity answer the service has committed to. Warm-started from
/// the singleton so a page that mounts already-online does not flicker, then
/// tracks every probe that changes the answer.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  yield ConnectionCheckerService.instance.isConnectedSync;
  yield* ConnectionCheckerService.instance.onConnectivityChanged;
});

/// Whether the network is up right now.
///
/// The synchronous answer the service already holds, behind a provider so a
/// unit test can stand in for it: the real service opens a platform channel
/// when it is first touched, which a test process has no binding for.
final networkAvailableProvider = Provider<bool>(
  (ref) => ConnectionCheckerService.instance.isConnectedSync,
);
