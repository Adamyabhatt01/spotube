import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/components/image/universal_image.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';

/// Resolves the background image for the active [ThemeBackground] spec.
///
/// Returns null when there is nothing to render:
/// - no plugin theme or source is [ThemeBackgroundSource.none]
/// - source is [ThemeBackgroundSource.shell] but the host shell source
///   has no background available
/// - source is albumArt but there is no active track art
final themeBackgroundImageProvider = Provider<ImageProvider?>((ref) {
  // Re-resolves the path when the shell reports a possible wallpaper
  // change, without touching the rest of the theme.
  ref.watch(shellBackgroundSignalProvider);

  final source = ref.watch(
    themeDefinitionProvider.select((s) => s.asData?.value?.background.source),
  );

  if (source == null || source == ThemeBackgroundSource.none) return null;

  if (source == ThemeBackgroundSource.shell) {
    final path = ref.watch(themeShellSourceProvider).getBackgroundPath();
    if (path == null) return null;
    return UniversalImage.imageProvider(path);
  }

  final images = ref.watch(
    audioPlayerProvider.select((s) => s.activeTrack?.album.images),
  );
  if (images == null || images.isEmpty) return null;

  return UniversalImage.imageProvider(
    images.asUrlString(
      index: images.length - 1,
      placeholder: ImagePlaceholder.albumArt,
    ),
  );
});
