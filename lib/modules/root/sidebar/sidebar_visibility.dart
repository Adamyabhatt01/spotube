import 'package:flutter/widgets.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/models/database/database.dart';

/// Whether the shell draws the sidebar at this size.
///
/// Mirrors the early return in `Sidebar.build`, named once so pages can ask
/// the same question without importing the sidebar tree. The Playlists page
/// uses it to decide whether pinned playlists need to rank first: with a
/// sidebar they already have a home, so the page keeps its plain order.
bool sidebarVisibleOf(BuildContext context, LayoutMode layoutMode) {
  if (layoutMode == LayoutMode.compact) return false;
  return !(MediaQuery.sizeOf(context).smAndDown &&
      layoutMode == LayoutMode.adaptive);
}
