import 'package:envied/envied.dart';
import 'package:spotube/utils/platform.dart';

part 'env.g.dart';

enum ReleaseChannel {
  nightly,
  stable,
}

@Envied(obfuscate: true, requireEnvFile: true, path: ".env")
abstract class Env {
  @EnviedField(varName: 'LASTFM_API_KEY')
  static final String lastFmApiKey = _Env.lastFmApiKey;

  @EnviedField(varName: 'LASTFM_API_SECRET')
  static final String lastFmApiSecret = _Env.lastFmApiSecret;

  @EnviedField(varName: 'HIDE_DONATIONS', defaultValue: "0")
  static final int _hideDonations = _Env._hideDonations;

  static bool get hideDonations => _hideDonations == 1;

  // Off by default: the only channel a build of this fork can install from is
  // this fork's own releases, and there are none yet. Turn it on per build with
  // ENABLE_UPDATE_CHECK=1 once there are.
  @EnviedField(varName: 'ENABLE_UPDATE_CHECK', defaultValue: "0")
  static final String _enableUpdateChecker = _Env._enableUpdateChecker;

  @EnviedField(varName: "RELEASE_CHANNEL", defaultValue: "nightly")
  static final String _releaseChannel = _Env._releaseChannel;

  static ReleaseChannel get releaseChannel => _releaseChannel == "stable"
      ? ReleaseChannel.stable
      : ReleaseChannel.nightly;

  static bool get enableUpdateChecker =>
      kIsFlatpak || _enableUpdateChecker == "1";

  /// Releases this build is allowed to install from. Deliberately not the
  /// upstream repository: upstream's next tag would otherwise offer to
  /// overwrite a fork build with a binary containing none of the fork's work.
  static const String updateRepo = "Adamyabhatt01/spotube";

  static const String updateRepoReleasesUrl =
      "https://github.com/$updateRepo/releases";

  static String discordAppId = "1176718791388975124";
}
