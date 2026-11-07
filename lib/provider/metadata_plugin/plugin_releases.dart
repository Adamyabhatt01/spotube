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

  /// The latest release's `.smplug` asset plus its published checksum.
  ///
  /// GitHub and Forgejo release assets carry `digest` ("sha256:<hex>").
  /// When a publisher declares none, `sha256` is null and the download
  /// proceeds unverified (the plugin is still installed under the user's
  /// explicit consent to that repository, as before).
  Future<({String url, String? sha256})> _getPluginDownloadUrl(
    Uri uri,
  ) async {
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
    final asset = (latestRelease["assets"] as List).firstWhere(
      (asset) => (asset["name"] as String).endsWith(".smplug"),
    );
    final downloadUrl = asset["browser_download_url"];
    if (downloadUrl == null) {
      throw MetadataPluginException.assetUrlNotFound();
    }
    return (url: downloadUrl as String, sha256: _assetDigest(asset));
  }

  /// The asset's published SHA-256, or null when it declares none.
  ///
  /// Both forges this resolves repositories against (GitHub, Forgejo)
  /// advertise `"digest": "sha256:<hex>"` on release assets.
  static String? _assetDigest(Map asset) {
    final digest = asset["digest"];
    if (digest is! String) return null;
    const prefix = 'sha256:';
    if (!digest.startsWith(prefix)) return null;
    final hex = digest.substring(prefix.length).trim().toLowerCase();
    return hex.isEmpty ? null : hex;
  }
}
