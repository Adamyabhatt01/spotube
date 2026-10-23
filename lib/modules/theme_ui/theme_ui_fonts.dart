import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';

/// Fonts already handed to Flutter, keyed by family and file.
///
/// [FontLoader] has no unload and registering the same bytes twice is waste,
/// so process-wide deduplication is the right scope: a widget rebuild, a
/// theme refresh or a second slot must not register a font again.
final _loadedFonts = <String>{};

/// Loads the TTF/OTF files the active theme ships under the family names its
/// styles reference.
///
/// Resolution goes through [ThemeUiAssets], so a family can only point at a
/// file inside the extracted plugin directory. Loading is best-effort: a
/// missing or corrupt font leaves the text on the host fallback instead of
/// making the theme unusable. Widgets that use the family watch this provider
/// so they repaint once the faces are available.
final themeUiFontsProvider = FutureProvider<void>((ref) async {
  final definition = await ref.watch(themeDefinitionProvider.future);
  final assets = await ref.watch(themeUiAssetsProvider.future);
  if (definition == null) return;

  final fonts = definition.typography['fonts'];
  if (fonts is! List) return;

  for (final entry in fonts.take(8)) {
    if (entry is! Map) continue;
    final family = _family(entry['family']);
    final asset = assets
        .resolve(entry['asset'] is String ? entry['asset'] as String : null);
    if (family == null || asset == null) continue;

    final key = '$family\u0000${asset.path}';
    if (!_loadedFonts.add(key)) continue;

    try {
      final bytes = await asset.readAsBytes();
      if (bytes.isEmpty) {
        _loadedFonts.remove(key);
        continue;
      }
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    } catch (e, stack) {
      _loadedFonts.remove(key);
      AppLogger.reportError(e, stack, 'themeUiFontsProvider');
    }
  }
});

String? _family(Object? raw) {
  if (raw is! String) return null;
  final family = raw.trim();
  if (family.isEmpty || family.length > 64) return null;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$').hasMatch(family)) return null;
  return family;
}

/// Test seam: font registration is process-wide, so tests that inspect the
/// loader need a clean slate between cases.
void resetThemeUiFontCacheForTest() => _loadedFonts.clear();
