import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:spotube/services/logger/logger.dart';

class ConnectionCheckerService {
  final _connectionStreamController = StreamController<bool>.broadcast();
  final Dio dio;
  Timer? _periodicTimer;

  /// The two subscriptions the constructor opens. Nothing cancels them
  /// today, which is invisible for a process-lifetime singleton but keeps
  /// [dispose] from actually being a shutdown.
  StreamSubscription<bool>? _ownStateSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  static final _instance = ConnectionCheckerService._();

  static ConnectionCheckerService get instance => _instance;

  ConnectionCheckerService._() : dio = Dio() {
    _ownStateSubscription =
        onConnectivityChanged.listen((connected) {
      try {
        if (!connected && _periodicTimer == null) {
          _periodicTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
            if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.paused) {
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
      final result = await InternetAddress.lookup(address);
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

  Future<bool> get isConnected async {
    final connected = await _isConnected();
    if (connected != isConnectedSync) {
      _connectionStreamController.add(connected);
    }
    isConnectedSync = connected;
    return connected;
  }

  Stream<bool> get onConnectivityChanged => _connectionStreamController.stream;
}
