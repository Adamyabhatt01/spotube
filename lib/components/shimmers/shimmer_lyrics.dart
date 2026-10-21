import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'package:skeletonizer/skeletonizer.dart';

/// The lyrics page while the lyric fetch runs.
///
/// Widths are fractions of the page rather than lorem text because the text
/// never fitted: four words in a centered `Row` measured ~810px against a 393px
/// viewport, so every row overflowed and the loading screen drew error stripes
/// down its sides. A bone of a fraction of the width cannot overflow by
/// construction.
///
/// The row count follows the viewport instead of being a fixed 30. This list is
/// neither scrollable nor given a bounded height, so `shrinkWrap` makes it lay
/// out every item it is given - 30 rows on a phone that shows 27 is 3 rows of
/// layout and paint that no one can see.
class ShimmerLyrics extends StatelessWidget {
  const ShimmerLyrics({super.key});

  /// A lyric line plus its breathing room. Only used to turn the page height
  /// into a row count.
  static const _rowExtent = 32.0;

  /// Repeats every six rows so the block does not read as a stack of identical
  /// bars. Fixed per row: the previous version shuffled on every build, so a
  /// rebuild mid-fetch rearranged the skeleton the user was looking at.
  static const _widthFractions = [0.62, 0.38, 0.74, 0.5, 0.28, 0.66];

  @visibleForTesting
  static int rowsFor(Size size) =>
      (size.height / _rowExtent).ceil().clamp(1, _widthFractions.length * 8);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rows = rowsFor(size);

    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        itemCount: rows,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Bone.text(
                width: size.width * _widthFractions[index % _widthFractions.length],
              ),
            ),
          );
        },
      ),
    );
  }
}
