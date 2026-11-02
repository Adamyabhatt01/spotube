import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/provider/radio/state.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';

/// Play/pause/resume for a station, shared by the inline controls and the
/// card/tile context menu so both follow the same live-stream semantics.
void toggleRadioStationPlayback(
  WidgetRef ref,
  RadioStation station,
  RadioStationStatus status,
) {
  final controller = ref.read(radioPlaybackControllerProvider.notifier);
  _toggle(controller, station, status);
}

/// Container twin for menus, which resolve state on open rather than watch.
void toggleRadioStationPlaybackContainer(
  ProviderContainer container,
  RadioStation station,
  RadioStationStatus status,
) {
  final controller = container.read(radioPlaybackControllerProvider.notifier);
  _toggle(controller, station, status);
}

void _toggle(
  RadioPlaybackNotifier controller,
  RadioStation station,
  RadioStationStatus status,
) {
  if (!status.isActive) {
    controller.play(station);
  } else if (status.isPlaying) {
    controller.pause();
  } else {
    controller.resume();
  }
}

/// Toggles the sidebar pin, with a toast only when pinning.
void toggleRadioStationPin(
  BuildContext context,
  WidgetRef ref,
  RadioStation station,
) {
  final wasPinned = ref
      .read(userPreferencesProvider)
      .pinnedStationIds
      .contains(station.favoriteKey);
  ref
      .read(userPreferencesProvider.notifier)
      .togglePinnedStation(station.favoriteKey);
  _toastPinned(context, wasPinned);
}

/// Container twin for menus.
void toggleRadioStationPinContainer(
  BuildContext context,
  ProviderContainer container,
  RadioStation station,
) {
  final wasPinned = container
      .read(userPreferencesProvider)
      .pinnedStationIds
      .contains(station.favoriteKey);
  container
      .read(userPreferencesProvider.notifier)
      .togglePinnedStation(station.favoriteKey);
  _toastPinned(context, wasPinned);
}

void _toastPinned(BuildContext context, bool wasPinned) {
  if (!wasPinned && context.mounted) {
    showToast(
      context: context,
      builder: (context, overlay) {
        return SurfaceCard(
          child: Text(context.l10n.pinned_to_sidebar),
        );
      },
    );
  }
}
