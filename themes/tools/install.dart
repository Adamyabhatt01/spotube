import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/installer.dart';
import '../lib/theme_source.dart';

/// Installs a built theme into a Spotube profile.
///
/// The app has no command line, and the in-app upload is a file picker with a
/// dialog in the middle of it — fine for a user, slow for somebody editing a
/// theme. This writes the plugin where the app looks for it (the extraction
/// directory) and registers it in the profile's database, so a rebuild is one
/// command and a restart.
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
    );

  final options = parser.parse(arguments);
  final profile = options['profile'] as String;
  final repoRoot = p.dirname(p.dirname(p.absolute(Platform.script.toFilePath())));

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
      dryRun: options['dry-run'] as bool,
    );
    stdout.writeln(result.message);
    if (!result.registered && !(options['dry-run'] as bool)) failed = true;
  }

  if (failed) exitCode = 69;
}
