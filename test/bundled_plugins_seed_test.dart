// Regression tests for the plugins that ship inside the APK.
//
// Covered:
//  - every slug in [bundledPlugins] has an archive on disk AND a pubspec
//    asset entry, so the seed list can not drift from what actually gets
//    packaged (a missing entry throws inside `_loadDefaultPlugins` on the
//    first launch of a fresh install, which is the worst time to find out);
//  - each archive parses and carries its bytecode, so `rootBundle.load` +
//    `readPluginArchiveConfig` cannot fail at startup;
//  - install *order*, because that order is the seed policy: the first plugin
//    with an ability wins that ability's default slot. Spotify ahead of
//    Musicbrainz is what makes it the recommended metadata source; YouTube
//    Audio must stay the audio source because Spotify has no `audio-source`.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/metadata_plugin/plugin_storage.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  Archive decode(String slug) => ZipDecoder().decodeBytes(
        File('assets/plugins/$slug/plugin.smplug').readAsBytesSync(),
      );

  PluginConfiguration readConfig(String slug) =>
      PluginStorage.readArchiveConfig(decode(slug));

  /// The seed that [addPlugin] would mark default for [ability]: the first
  /// installed plugin carrying it.
  PluginConfiguration firstWith(PluginAbilities ability) => bundledPlugins
      .map(readConfig)
      .firstWhere((c) => c.abilities.contains(ability));

  group('bundledPlugins', () {
    test('every entry is packaged as an asset', () {
      for (final slug in bundledPlugins) {
        expect(
          File('assets/plugins/$slug/plugin.smplug').existsSync(),
          isTrue,
          reason: '$slug has no archive on disk',
        );
        expect(
          pubspec.contains('assets/plugins/$slug/plugin.smplug'),
          isTrue,
          reason: '$slug is missing from pubspec.yaml assets',
        );
      }
    });

    test('every archive parses and carries bytecode', () {
      for (final slug in bundledPlugins) {
        final config = readConfig(slug);
        expect(config.name.isNotEmpty, isTrue);
        expect(config.author.isNotEmpty, isTrue);
        expect(
          decode(slug)
              .where((e) => e.isFile && e.name == 'plugin.out')
              .single
              .size,
          greaterThan(0),
          reason: '$slug has no plugin.out to load',
        );
      }
    });

    test('the Spotify plugin is bundled and wins the metadata default', () {
      final spotify = readConfig('spotube-plugin-spotify');

      expect(spotify.name, 'Spotify');
      expect(spotify.author, 'Adamya Bhatt');
      expect(spotify.abilities, contains(PluginAbilities.metadata));
      expect(
        spotify.abilities,
        isNot(contains(PluginAbilities.audioSource)),
        reason: 'audio-source would steal the YouTube Audio default',
      );

      expect(firstWith(PluginAbilities.metadata).name, 'Spotify');
      expect(
        firstWith(PluginAbilities.audioSource).name,
        'YouTube Audio',
        reason: 'the audio default must not move off the bundled source',
      );
      expect(
        firstWith(PluginAbilities.radio).name,
        'Internet Radio Browser',
      );
    });

    // The archive inside the APK is a build artifact copied out of the plugin
    // repo, so it goes stale silently: an app release that re-bundles nothing
    // keeps shipping whatever kernel was last copied. 0.2.10 is the build whose
    // `removeTracks` asserts on its own `uris` parameter instead of an
    // identifier that does not exist, which is why removal failed.
    //
    // 0.2.11 drops the read-back from the playlist *create*: it was the last
    // step of the create, so a throttled read reported a successful creation
    // as a failure and the playlist never appeared in the app.
    test('the bundled Spotify archive is the fixed build', () {
      expect(
        readConfig('spotube-plugin-spotify').version,
        '0.2.11',
        reason: 'assets/plugins/spotube-plugin-spotify/plugin.smplug is stale — '
            'rebuild in the plugin repo and copy build/plugin.smplug over it',
      );
    });

    // `checkUpdate` asks GitHub for the *declared repository's* latest release,
    // so a kernel left pointing at the original author's repo would offer to
    // replace this fork's plugin with the upstream build. The URL is a string
    // constant in the compiled kernel, which makes it checkable here.
    test('the bundled Spotify kernel updates from its own repository', () {
      final config = readConfig('spotube-plugin-spotify');
      final owner = Uri.parse(config.repository!).pathSegments.first;

      final kernel = decode('spotube-plugin-spotify')
          .firstWhere((file) => file.isFile && file.name == 'plugin.out')
          .readBytes();
      expect(kernel, isNotNull, reason: 'no kernel to read the URL out of');
      // String constants survive into the dill as plain bytes, which is what
      // makes this checkable without running the plugin.
      final source = String.fromCharCodes(kernel!);

      expect(
        source,
        contains('api.github.com/repos/$owner/spotube-plugin-spotify/releases'),
        reason: 'the kernel checks a repository other than the declared one',
      );
      expect(
        source,
        isNot(contains('api.github.com/repos/sonic-liberation/')),
        reason: 'self-update would recommend the upstream plugin over this fork',
      );
    });
  });
}
