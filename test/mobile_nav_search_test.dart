import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/collections/side_bar_tiles.dart';
import 'package:spotube/l10n/generated/app_localizations_en.dart';
import 'package:spotube/models/database/database.dart';

/// The mobile bottom bar carries search again (like before the Search page
/// removal): home → search → radio → library → stats. The Search tab is the
/// only mobile search entry — Home and Radio hide their inline rows wherever
/// this bar is visible ([isBottomNavVisible] mirrors the bar's own gate).
void main() {
  test('navbar order is home, search, radio, library, stats', () {
    final ids =
        getNavbarTileList(AppLocalizationsEn()).map((t) => t.id).toList();
    expect(ids, ['home', 'search', 'radio', 'library', 'stats']);
  });

  test('search tile points at the search route', () {
    final tile = getNavbarTileList(AppLocalizationsEn())
        .firstWhere((t) => t.id == 'search');
    expect(tile.pathPrefix, '/search');
    expect(tile.title, 'Search');
  });

  test('bottom bar visibility mirrors SpotubeNavigationBar gate', () {
    const compact = LayoutMode.compact;
    const extended = LayoutMode.extended;
    const adaptive = LayoutMode.adaptive;
    // Compact always shows the bar.
    expect(isBottomNavVisible(const Size(390, 844), compact), isTrue);
    expect(isBottomNavVisible(const Size(1920, 1080), compact), isTrue);
    // Extended never does (sidebar owns navigation).
    expect(isBottomNavVisible(const Size(390, 844), extended), isFalse);
    // Adaptive follows width: sidebar from md up, bar below.
    expect(isBottomNavVisible(const Size(390, 844), adaptive), isTrue);
    expect(isBottomNavVisible(const Size(1920, 1080), adaptive), isFalse);
  });
}
