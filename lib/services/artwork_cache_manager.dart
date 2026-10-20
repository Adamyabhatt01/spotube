import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The single on-disk image-artwork cache manager: `UniversalImage`'s network
/// providers, `ServiceUtils.downloadImage`, glance notifications and plugin
/// READMEs all go through this one instance.
///
/// It keeps `DefaultCacheManager`'s cache key (so artwork cached before this
/// class existed stays valid, no re-download cliff) while raising its
/// 200-object ceiling: scrolling a real library touches far more than 200
/// covers, and every eviction turned the next sighting into a re-download plus
/// a cache-DB rewrite.
///
/// `DefaultCacheManager()` must never be constructed in this process — two
/// managers sharing one key would fight over one database with different
/// budgets — so every image call site names this instance explicitly instead
/// of relying on the package default.
class ArtworkCacheManager extends CacheManager with ImageCacheManager {
  static final ArtworkCacheManager instance = ArtworkCacheManager._();

  static const _cacheKey = 'libCachedImageData';

  ArtworkCacheManager._()
      : super(
          Config(
            _cacheKey,
            maxNrOfCacheObjects: 1500,
          ),
        );
}
