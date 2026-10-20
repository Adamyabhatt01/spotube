import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';
import 'package:spotube/models/radio/radio_station.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/radio/radio_station_tile.dart';

/// Home-style section header for the Radio page: an h4 title with an optional
/// trailing "See all" button.
///
/// Mirrors the header in `HorizontalPlaybuttonCardView` (same padding, row and
/// title style) so Browse and Radio read as one app instead of two designs.
class RadioSectionHeader extends StatelessWidget {
  const RadioSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
  });

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: DefaultTextStyle(
                  style: context.theme.typography.h4.copyWith(
                    color: context.theme.colorScheme.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Text(title),
                ),
              ),
              if (onSeeAll != null)
                Button.text(
                  onPressed: onSeeAll,
                  child: const Text('See all'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal station-card rail under a [RadioSectionHeader].
///
/// Cards are the shared [RadioStationCard] at its fixed grid width, separated
/// by the theme gutter — the same geometry the paged grid below uses, so a
/// station looks identical in both. An empty list renders nothing (Home's
/// rails guard the same way), so empty library sections never leave a bare
/// header behind.
class RadioStationRail extends StatelessWidget {
  const RadioStationRail({
    super.key,
    required this.title,
    required this.stations,
    this.onSeeAll,
  });

  final String title;
  final List<RadioStation> stations;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (stations.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioSectionHeader(title: title, onSeeAll: onSeeAll),
        SizedBox(
          height: context.gridCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: stations.length,
            separatorBuilder: (_, __) => Gap(context.layoutGutter),
            itemBuilder: (context, index) =>
                RadioStationCard(station: stations[index]),
          ),
        ),
      ],
    );
  }
}
