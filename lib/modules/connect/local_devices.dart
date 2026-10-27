import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/ui/button_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/audio_player/audio_player_port.dart';

class ConnectPageLocalDevices extends HookConsumerWidget {
  const ConnectPageLocalDevices({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData(:typography) = Theme.of(context);
    final player = ref.read(audioPlayerPortProvider);
    // `devices`/`selectedDevice` are async getters: every build made a new
    // Future, so useFuture saw a changed future on every rebuild triggered
    // by its own resolution — the same instance-churn storm the music-cache
    // dir site had. Memoize one future per element; the streams below are
    // the live source anyway (these are just their pre-first-event
    // fallbacks).
    final devicesFuture = useFuture(useMemoized(() => player.devices));
    final devicesStream = useStream(player.devicesStream);
    final selectedDeviceFuture =
        useFuture(useMemoized(() => player.selectedDevice));
    final selectedDeviceStream = useStream(player.selectedDeviceStream);

    final devices = devicesStream.data ?? devicesFuture.data;
    final selectedDevice =
        selectedDeviceStream.data ?? selectedDeviceFuture.data;

    if (devices == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        const SliverGap(10),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          sliver: SliverToBoxAdapter(
            child: Text(
              context.l10n.this_device,
              style: typography.bold,
            ),
          ),
        ),
        const SliverGap(10),
        SliverList.separated(
          itemCount: devices.length,
          separatorBuilder: (context, index) => const Gap(10),
          itemBuilder: (context, index) {
            final device = devices[index];

            return ButtonTile(
              selected: selectedDevice == device,
              onPressed: () => player.setAudioDevice(device),
              leading: const Icon(SpotubeIcons.speaker),
              title: Text(device.description),
              subtitle: Text(device.name),
            );
          },
        ),
        const SliverGap(200)
      ],
    );
  }
}
