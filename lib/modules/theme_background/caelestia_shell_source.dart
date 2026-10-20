import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_background/theme_shell_source.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_glass_config.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_state.dart';
import 'package:spotube/modules/theme_caelestia/caelestia_theme_source.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/debounced_writer.dart';

/// [ThemeShellSource] backed by Caelestia's on-disk state.
///
/// Resolves `wallpaper/current` (a symlink to the live wallpaper) under
/// the state directory. Returns null when Caelestia isn't installed,
/// the link is missing/broken, or it doesn't point at a real file.
/// Only stat calls are made — image bytes are never read here.
class CaelestiaShellSource implements ThemeShellSource {
  /// Override for tests. Defaults to [caelestiaStateDir].
  final String? stateDir;

  /// Override for tests. Defaults to [xdgConfigDir] — `foot/foot.ini` and
  /// `caelestia/shell.json` live under here, outside the state directory.
  final String? configDir;

  const CaelestiaShellSource({this.stateDir, this.configDir});

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

  /// Glass derived from what the desktop actually draws with: foot's
  /// translucency and the shell's transparency setting, veiled in the live
  /// scheme's `surface`. Null when any input is missing, which leaves the
  /// plugin's authored numbers in place.
  @override
  Future<ThemeGlass?> getGlass() async {
    try {
      final surface = await CaelestiaThemeSource(
        stateDir: stateDir,
      ).getSurface();
      if (surface == null) return null;

      return readDerivedGlass(
        surfaceHex: surface.hex,
        mode: surface.mode,
        configDir: configDir,
      );
    } catch (e, stackTrace) {
      AppLogger.reportError(e, stackTrace, 'CaelestiaShellSource.getGlass');
      return null;
    }
  }

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

  /// Emits when anything the resolved theme reads may have changed:
  /// `scheme.json` for the palette, `foot.ini`/`shell.json` for the glass.
  /// Missing dirs stay silent per source.
  ///
  /// Watches directories rather than files: every writer here saves
  /// atomically via temp-file + rename, which orphans a direct file watch
  /// after the first change. The rename surfaces as a move event whose
  /// *destination* is the real file, so both sides are matched.
  @override
  Stream<void> watchTheme() {
    final configRoot = xdgConfigDir(configDir);
    final sources = [
      _fileSignal(caelestiaStateDir(stateDir), 'scheme.json'),
      _fileSignal(
        configRoot == null ? null : p.join(configRoot, 'caelestia'),
        'shell.json',
      ),
      _fileSignal(
        configRoot == null ? null : p.join(configRoot, 'foot'),
        'foot.ini',
      ),
    ].nonNulls.toList();

    if (sources.isEmpty) return const Stream.empty();
    return _coalesceEvents(_mergeSignals(sources));
  }

  Stream<void>? _fileSignal(String? directory, String fileName) {
    try {
      if (directory == null) return null;
      final dir = Directory(directory);
      if (!dir.existsSync()) return null;
      return dir
          .watch()
          .where((event) {
            if (p.basename(event.path) == fileName) return true;
            final destination =
                event is FileSystemMoveEvent ? event.destination : null;
            return destination != null && p.basename(destination) == fileName;
          })
          .map((_) {})
          .handleError((_) {});
    } catch (_) {
      return null;
    }
  }

  /// Emits when the resolved wallpaper path actually differs from the last one
  /// seen — see [_distinctPathSignal] for why this watch is not debounced like
  /// [watchTheme]. Missing dir → silent.
  @override
  Stream<void> watchBackground() {
    try {
      final stateDir = caelestiaStateDir(this.stateDir);
      if (stateDir == null) return const Stream.empty();
      final dir = Directory(p.join(stateDir, 'wallpaper'));
      if (!dir.existsSync()) return const Stream.empty();
      return _distinctPathSignal(
        dir.watch().map((_) {}).handleError((_) {}),
        getBackgroundPath,
      );
    } catch (_) {
      return const Stream.empty();
    }
  }
}

const _themeEventWindow = Duration(milliseconds: 300);

/// How long a wallpaper has to stay unresolvable before that counts as a
/// removal rather than the hole between Caelestia's `unlink` and `symlink_to`.
const _removalGrace = _themeEventWindow;

/// Fans several silent watches into one stream.
///
/// Hand-rolled because `rxdart` is a transitive dependency only — merging
/// with it would mean promoting it into `pubspec.yaml` for eight lines.
Stream<void> _mergeSignals(List<Stream<void>> sources) {
  final controller = StreamController<void>();
  var subscriptions = <StreamSubscription<void>>[];

  controller.onListen = () {
    subscriptions = [
      for (final source in sources) source.listen(controller.add),
    ];
  };
  controller.onCancel = () async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  };
  return controller.stream;
}

/// Caelestia saves through temp-file + rename, so a single palette write
/// surfaces as several filesystem events and each raw one re-resolved the theme
/// and rebuilt the tree. A burst inside [_themeEventWindow] becomes one.
///
/// Theme only. The wallpaper cannot be handled this way — see
/// [_distinctPathSignal].
Stream<void> _coalesceEvents(Stream<void> source) {
  final controller = StreamController<void>();
  final debouncer = DebouncedWriter(_themeEventWindow, (error, stackTrace) {});
  StreamSubscription<void>? subscription;

  controller.onListen = () {
    subscription = source.listen((_) {
      debouncer(() async => controller.add(null));
    });
  };
  controller.onCancel = () async {
    debouncer.cancel();
    await subscription?.cancel();
  };
  return controller.stream;
}

/// Emits once per distinct value of [resolve], as close to the event that
/// caused the change as the filesystem allows.
///
/// Debouncing the wallpaper burst costs a fixed [_themeEventWindow] of visible
/// lag on every change, which is the opposite of what a backdrop is for: the
/// desktop swaps instantly and the app trails it by a third of a second. The
/// burst does not need suppressing either — `set_wallpaper` rewrites
/// `path.txt`, the `current` link and the `thumbnail.jpg` link inside ~1ms,
/// and only the middle one of those changes what the backdrop should show.
/// Resolving on each raw event and dropping repeats therefore emits exactly
/// once, on the right event, with no window: the two no-op events collapse by
/// [resolve] equality rather than by time.
///
/// A null from [resolve] is the one case that cannot be decided on the spot,
/// because the link is unlinked before its replacement is created — a
/// sub-millisecond hole that looks exactly like the wallpaper being removed.
/// Nulls therefore go through a grace timer, and an incoming path cancels it.
Stream<void> _distinctPathSignal(
  Stream<void> raw,
  String? Function() resolve,
) {
  final controller = StreamController<void>();
  StreamSubscription<void>? subscription;
  Timer? removalGrace;
  var last = '';

  void emitIfChanged() {
    final path = resolve() ?? '';
    if (path == last) return;
    last = path;
    controller.add(null);
  }

  controller.onListen = () {
    last = resolve() ?? '';
    subscription = raw.listen((_) {
      final path = resolve();
      if (path == null) {
        removalGrace ??= Timer(_removalGrace, () {
          removalGrace = null;
          emitIfChanged();
        });
        return;
      }
      removalGrace?.cancel();
      removalGrace = null;
      emitIfChanged();
    });
  };
  controller.onCancel = () async {
    removalGrace?.cancel();
    await subscription?.cancel();
  };
  return controller.stream;
}
