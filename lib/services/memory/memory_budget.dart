import 'package:spotube/services/memory/device_memory_profile.dart';

/// The process-wide memory budget the image caches obey.
///
/// A single source of truth so the three caches cannot drift apart: the
/// platform image cache (`PaintingBinding.instance.imageCache`), the
/// decoded-artwork cache (`UniversalImage`) and the artwork-bytes memo
/// (`ServiceUtils.artworkBytes`) each take a slice of the same budget
/// instead of each picking its own fixed number.
///
/// The budget is resolved once at startup from what the platform reports
/// about the device. Until then — and on a platform that reports nothing —
/// the conservative defaults apply, so a cache is never unbounded and never
/// larger than it should be.
class MemoryBudget {
  static DeviceMemoryProfile _profile = const DeviceMemoryProfile();

  /// The current profile.
  static DeviceMemoryProfile get profile => _profile;

  /// The bytes the platform image cache may hold.
  static int get imageCacheBytes => _profile.imageCacheBudgetBytes;

  /// The bytes the decoded-artwork cache may hold.
  static int get decodedArtworkBytes => _profile.decodedArtworkBudgetBytes;

  /// The bytes the artwork-bytes memo may hold.
  static int get artworkMemoBytes => _profile.artworkMemoBudgetBytes;

  /// Installs the resolved profile. Called once at startup.
  static void install(DeviceMemoryProfile profile) {
    _profile = profile;
  }

  /// Test seam: restores the default profile.
  static void reset() {
    _profile = const DeviceMemoryProfile();
  }
}
