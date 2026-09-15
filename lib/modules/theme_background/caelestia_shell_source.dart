import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_state.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_theme_source.dart';

/// [ThemeShellSource] backed by Caelestia's on-disk state.
///
/// Resolves `wallpaper/current` (a symlink to the live wallpaper) under
/// the state directory. Returns null when Caelestia isn't installed,
/// the link is missing/broken, or it doesn't point at a real file.
/// Only stat calls are made — image bytes are never read here.
class CaelestiaShellSource implements ThemeShellSource {
  /// Override for tests. Defaults to [caelestiaStateDir].
  final String? stateDir;

  const CaelestiaShellSource({this.stateDir});

  @override
  String? getBackgroundPath() {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return null;
      final current = File(
        p.join(stateDir, 'wallpaper', 'current'),
      );
      if (!current.existsSync() && !FileSystemEntity.isLinkSync(current.path)) {
        return null;
      }
      final resolved = current.resolveSymbolicLinksSync();
      if (!File(resolved).existsSync()) return null;
      return resolved;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ThemeDefinition?> getTheme() =>
      CaelestiaThemeSource(stateDir: stateDir).getTheme();

  /// Scheme file mtime: any Caelestia rewrite changes it, so a stale
  /// cache from before the rewrite never validates.
  @override
  String? get cacheKey {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return null;
      final scheme = File(p.join(stateDir, 'scheme.json'));
      if (!scheme.existsSync()) return null;
      return scheme.lastModifiedSync().millisecondsSinceEpoch.toString();
    } catch (_) {
      return null;
    }
  }

  /// Emits when `scheme.json` may have changed. Missing dir → silent.
  ///
  /// Watches the state directory (not the file itself): Caelestia saves
  /// atomically via temp-file + rename, which orphans a direct file
  /// watch after the first change. The rename surfaces as a move event
  /// whose *destination* is `scheme.json`, so both sides are matched.
  @override
  Stream<void> watchTheme() {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return const Stream.empty();
      final dir = Directory(stateDir);
      if (!dir.existsSync()) return const Stream.empty();
      return dir
          .watch()
          .where((event) {
            if (p.basename(event.path) == 'scheme.json') return true;
            final destination =
                event is FileSystemMoveEvent ? event.destination : null;
            return destination != null &&
                p.basename(destination) == 'scheme.json';
          })
          .map((_) {})
          .handleError((_) {});
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Emits when the wallpaper directory changes (symlink swaps appear
  /// as create/delete events). Missing dir → silent.
  @override
  Stream<void> watchBackground() {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return const Stream.empty();
      final dir = Directory(p.join(stateDir, 'wallpaper'));
      if (!dir.existsSync()) return const Stream.empty();
      return dir.watch().map((_) {}).handleError((_) {});
    } catch (_) {
      return const Stream.empty();
    }
  }
}
