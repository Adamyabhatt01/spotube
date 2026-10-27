import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/utils/service_utils.dart';

/// On-disk layout and atomic install for metadata plugins.
///
/// Everything here is filesystem work: the plugin root, per-version
/// extraction directories, staged extraction and rollback. The notifier owns
/// the database rows and the registry state on top of it.
class PluginStorage {
  PluginStorage();

  /// Root directory where all metadata plugins are stored.
  ///
  /// Memoized: every `pluginsTable` watch event re-validates the plugin list,
  /// and the support directory cannot move within a session.
  Future<Directory> get rootDir async {
    if (_rootDirPath case final path?) return Directory(path);
    final root = Directory(
      join(
        (await getApplicationSupportDirectory()).path,
        "metadata-plugins",
      ),
    );
    _rootDirPath = root.path;
    return root;
  }

  String? _rootDirPath;

  /// `author::name@version` triples whose extraction directory was validated
  /// this session. Directories are version-suffixed and immutable once
  /// extracted, so the three existence checks per plugin do not need to
  /// re-run on every watch event; install/remove paths below evict stale
  /// entries.
  final Set<String> validatedPlugins = {};

  static String validationKey(PluginConfiguration plugin) =>
      '${plugin.author}::${plugin.name}@${plugin.version}';

  static String validationPrefix(PluginConfiguration plugin) =>
      '${plugin.author}::${plugin.name}@';

  /// Directory where the plugin will be extracted.
  /// This is a unique directory for each plugin version.
  /// It is used to avoid conflicts when multiple versions of the same plugin are installed
  ///
  /// `author` and `name` go through [ServiceUtils.sanitizeFilename]; `version`
  /// used to be interpolated raw. It is free text from the archive's own
  /// `plugin.json`, so a crafted value decided where every entry of the archive
  /// landed: `join` does not normalize, so `..` segments survive and the kernel
  /// resolves them at open(). The entry names themselves are already rejected
  /// by [isSafePluginEntryPath] before anything is written; the directory they
  /// land in has to pass the same predicate. Thrown here — the single choke
  /// point every caller (extraction, bytecode read, logo, validation, removal)
  /// funnels through — so no path can write outside the plugin root.
  Future<Directory> extractionDir(PluginConfiguration plugin) async {
    if (!isSafePluginEntryPath(plugin.version)) {
      throw MetadataPluginException.invalidPluginConfiguration();
    }
    final pluginDir = await rootDir;
    final pluginExtractionDirPath = join(
      pluginDir.path,
      "${ServiceUtils.sanitizeFilename(plugin.author)}-${ServiceUtils.sanitizeFilename(plugin.name)}-${plugin.version}",
    );
    return Directory(pluginExtractionDirPath);
  }

  Future<PluginConfiguration> extractArchive(List<int> bytes) async {
    return extractArchiveFrom(ZipDecoder().decodeBytes(bytes));
  }

  /// `plugin.json` of an already decoded archive, without touching the disk.
  static PluginConfiguration readArchiveConfig(Archive archive) {
    final pluginJson = archive.firstWhereOrNull(
      (file) => file.isFile && file.name == "plugin.json",
    );
    if (pluginJson == null) {
      throw MetadataPluginException.pluginConfigJsonNotFound();
    }
    return PluginConfiguration.fromJson(
      jsonDecode(
        utf8.decode(pluginJson.content as List<int>),
      ) as Map<String, dynamic>,
    );
  }

  Future<PluginConfiguration> extractArchiveFrom(Archive archive) async {
    final pluginConfig = readArchiveConfig(archive);

    // Validate before anything is written to disk: the bytecode file
    // [MetadataPluginNotifier.getPluginByteCode] will later require must be
    // present, and every entry path must stay inside the extraction directory.
    // A partially extracted plugin would otherwise linger on disk even though
    // the install itself fails.
    final hasByteCode =
        archive.any((file) => file.isFile && file.name == "plugin.out");
    if (!hasByteCode) {
      throw MetadataPluginException.pluginByteCodeFileNotFound();
    }

    final pluginDir = await rootDir;
    await pluginDir.create(recursive: true);

    final pluginExtractionDir = await extractionDir(pluginConfig);
    await recoverInterruptedExtraction(pluginExtractionDir);

    for (final file in archive) {
      if (file.isFile && !isSafePluginEntryPath(file.name)) {
        throw MetadataPluginException.invalidPluginConfiguration();
      }
    }

    // Never write over the live plugin directory. A failed extraction must
    // leave the previous working version byte-for-byte intact, and readers
    // must never observe a half-written plugin.
    final stagingDir = Directory(
      join(pluginDir.path, '.staging-$pid-${_stagingSequence++}'),
    );
    try {
      await stagingDir.create(recursive: true);
      for (final file in archive) {
        if (file.isFile) {
          final extractedFile = File(join(stagingDir.path, file.name));
          await extractedFile.create(recursive: true);
          await extractedFile.writeAsBytes(file.content as List<int>);
        }
      }
      await _promoteStagedPlugin(stagingDir, pluginExtractionDir);
    } catch (_) {
      // Only the staging directory is ours to remove; the target is either
      // untouched (failure before promotion) or was restored by promotion.
      await deleteDirectoryQuietly(stagingDir);
      rethrow;
    }

    return pluginConfig;
  }

  static int _stagingSequence = 0;

  /// Replaces [target] with [staging] as close to atomically as the
  /// filesystem allows. The target is moved aside first because a directory
  /// rename cannot replace a non-empty directory on every platform.
  Future<void> _promoteStagedPlugin(
    Directory staging,
    Directory target,
  ) async {
    final backup = Directory('${target.path}.backup');

    if (await backup.exists()) {
      await deleteDirectoryQuietly(backup);
    }

    final hadTarget = await target.exists();
    if (hadTarget) {
      await target.rename(backup.path);
    }

    try {
      await staging.rename(target.path);
    } catch (_) {
      // Put the old version back so a failed promotion is a no-op for the
      // caller. If this restore also fails, a later startup recovery can
      // still restore `${target}.backup`.
      if (hadTarget && !await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }

    if (hadTarget) {
      await deleteDirectoryQuietly(backup);
    }
  }

  /// Completes or rolls back a swap interrupted between the two directory
  /// renames. Called before validation and before the next extraction.
  Future<void> recoverInterruptedExtraction(Directory target) async {
    final backup = Directory('${target.path}.backup');
    if (!await backup.exists()) return;

    if (await target.exists()) {
      // The new target was promoted but the backup was not cleaned up.
      await deleteDirectoryQuietly(backup);
      return;
    }

    // The old target was moved aside but the new one was never promoted.
    await backup.rename(target.path);
  }

  Future<void> deleteDirectoryQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup; an orphaned staging/backup directory is never
      // registered and cannot be served as a plugin.
    }
  }

  /// True when [name] cannot escape the plugin extraction directory.
  ///
  /// Both separator styles are normalized first: a Windows-style
  /// `..\evil` entry only traverses on Windows, so a substring check
  /// for `..` alone would miss platform differences, and `a/../../b`
  /// only escapes after normalization. Drive-letter prefixes are also
  /// rejected on every platform: a zip built on one OS is extracted on
  /// whatever OS the installer runs.
  /// Static and side-effect free so the traversal rules stay unit-testable.
  static bool isSafePluginEntryPath(String name) {
    final normalized = normalize(name.replaceAll('\\', '/'));
    if (isAbsolute(normalized)) return false;
    if (normalized == '..' || normalized.startsWith('../')) return false;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) return false;
    return true;
  }
}
