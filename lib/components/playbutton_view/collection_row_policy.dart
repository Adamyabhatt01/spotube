import 'package:flutter/foundation.dart';

/// The visibility and style policy for one collection row (playlist, album,
/// or compact artist tile), as a theme may override it through
/// `library.playlists`, `library.pins`, `library.albums`, or
/// `library.artists` host-widget props.
///
/// Defaults preserve the historical presentation: every trailing action is
/// rendered, the cover belongs to the row's navigation tap, the subtitle is
/// shown, and the cover keeps its host radius. A theme opts in to a denser,
/// Spotify-style row (hide the trailing buttons, make the cover play, drop
/// the subtitle, shrink the cover) without forking the widget.
@immutable
class CollectionRowPolicy {
  /// Render the pin/unpin trailing button. Playlists only.
  final bool showPin;

  /// Render the add-to-queue trailing button.
  final bool showQueue;

  /// Render the trailing play/pause button.
  final bool showPlay;

  /// Make the cover itself a play/pause hit target. Null preserves the
  /// row's navigation tap.
  final bool coverPlays;

  /// Render the title line.
  ///
  /// A collapsed sidebar rail draws the cover alone; the title is the only
  /// thing that does not fit there.
  final bool showTitle;

  /// Render the description/subtitle line under the title.
  final bool showSubtitle;

  /// Row density: `standard` keeps the current padding, `compact` trades
  /// vertical padding for a denser list.
  final bool compactDensity;

  /// Cover edge in logical px. Null keeps the tile's default 50.
  final int? coverSize;

  /// Cover corner radius in logical px. Null keeps the host default.
  final int? coverRadius;

  const CollectionRowPolicy({
    this.showPin = true,
    this.showQueue = true,
    this.showPlay = true,
    this.coverPlays = false,
    this.showTitle = true,
    this.showSubtitle = true,
    this.compactDensity = false,
    this.coverSize,
    this.coverRadius,
  });

  /// Whether any trailing action is rendered at all.
  bool get hasActions => showPin || showQueue || showPlay;
}

/// Reads a [CollectionRowPolicy] out of a theme host-widget's `props` bag.
///
/// `showPin`/`showQueue`/`showPlay` default to `true` and `coverPlays`,
/// `showSubtitle`, `showDividers` default to the historical presentation,
/// so a theme that omits every new prop sees no change. Out-of-range counts
/// and unknown density values fall back rather than erroring: an installed
/// `.smplug` may have been authored against a different host.
CollectionRowPolicy collectionRowPolicyFromProps(Map<String, dynamic> props) {
  bool boolProp(String key, bool fallback) {
    final raw = props[key];
    return raw is bool ? raw : fallback;
  }

  int? intProp(String key, int min, int max) {
    final raw = props[key];
    if (raw is! num || !raw.isFinite) return null;
    return raw.round().clamp(min, max);
  }

  return CollectionRowPolicy(
    showPin: boolProp('showPin', true),
    showQueue: boolProp('showQueue', true),
    showPlay: boolProp('showPlay', true),
    coverPlays: boolProp('coverPlays', false),
    showTitle: boolProp('showTitle', true),
    showSubtitle: boolProp('showSubtitle', true),
    compactDensity: props['density'] == 'compact',
    coverSize: intProp('coverSize', 32, 96),
    coverRadius: intProp('coverRadius', 0, 24),
  );
}

/// `showDividers` and `rowSpacing` describe the list, not a single row, so
/// the collection widgets read them separately from the row policy.
class CollectionListStyle {
  final bool showDividers;
  final int rowSpacing;

  const CollectionListStyle({
    this.showDividers = true,
    this.rowSpacing = 0,
  });
}

CollectionListStyle collectionListStyleFromProps(Map<String, dynamic> props) {
  final dividers = props['showDividers'];
  final spacing = props['rowSpacing'];
  return CollectionListStyle(
    showDividers: dividers is bool ? dividers : true,
    rowSpacing: spacing is num && spacing.isFinite
        ? spacing.round().clamp(0, 24)
        : 0,
  );
}
