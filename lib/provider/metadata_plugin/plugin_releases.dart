part of 'metadata_plugin_provider.dart';

extension MetadataPluginReleases on MetadataPluginNotifier {
  Uri _getGithubReleasesUrl(String repoUrl) {
    final parsedUri = Uri.parse(repoUrl);
    final uri = parsedUri.replace(
      host: "api.github.com",
      pathSegments: [
        "repos",
        ...parsedUri.pathSegments,
        "releases",
      ],
      queryParameters: {
        "per_page": "1",
        "page": "1",
      },
    );

    return uri;
  }

  Uri _getCodebergeReleasesUrl(String repoUrl) {
    final parsedUri = Uri.parse(repoUrl);
    final uri = parsedUri.replace(
      pathSegments: [
        "api",
        "v1",
        "repos",
        ...parsedUri.pathSegments,
        "releases",
      ],
      queryParameters: {
        "limit": "1",
        "page": "1",
      },
    );

    return uri;
  }

  Future<String> _getPluginDownloadUrl(Uri uri) async {
    AppLogger.log.i("Getting plugin download URL from: $uri");
    final res = await ref.read(appDioProvider).getUri(
          uri,
          options: Options(responseType: ResponseType.json),
        );

    if (res.statusCode != 200) {
      throw MetadataPluginException.failedToGetRelease();
    }
    final releases = res.data as List;
    if (releases.isEmpty) {
      throw MetadataPluginException.noReleasesFound();
    }
    final latestRelease = releases.first;
    final downloadUrl = (latestRelease["assets"] as List).firstWhere(
      (asset) => (asset["name"] as String).endsWith(".smplug"),
    )["browser_download_url"];
    if (downloadUrl == null) {
      throw MetadataPluginException.assetUrlNotFound();
    }
    return downloadUrl;
  }
}
