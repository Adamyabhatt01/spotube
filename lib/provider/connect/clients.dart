import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/device_info/device_info.dart';
import 'package:spotube/services/logger/logger.dart';

class ConnectClientsState {
  final List<BonsoirService> services;
  final BonsoirService? resolvedService;

  /// Null while `enableConnect` is off: no `BonsoirDiscovery` is even
  /// constructed, so the mDNS browser does not exist and no multicast
  /// browsing runs for a feature the user switched off. Consumers must
  /// treat null as "discovery unavailable"; only [resolveService] ever
  /// needed the guard, and it is unreachable while the list is empty.
  final BonsoirDiscovery? discovery;

  ConnectClientsState({
    required this.services,
    required this.discovery,
    this.resolvedService,
  });

  ConnectClientsState copyWith({
    List<BonsoirService>? services,
    BonsoirDiscovery? discovery,
    BonsoirService? resolvedService,
  }) {
    return ConnectClientsState(
      services: services ?? this.services,
      discovery: discovery ?? this.discovery,
      resolvedService: resolvedService ?? this.resolvedService,
    );
  }
}

class ConnectClientsNotifier extends AsyncNotifier<ConnectClientsState> {
  ConnectClientsNotifier();

  @override
  build() async {
    // R-05: the broadcast side (bonsoir.dart) always honored `enableConnect`;
    // discovery never checked it, so multicast browsing ran the whole session
    // even with Connect off. Watching here means a toggle rebuilds the
    // provider: [ref.onDispose] of the previous build stops the live browser
    // when switching off, and switching on constructs a fresh discovery.
    final enabled = ref.watch(
      userPreferencesProvider.select((s) => s.enableConnect),
    );
    if (!enabled) {
      return ConnectClientsState(services: const [], discovery: null);
    }

    final discovery = BonsoirDiscovery(type: '_spotube._tcp');
    final deviceId = await DeviceInfoService.instance.deviceId();

    try {
      // bonsoir >=6: `ready` was renamed to `initialize()`. Failure here means
      // mDNS is unavailable on this machine (e.g. missing or misconfigured
      // avahi on Linux, dbus blocked). Degrade to an empty state instead of
      // erroring the provider, which would also poison `bonsoirProvider` via
      // its `selectAsync` rethrow and kill the whole Connect page.
      await discovery.initialize();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return ConnectClientsState(services: [], discovery: discovery);
    }

    // bonsoir >=6: `eventStream` only exists after `initialize()`, so the
    // subscription must be registered after it (unlike the old `ready` flow).
    final subscription = discovery.eventStream?.listen((event) {
      // ignore device itself
      try {
        if (event.service?.attributes["deviceId"] == deviceId) {
          return;
        }

        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            state = AsyncData(state.value!.copyWith(
              services: [
                ...?state.value?.services,
                event.service,
              ],
            ));
            break;
          case BonsoirDiscoveryServiceResolvedEvent():
            state = AsyncData(
              state.value!.copyWith(resolvedService: event.service),
            );
            break;
          case BonsoirDiscoveryServiceLostEvent():
            state = AsyncData(
              ConnectClientsState(
                services: state.value!.services
                    .where((s) => s.name != event.service.name)
                    .toList(),
                discovery: state.value!.discovery,
                resolvedService: state.value?.resolvedService != null &&
                        event.service.name ==
                            state.value?.resolvedService?.name
                    ? null
                    : state.value!.resolvedService,
              ),
            );
            break;
          default:
            break;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });

    ref.onDispose(() {
      subscription?.cancel();
      // bonsoir >=6 (linux): `stop()` dereferences the service browser that is
      // only created by `initialize()`, so skip it when initialization failed.
      if (discovery.isReady) {
        discovery.stop();
      }
    });

    try {
      await discovery.start();
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return ConnectClientsState(services: [], discovery: discovery);
    }

    return ConnectClientsState(
      services: [],
      discovery: discovery,
    );
  }

  Future<void> resolveService(BonsoirService service) async {
    final discovery = state.value?.discovery;
    if (discovery == null) return;
    // bonsoir >=6: resolution moved from `service.resolve()` to the
    // discovery's `ServiceResolver`; the resolved info arrives on the event
    // stream as a `BonsoirDiscoveryServiceResolvedEvent`.
    await discovery.serviceResolver.resolveService(service);
  }

  Future<void> clearResolvedService() async {
    if (state.value == null) return;
    state = AsyncData(
      ConnectClientsState(
        services: state.value!.services,
        discovery: state.value!.discovery,
      ),
    );
  }
}

final connectClientsProvider =
    AsyncNotifierProvider<ConnectClientsNotifier, ConnectClientsState>(
  () => ConnectClientsNotifier(),
);
