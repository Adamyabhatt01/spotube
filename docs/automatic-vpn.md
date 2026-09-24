# Automatic VPN (user-owned system connection)

Spotube can route protected network activity through **your existing VPN**.
Two target kinds are supported. Both are strictly opt-in and off by default.

## Target kinds

1. **System connection** (Linux + NetworkManager only): a connection from
   your NetworkManager configuration, which Spotube may activate before a
   protected operation and deactivate afterwards.
2. **Tunnel device, app-managed** (any platform): a live tunnel interface
   from your VPN app (e.g. `nordlynx`, `proton0`, `mullvad-*`). Spotube
   never connects or disconnects it — it waits for the device to exist
   with addresses, shares it while held, and leaves it untouched. This is
   the kind to use when your VPN runs in its own provider app outside
   NetworkManager. When both a connection and a device are selected, the
   connection wins.

## What it does

- When enabled for downloads, each track download waits for the selected
  system VPN connection to be active (activating it first if needed) and
  holds it until the download finishes, fails, or is cancelled.
- When enabled for playback, upstream stream fetches (the proxy hop from
  YouTube/CDN to Spotube's local server) are gated the same way.
  Already-downloaded files and the music cache are local I/O and never
  take a VPN lease.
- Concurrent downloads share one VPN connection (reference-counted leases),
  so the VPN is not flapped per track.
- If the VPN disappears mid-download, the retry loop **pauses and waits**
  for recovery (up to the configured timeout) instead of continuing over
  the normal connection. If recovery does not happen in time, the download
  fails with an explicit error.
- A VPN you connected yourself is used but **never disconnected** by
  Spotube. Only a connection Spotube itself activated is brought down —
  and only when auto-disconnect is on and the last download finishes.
  App-managed tunnel devices are never connected or disconnected, only
  shared while they exist.

## What it does NOT do

- It is **not a VPN provider**: there is no Spotube VPN service, no server,
  no subscription, no credentials. You configure your VPN in your operating
  system (e.g. NetworkManager) exactly as before; Spotube only activates or
  deactivates the connection you pick.
- It is **not a system-wide kill switch** and full traffic isolation is not
  claimed (see "Socket-level pinning" below for exactly what is and is not
  pinned). Kernel routing, DNS resolution, other applications, and an
  already-open player socket are outside what the app can enforce.

## Socket-level pinning (qBittorrent-style hardening)

Dart exposes no interface-binding API (`SO_BINDTODEVICE` does not exist in
`dart:io`), so true "bind everything to `tun0`" is impossible from app
code. What Spotube does instead, while a VPN lease is held:

- Dio traffic (track downloads, playback upstream fetches, lyrics/metadata
  validation, plugin index) opens its sockets with the local end bound to
  the tunnel interface's current address (`Socket.connect(...,
  sourceAddress:)`; TLS legs upgrade the same pinned socket via
  `SecureSocket.secure` with SNI and the app's standard certificate rule).
  With no lease held, the same code path behaves exactly like a default
  client (verified by tests against loopback, plain and TLS).
- The pin is resolved when the lease connects and refreshed after every
  protection wait, so a reconnect IP change heals on the next attempt. If
  no tunnel address can be found, acquisition fails closed
  (`VpnNoRouteException`) — a connected-but-unpinnable state never
  authorizes traffic, and an owned activation is undone.
- A request that would traverse an HTTP proxy under an active pin throws
  `VpnProxyConflictException` instead of transmitting unpinned (no proxy
  handling exists in the app, so this is currently unreachable by
  construction — it exists so a future proxy cannot silently bypass).

Not pinned (separate transports outside Dio): Hetu plugin HTTP, the
yt-dlp/NewPipe subprocesses, and image-cache fetches. DNS uses the system
resolver. Packet-level verification (tcpdump while dropping the tunnel
mid-download) is still required before claiming more than "reduces
exposure" — until then, this is hardening, not a kill switch.
- It never stores passwords, keys, or tokens. Authentication stays with the
  operating system.

## Supported platforms and managers

- **System connections:** Linux with NetworkManager (`nmcli` on PATH)
  only, verified at operation time. Every other platform reports
  `Automatic VPN is not supported on this platform yet` for this kind, and
  gated operations fail with that explicit error.
- **Tunnel devices:** anywhere Dart lists network interfaces (all current
  platforms, including nmcli-less hosts) — sharing a live tunnel needs no
  backend, only interface listing plus socket pinning.
- If `nmcli` is missing (minimal installs, some Flatpak sandboxes), the
  system-connection kind is unavailable and operations fail closed with an
  explicit error rather than silently using the normal connection; the
  tunnel-device kind keeps working.
- A command return code alone is never trusted: after activation Spotube
  polls the active-connection set for the selected UUID before proceeding.
- The tunnel picker only offers interfaces that look like tunnels
  (backend-verified VPN devices or name matches), so Wi-Fi/Ethernet can
  never be selected: pinning one of those would protect nothing.

## Behavior on VPN loss

1. In-flight HTTP requests typically fail when the tunnel drops; the
   existing bounded retry (2 s, 6 s) applies.
2. Before every (re)try, Spotube re-verifies the VPN against the live
   system state and waits for it to return (bounded by "VPN wait timeout",
   default 60 s, cancellable at any time).
3. If the wait expires, the download fails with `VPN connection lost
   during protected operation`. Nothing is retried outside the VPN.

## Ownership

- Connection active before Spotube needed it → shared, left untouched.
- Connection activated by Spotube → brought down after the last lease
  releases, unless "Disconnect when done" is off.
- If ownership cannot be determined, Spotube leaves the system state
  unchanged and fails the operation closed.

## Configuration (Settings → Downloads)

- **Automatic VPN**: Disabled (default = everything behaves as before),
  Downloads, Playback, or Downloads + playback. The connection picker and
  auto-disconnect switch appear only when a non-disabled mode is chosen.
- **VPN connection**: one of your system VPN connections (managed kind),
  or one of your live tunnel devices (app-managed kind), or nothing
  (clears the selection and disables gating). The row shows the current
  selection: `Tunnel: <device>`, `System connection`, or nothing selected.
- **Disconnect when done**: default on. Applies to system connections
  Spotube started; app-managed tunnels and user-started connections are
  never disconnected regardless of this switch.
- **VPN wait timeout** is fixed at 60 s in settings storage; per-operation
  waits are additionally bounded and abort immediately on cancellation.

## Limitations

- System connections: Linux/NetworkManager only; no WireGuard-direct, no
  Android/Windows/macOS automation for that kind in this phase.
  Tunnel devices work cross-platform.
- Activation waits are bounded, never indefinite; a protected operation can
  therefore still fail when the VPN (or its credentials, or user
  authorization via polkit) never arrives — explicitly, never silently.
- A tunnel that changes its device name across reconnects must be
  reselected; the wait fails closed naming the missing device.
- `nmcli` invocations cannot be cancelled mid-flight, only abandoned by
  timeout; cancellation races the activation and undoes it best-effort.
- During a wait, the active set is re-queried about twice per second; when
  the feature is disabled there is no polling, no process, no overhead.
