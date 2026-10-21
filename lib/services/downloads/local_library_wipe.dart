import 'package:path/path.dart';

/// The only files a library wipe may delete.
///
/// A `track_download` row records where a file was written, not who owns it:
/// existing files get adopted when a download finds one already on disk, and a
/// row keeps its old path after the user moves the download location. So the
/// row alone is not permission to delete — the path has to resolve inside one of
/// the two roots this app owns. Anything else loses its row and keeps its file.
///
/// Folder locations the user added to the library are then subtracted, because
/// music in those folders was never ours. When a user adds a folder that
/// contains the download root, every download path is also a library path, so
/// the result is empty by construction rather than by a special case.
///
/// Pure and filesystem-free so the boundary is testable without touching disk.
List<String> selectFilesToDelete({
  required Iterable<String> filePaths,
  required String downloadRoot,
  required String cacheRoot,
  required List<String> libraryLocations,
}) {
  final ownedRoots = [downloadRoot, cacheRoot]
      .where((root) => root.isNotEmpty)
      .map(normalize)
      .toList();

  final userRoots = libraryLocations
      .where((root) => root.isNotEmpty)
      .map(normalize)
      .toList();

  final selected = <String>{};
  for (final path in filePaths) {
    if (path.isEmpty) continue;
    final normalized = normalize(path);
    final isOurs = ownedRoots.any((root) => isWithin(root, normalized));
    if (!isOurs) continue;
    final isUserMusic = userRoots.any((root) => isWithin(root, normalized));
    if (isUserMusic) continue;
    selected.add(normalized);
  }
  return selected.toList();
}

/// Byte total of the rows a wipe would report to the user.
///
/// `sizeBytes` is written by the completed download only, so a queued, failed or
/// interrupted row contributes nothing rather than a guessed size.
int sumDownloadedBytes(Iterable<int?> sizeBytes) =>
    sizeBytes.fold<int>(0, (total, size) => total + (size ?? 0));

/// Compact byte total for the confirmation dialog.
String formatByteTotal(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : (value < 10 ? 1 : 0))} '
      '${units[unit]}';
}
