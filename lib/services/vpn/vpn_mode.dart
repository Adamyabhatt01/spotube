/// Which network operations Spotube gates behind the user's own system VPN.
///
/// Kept in its own dependency-free file so both the Drift
/// `preferences_table` (a `part of` the database, which cannot carry extra
/// imports of its own) and the VPN service layer can share one definition.
///
/// `disabled` is the default and must mean zero behavioral change.
enum VpnMode {
  /// VPN automation off. No lease, no probe, no polling.
  disabled,

  /// Only track downloads wait for / hold the VPN.
  downloadsOnly,

  /// Only playback upstream fetches wait for / hold the VPN.
  playbackOnly,

  /// Both downloads and playback upstream fetches.
  downloadsAndPlayback,
}

/// Whether [mode] gates track downloads behind the VPN.
bool vpnModeGatesDownloads(VpnMode mode) =>
    mode == VpnMode.downloadsOnly || mode == VpnMode.downloadsAndPlayback;

/// Whether [mode] gates playback upstream fetches behind the VPN.
bool vpnModeGatesPlayback(VpnMode mode) =>
    mode == VpnMode.playbackOnly || mode == VpnMode.downloadsAndPlayback;
