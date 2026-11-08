// PR 3 / R-05: mDNS discovery runs only while `enableConnect` is on.
//
// The broadcast side always honored the preference; the discovery side never
// checked it, so a session with Connect off still multicast-browsed
// `_spotube._tcp` forever. The seam is `BonsoirPlatformInterface.instance`:
// `BonsoirDiscovery`'s factory asks it for the platform action, so a fake
// platform counts creations/initialize/start/stop without any real mDNS.
// `deviceId()` uses device_info_plus' own Linux implementation, which reads
// /etc/os-release and /etc/machine-id directly.

import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:bonsoir_platform_interface/bonsoir_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/provider/connect/clients.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/logger/logger.dart';

import 'support/common_fakes.dart';

class _FakeDiscoveryAction implements BonsoirAction<BonsoirDiscoveryEvent> {
  int initializeCount = 0;
  int startCount = 0;
  int stopCount = 0;
  bool _ready = false;

  final _events = StreamController<BonsoirDiscoveryEvent>.broadcast();

  @override
  Stream<BonsoirDiscoveryEvent>? get eventStream => _events.stream;

  @override
  Future<void> initialize() async {
    initializeCount++;
    _ready = true;
  }

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  @override
  bool get isReady => _ready;

  @override
  bool get isStopped => stopCount > 0;
}

class _FakeBonsoirPlatform extends BonsoirPlatformInterface {
  final actions = <_FakeDiscoveryAction>[];

  @override
  BonsoirAction<BonsoirDiscoveryEvent> createDiscoveryAction(
    String type, {
    bool printLogs = false,
  }) {
    final action = _FakeDiscoveryAction();
    actions.add(action);
    return action;
  }

  @override
  BonsoirAction<BonsoirBroadcastEvent> createBroadcastAction(
    BonsoirService service, {
    bool printLogs = false,
  }) {
    throw UnimplementedError('discovery gating never broadcasts');
  }
}

void main() {
  AppLogger.initialize(false);

  late _FakeBonsoirPlatform platform;
  late StubPrefsNotifier prefs;
  late ProviderContainer container;

  setUp(() {
    platform = _FakeBonsoirPlatform();
    BonsoirPlatformInterface.instance = platform;
    DeviceInfoPlatform.instance = DeviceInfoPlusLinuxPlugin();
    prefs = StubPrefsNotifier(PreferencesTable.defaults());
    container = ProviderContainer(
      overrides: [
        userPreferencesProvider.overrideWith(() => prefs),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ConnectClientsState> readState() =>
      container.read(connectClientsProvider.future);

  test('off: no discovery object is created at all', () async {
    final state = await readState();

    expect(state.discovery, isNull);
    expect(state.services, isEmpty);
    expect(state.resolvedService, isNull);
    expect(platform.actions, isEmpty);
  });

  test('on: discovery is created, initialized and started', () async {
    prefs.stub = prefs.stub.copyWith(enableConnect: true);

    final state = await readState();

    expect(state.discovery, isNotNull);
    expect(platform.actions, hasLength(1));
    expect(platform.actions.single.initializeCount, 1);
    expect(platform.actions.single.startCount, 1);
  });

  test('toggle off stops the live browser; toggle on starts a fresh one',
      () async {
    // Initialize the prefs notifier before setting state on it.
    container.read(userPreferencesProvider);
    prefs.state = prefs.stub.copyWith(enableConnect: true);
    await readState();
    expect(platform.actions, hasLength(1));

    prefs.state = prefs.stub.copyWith(enableConnect: false);
    final disabled = await readState();
    expect(disabled.discovery, isNull);
    expect(platform.actions.single.stopCount, 1);
    expect(platform.actions, hasLength(1),
        reason: 'nothing new is constructed');

    prefs.state = prefs.stub.copyWith(enableConnect: true);
    await readState();
    expect(platform.actions, hasLength(2));
    expect(platform.actions[1].startCount, 1);
    // The stopped browser stays stopped — it is not resurrected by the
    // second enable.
    expect(platform.actions[0].stopCount, 1);
  });
}
