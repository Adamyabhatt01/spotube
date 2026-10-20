import 'dart:io';

import 'package:flutter/services.dart';
import 'package:spotube/utils/platform.dart';

/// Device-capability facts the memory budget needs.
///
/// A pure value object so the policy is testable without a device: only
/// [DeviceMemoryProbe] touches the platform.
class DeviceMemoryProfile {
  /// The device's total physical memory in bytes, or null when it cannot be
  /// determined.
  final int? totalPhysicalBytes;

  /// The per-app heap budget the platform grants, in bytes, or null when
  /// the platform does not publish one.
  ///
  /// On Android this is `ActivityManager.getMemoryClass()` — the point at
  /// which the system starts killing the app for being too big. It is the
  /// number that actually matters on a phone, and it is much smaller than
  /// the device's total RAM.
  final int? appHeapLimitBytes;

  const DeviceMemoryProfile({
    this.totalPhysicalBytes,
    this.appHeapLimitBytes,
  });

  /// The floor for every budget: below this the app cannot show a
  /// screenful of artwork and starts thrashing.
  static const int _minimumBudget = 8 * 1024 * 1024;

  /// The ceiling for every budget: a cache larger than this is not
  /// filling a screen, it is hoarding.
  static const int _maximumBudget = 64 * 1024 * 1024;

  /// The budget the platform image cache may use, in bytes.
  ///
  /// Three inputs, in order of authority:
  ///
  /// 1. The platform's per-app heap limit, when it publishes one. The
  ///    caches are the largest thing the app can hold onto, so they must
  ///    stay well inside what the platform will let the process keep.
  /// 2. A share of the device's physical memory, for platforms that publish
  ///    no per-app limit.
  /// 3. A conservative fixed fallback, for platforms where neither is
  ///    known (a browser, or a host that will not say).
  ///
  /// The share is deliberately small. A music player shows a grid of
  /// artwork; the decoded bytes are what the user sees, so the budget is
  /// spent on what is on screen, not on a speculative prefetch.
  int get imageCacheBudgetBytes {
    final heapLimit = appHeapLimitBytes;
    if (heapLimit != null && heapLimit > 0) {
      // A quarter of the per-app heap, bounded at both ends: an old
      // 64 MB-class device does not get a 40 MB image cache, and a modern
      // 512 MB-class device does not get 128 MB of one.
      final share = heapLimit ~/ 4;
      return share.clamp(_minimumBudget, _maximumBudget);
    }

    final total = totalPhysicalBytes;
    if (total != null && total > 0) {
      // A fifteenth of the device, bounded: a phone with 8 GB does not hand
      // 512 MB to an image cache, and a 1 GB device does not hand 68 MB.
      final share = total ~/ 15;
      return share.clamp(_minimumBudget, _maximumBudget);
    }

    return 32 * 1024 * 1024;
  }

  /// The cap for the in-process decoded-artwork cache
  /// (`UniversalImage._decodedMemoryCache`).
  ///
  /// Smaller than the image-cache budget on purpose: this one holds
  /// *decoded* bytes for local-track artwork, which the platform's image
  /// cache also holds. Two caches of the same size would double the
  /// artwork footprint.
  int get decodedArtworkBudgetBytes => imageCacheBudgetBytes ~/ 3;

  /// The cap for the artwork-bytes memo
  /// (`ServiceUtils.artworkBytes`).
  ///
  /// This one holds *encoded* bytes (what a fetch returns), so it is cheap
  /// per entry compared to a decoded image. It is bounded by bytes rather
  /// than by entry count, because a single 640x640 Spotify cover is
  /// ~150 KB while a small one is ~5 KB — an entry-count cap lets a
  /// handful of large covers cost megabytes without bound.
  int get artworkMemoBudgetBytes => imageCacheBudgetBytes ~/ 4;

  @override
  String toString() => 'DeviceMemoryProfile('
      'total=${_mb(totalPhysicalBytes)}, '
      'heapLimit=${_mb(appHeapLimitBytes)}, '
      'imageCache=${_mb(imageCacheBudgetBytes)})';

  /// Formats a byte count as MB, or "?" when it is unknown.
  static String _mb(int? bytes) =>
      bytes == null ? '?' : '${bytes ~/ (1024 * 1024)}MB';
}

/// Reads the device's memory facts.
///
/// The Android per-app heap limit needs a platform channel (there is no
/// Dart API for it). The channel is optional: if the platform side is not
/// there, the probe returns null and the policy falls back to the device
/// total.
class DeviceMemoryProbe {
  /// The channel the Android side answers on.
  static const channelName = 'oss.krtirtho.spotube/device_memory';

  /// Invokes a method on the platform channel.
  ///
  /// A function rather than a channel object so the test suite can drive
  /// the probe without a live engine.
  final Future<Object?> Function(String method) invoke;

  DeviceMemoryProbe({Future<Object?> Function(String method)? invoke})
      : invoke = invoke ?? _defaultInvoke;

  static Future<Object?> _defaultInvoke(String method) async {
    if (!kIsAndroid) {
      // Only Android publishes a per-app heap limit; asking elsewhere is
      // a guaranteed no-op.
      return null;
    }
    try {
      return await const MethodChannel(channelName)
          .invokeMethod<Object>(method);
    } catch (_) {
      // No platform side, or the channel is not implemented there. The
      // policy has a documented fallback for this.
      return null;
    }
  }

  /// The per-app heap limit, or null when unknown.
  ///
  /// `largeMemoryClass` is Android's way of saying "this app may use more
  /// than the standard limit"; it is not requested by this app, so the
  /// standard class is the right number to budget against.
  Future<int?> appHeapLimitBytes() async {
    try {
      final result = await invoke('appHeapLimitBytes');
      if (result is! int || result <= 0) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// The device's total physical memory, or null when unknown.
  ///
  /// `/proc/meminfo` on Linux and Android; the OS API elsewhere is not
  /// reachable from Dart without a channel, so this is null there and the
  /// policy falls back to its fixed value.
  Future<int?> totalPhysicalBytes() async {
    if (!kIsLinux && !kIsAndroid) return null;
    try {
      final file = File('/proc/meminfo');
      if (!await file.exists()) return null;
      for (final line in (await file.readAsString()).split('\n')) {
        if (!line.startsWith('MemTotal:')) continue;
        // MemTotal is in kB: "MemTotal:  16316388 kB".
        final parts = line.split(RegExp(r'\s+'));
        int? kb;
        for (final part in parts) {
          final parsed = int.tryParse(part);
          if (parsed != null) {
            kb = parsed;
            break;
          }
        }
        if (kb == null || kb <= 0) return null;
        return kb * 1024;
      }
    } catch (_) {
      // Unreadable /proc: the policy falls back.
    }
    return null;
  }

  /// The full profile, from whatever the platform can tell us.
  Future<DeviceMemoryProfile> resolve() async {
    final total = await totalPhysicalBytes();
    final heap = await appHeapLimitBytes();
    return DeviceMemoryProfile(
      totalPhysicalBytes: total,
      appHeapLimitBytes: heap,
    );
  }
}
