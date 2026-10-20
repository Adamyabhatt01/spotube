import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:hetu_otp_util/hetu_otp_util.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_spotube_plugin/hetu_spotube_plugin.dart' as spotube_plugin;
import 'package:hetu_spotube_plugin/hetu_spotube_plugin.dart'
    hide YouTubeEngine;
import 'package:hetu_std/hetu_std.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/components/titlebar/titlebar.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/services/metadata/apis/localstorage.dart';
import 'package:spotube/services/metadata/endpoints/album.dart';
import 'package:spotube/services/metadata/endpoints/artist.dart';
import 'package:spotube/services/metadata/endpoints/audio_source.dart';
import 'package:spotube/services/metadata/endpoints/auth.dart';
import 'package:spotube/services/metadata/endpoints/browse.dart';
import 'package:spotube/services/metadata/endpoints/playlist.dart';
import 'package:spotube/services/metadata/endpoints/search.dart';
import 'package:spotube/services/metadata/endpoints/track.dart';
import 'package:spotube/services/metadata/endpoints/core.dart';
import 'package:spotube/services/metadata/endpoints/user.dart';
import 'package:spotube/services/metadata/endpoints/theme.dart';
import 'package:spotube/services/metadata/endpoints/radio.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';

const defaultMetadataLimit = "20";

class MetadataPlugin {
  static final pluginApiVersion = Version.parse("2.0.0");

  static Future<MetadataPlugin> create(
    YouTubeEngine youtubeEngine,
    PluginConfiguration config,
    Uint8List byteCode,
  ) async {
    final sharedPreferences = await SharedPreferences.getInstance();
    BuildContext? pageContext;

    final hetu = Hetu();
    hetu.init();

    HetuStdLoader.loadBindings(hetu);
    HetuSpotubePluginLoader.loadBindings(
      hetu,
      localStorageImpl: SharedPreferencesLocalStorage(
        sharedPreferences,
        config.slug,
      ),
      onNavigatorPush: (route) {
        return rootNavigatorKey.currentContext?.router
            .pushWidget(Builder(builder: (context) {
          pageContext = context;
          return Scaffold(
            headers: const [
              TitleBar(
                automaticallyImplyLeading: true,
              )
            ],
            child: route,
          );
        }));
      },
      onNavigatorPop: () {
        pageContext?.maybePop();
      },
      onShowForm: (title, fields) async {
        if (rootNavigatorKey.currentContext == null) {
          return [];
        }

        return await rootNavigatorKey.currentContext!.router
            .push<List<Map<String, dynamic>>?>(
          SettingsMetadataProviderFormRoute(
            title: title,
            fields:
                fields.map((e) => MetadataFormFieldObject.fromJson(e)).toList(),
          ),
        );
      },
      createYoutubeEngine: () {
        return spotube_plugin.YouTubeEngine(
          search: (query) async {
            final result = await youtubeEngine.searchVideos(query);
            return result
                .map((video) => {
                      'id': video.id,
                      'title': video.title,
                      'author': video.author,
                      'duration': video.duration?.inSeconds,
                      'description': video.description,
                      'uploadDate': video.uploadDate?.toIso8601String(),
                      'viewCount': video.viewCount,
                      'likeCount': video.likeCount,
                      'isLive': video.isLive,
                      // A Short is a clip, not a recording. The flag is
                      // forwarded so the plugin can tell one from a
                      // full-length upload of the same title; the length
                      // check is what actually rules a Short out.
                      'isShortForm': video.isShortForm,
                    })
                .toList();
          },
          getVideo: (videoId) async {
            final video = await youtubeEngine.getVideo(videoId);
            return {
              'id': video.id.value,
              'title': video.title,
              'author': video.author,
              'duration': video.duration?.inSeconds,
              'description': video.description,
              'uploadDate': video.uploadDate?.toIso8601String(),
              'viewCount': video.engagement.viewCount,
              'likeCount': video.engagement.likeCount,
              'isLive': video.isLive,
            };
          },
          streamManifest: (videoId) {
            return youtubeEngine.getStreamManifest(videoId).then(
              (manifest) {
                final streams = manifest.audioOnly
                    .map(
                      (stream) => {
                        'url': stream.url.toString(),
                        'quality': stream.qualityLabel,
                        'bitrate': stream.bitrate.bitsPerSecond,
                        'container': stream.container.name,
                        'videoId': stream.videoId,
                      },
                    )
                    .toList();
                return streams;
              },
            );
          },
        );
      },
    );

    await HetuStdLoader.loadBytecodeFlutter(hetu);
    await HetuOtpUtilLoader.loadBytecodeFlutter(hetu);
    await HetuSpotubePluginLoader.loadBytecodeFlutter(hetu);

    hetu.loadBytecode(bytes: byteCode, moduleName: "plugin");
    hetu.eval("""
      import "module:plugin" as plugin

      var Plugin = plugin.${config.entryPoint}

      var metadataPlugin = Plugin()
      """);

    return MetadataPlugin._(hetu);
  }

  /// Wraps an already-booted [hetu] as a plugin, for tests that drive a real
  /// Hetu VM from an inline bytecode module without a plugin archive,
  /// SharedPreferences or a Flutter binding.
  @visibleForTesting
  static MetadataPlugin forTesting(Hetu hetu) => MetadataPlugin._(hetu);

  final Hetu hetu;

  late final MetadataAuthEndpoint auth;

  late final MetadataPluginAudioSourceEndpoint audioSource;
  late final MetadataPluginAlbumEndpoint album;
  late final MetadataPluginArtistEndpoint artist;
  late final MetadataPluginBrowseEndpoint browse;
  late final MetadataPluginSearchEndpoint search;
  late final MetadataPluginPlaylistEndpoint playlist;
  late final MetadataPluginTrackEndpoint track;
  late final MetadataPluginUserEndpoint user;
  late final MetadataPluginCore core;
  late final MetadataPluginThemeEndpoint theme;
  late final MetadataPluginRadioEndpoint radio;

  MetadataPlugin._(this.hetu) {
    auth = MetadataAuthEndpoint(hetu);

    audioSource = MetadataPluginAudioSourceEndpoint(hetu);
    artist = MetadataPluginArtistEndpoint(hetu);
    album = MetadataPluginAlbumEndpoint(hetu);
    browse = MetadataPluginBrowseEndpoint(hetu);
    search = MetadataPluginSearchEndpoint(hetu);
    playlist = MetadataPluginPlaylistEndpoint(hetu);
    track = MetadataPluginTrackEndpoint(hetu);
    user = MetadataPluginUserEndpoint(hetu);
    core = MetadataPluginCore(hetu);
    theme = MetadataPluginThemeEndpoint(hetu);
    radio = MetadataPluginRadioEndpoint(hetu);
  }
}
