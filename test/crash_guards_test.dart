// Regression guards for the album/playlist/radio crash sweep.
//
// Each case here used to throw from real metadata shapes (local files and
// plugin payloads can carry empty artist lists or blank names). They are
// pure helpers, so they stay cheap and hermetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/collections/fake.dart';
import 'package:spotube/models/sort.dart';
import 'package:spotube/utils/primitive_utils.dart';
import 'package:spotube/utils/service_utils.dart';

void main() {
  group('PrimitiveUtils initials', () {
    test('blank names return the fallback instead of throwing', () {
      expect(PrimitiveUtils.initialOf(null), '?');
      expect(PrimitiveUtils.initialOf(''), '?');
      expect(PrimitiveUtils.initialOf('   '), '?');
      expect(PrimitiveUtils.initialsOf(null), '?');
      expect(PrimitiveUtils.initialsOf(''), '?');
      expect(PrimitiveUtils.initialsOf('   '), '?');
    });

    test('names use the first letter/two initials', () {
      expect(PrimitiveUtils.initialOf(' daft punk '), 'D');
      expect(PrimitiveUtils.initialsOf('Daft Punk'), 'DP');
      expect(PrimitiveUtils.initialsOf('Madonna'), 'MA');
    });
  });

  group('sort by artist with empty metadata', () {
    test('does not throw on a track with no artists', () {
      // FakeData.albumSimple already has `artists: []`; the old
      // `a.artists.first.name` comparator threw RangeError here.
      final noArtists = FakeData.track.copyWith(artists: const []);

      final sorted = ServiceUtils.sortTracks(
        [noArtists, FakeData.track],
        SortBy.artist,
      );

      expect(sorted, hasLength(2));
    });
  });
}
