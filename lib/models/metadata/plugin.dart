part of 'metadata.dart';

enum PluginApis { webview, localstorage, timezone }

enum PluginAbilities {
  authentication,
  scrobbling,
  metadata,
  @JsonValue('audio-source')
  audioSource,
  theme,
  @JsonValue('radio')
  radio,
}

@freezed
class PluginConfiguration with _$PluginConfiguration {
  const PluginConfiguration._();

  factory PluginConfiguration({
    required String name,
    required String description,
    required String version,
    required String author,
    required String entryPoint,
    required String pluginApiVersion,
    @Default([]) List<PluginApis> apis,
    @Default([]) List<PluginAbilities> abilities,
    String? repository,
  }) = _PluginConfiguration;

  factory PluginConfiguration.fromJson(Map<String, dynamic> json) =>
      _$PluginConfigurationFromJson(json);

  String get slug => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}

@freezed
class PluginUpdateAvailable with _$PluginUpdateAvailable {
  factory PluginUpdateAvailable({
    required String downloadUrl,
    required String version,
    String? changelog,

    /// Optional integrity pin for the `downloadUrl` bytes.
    ///
    /// Plugin-authored: a plugin's own `checkUpdate` returns what the
    /// release metadata says, so the host trusts this only as a
    /// tamper/corruption check, never as a signature — a publisher that
    /// re-signs a compromise re-signs its checksum with it. Plugins that
    /// publish none leave this null; the download then proceeds as
    /// before.
    @JsonKey(name: 'sha256') String? expectedSha256,
  }) = _PluginUpdateAvailable;

  factory PluginUpdateAvailable.fromJson(Map<String, dynamic> json) =>
      _$PluginUpdateAvailableFromJson(json);
}
