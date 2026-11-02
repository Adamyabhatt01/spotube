import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/installer.dart';
import '../lib/theme_source.dart';

/// Installs a built theme into a Spotube profile, or removes one from it.
///
/// The app has no command line, and the in-app upload is a file picker with a
/// dialog in the middle of it — fine for a user, slow for somebody editing a
/// theme. This writes the plugin where the app looks for it (the extraction
/// directory) and registers it in the profile's database, so a rebuild is one
/// command and a restart. `--uninstall <name> --author <author>` takes it away
/// again, including the cached definition and the theme's own settings.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption('theme', help: 'Theme id to install.', abbr: 't')
    ..addOption(
      'profile',
      help: 'Profile directory (the one with .local/share).',
      defaultsTo: '/tmp/spotube-bench-home',
    )
    ..addOption(
      'artifact',
      help: 'Install a built .smplug instead of a theme directory.',
    )
    ..addFlag(
      'select',
      help: 'Make the installed theme the default theme.',
      negatable: false,
    )
    ..addFlag('dry-run', help: 'Print what would happen.', negatable: false)
    ..addFlag(
      'create-profile',
      help: 'Create the profile and its plugin table if they are missing.',
      negatable: false,
    )
    ..addMultiOption(
      'uninstall',
      abbr: 'u',
      help: 'Plugin name to remove from the profile, with --author.',
    )
    ..addOption('author', help: 'Author of the plugin named by --uninstall.')
    ..addOption(
      'version',
      help: 'Only this installed version, for use with --uninstall.',
    );

  final options = parser.parse(arguments);
  final profile = options['profile'] as String;
  final dryRun = options['dry-run'] as bool;
  final repoRoot = p.dirname(p.dirname(p.absolute(Platform.script.toFilePath())));

  final targets = options['uninstall'] as List<String>;
  if (targets.isNotEmpty) {
    final author = options['author'] as String?;
    if (author == null) {
      stderr.writeln('--uninstall needs --author: the row is keyed by both');
      exitCode = 64;
      return;
    }
    for (final name in targets) {
      final result = uninstallPlugin(
        name: name,
        author: author,
        version: options['version'] as String?,
        profile: profile,
        dryRun: dryRun,
      );
      stdout.writeln(result.message);
      if (!dryRun && result.removedDirs.isEmpty && !result.removedRow) {
        exitCode = 66;
      }
    }
    return;
  }

  final archives = <File>[];
  final artifact = options['artifact'] as String?;
  if (artifact != null) {
    archives.add(File(artifact));
  } else {
    final selected = options['theme'] as List<String>;
    if (selected.isEmpty) {
      stderr.writeln('nothing to install: pass --theme <id> or --artifact <file>');
      exitCode = 64;
      return;
    }
    for (final theme in loadThemes(repoRoot)) {
      if (!selected.contains(theme.id)) continue;
      final built = File(p.join(repoRoot, 'dist', theme.artifactName));
      if (!built.existsSync()) {
        stderr.writeln('${theme.id}: no build at ${built.path} — run the build first');
        exitCode = 66;
        return;
      }
      archives.add(built);
    }
  }

  if (options['create-profile'] as bool) {
    createPluginTable(File(pluginDatabaseFile(profile)));
  }

  var failed = false;
  for (final archive in archives) {
    final result = installPlugin(
      archive: PluginArchive.read(archive),
      profile: profile,
      select: options['select'] as bool,
      dryRun: dryRun,
    );
    stdout.writeln(result.message);
    if (!result.registered && !dryRun) failed = true;
  }

  if (failed) exitCode = 69;
}
