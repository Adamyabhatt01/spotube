// LRCLib entry ranking (selectLrclibEntry in
// lib/services/lyrics/lrclib_provider.dart).
//
// /api/get is an exact-match lookup and LRCLib's stored artist strings do not
// agree with Spotify's, so a miss is recovered by ranking /api/search results.
// These are the shapes that ranking has to survive, including the real
// two-candidate answer for "Hardbone boy, SINASH - Dua".

import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/lyrics/lrclib_provider.dart';

Map<String, dynamic> _entry({
  int id = 1,
  String album = 'Album',
  double? duration = 153.0,
  String? synced = '[00:08.12] line',
  String? plain = 'line',
}) {
  return {
    'id': id,
    'trackName': 'Track',
    'artistName': 'Artist',
    'albumName': album,
    if (duration != null) 'duration': duration,
    'syncedLyrics': synced,
    'plainLyrics': plain,
  };
}

void main() {
  test('a timed entry beats a plain one, whatever the order', () {
    final plain = _entry(id: 1, synced: null, plain: 'just words');
    final timed = _entry(id: 2, album: 'Something else');

    for (final entries in [
      [plain, timed],
      [timed, plain],
    ]) {
      expect(
        selectLrclibEntry(entries, albumName: '', durationMs: 0)?['id'],
        2,
        reason: 'timestamps are the point of the synced view',
      );
    }
  });

  test('an entry with no lyrics at all is never chosen', () {
    expect(
      selectLrclibEntry(
        [
          _entry(id: 1, synced: null, plain: null),
          _entry(id: 2, synced: '  ', plain: ' \n '),
        ],
        albumName: '',
        durationMs: 0,
      ),
      isNull,
      reason: 'whitespace is what lrclib hands back for an empty entry',
    );
  });

  test('album agreement breaks a tie between two timed candidates', () {
    final chosen = selectLrclibEntry(
      [
        _entry(id: 1, album: 'Greatest Hits', duration: 153),
        _entry(id: 2, album: 'Dua', duration: 153),
      ],
      albumName: 'Dua',
      durationMs: 153000,
    );

    expect(chosen?['id'], 2);
  });

  test('a cover version of the same title is dropped on length alone',
      () async {
    final chosen = selectLrclibEntry(
      [
        _entry(id: 1, album: 'Other', duration: 900),
        _entry(id: 2, album: 'Other', duration: 153),
      ],
      albumName: '',
      durationMs: 153000,
    );

    expect(chosen?['id'], 2, reason: 'a 15-minute entry is not this song');
  });

  test('a missing duration does not disqualify an entry', () {
    final chosen = selectLrclibEntry(
      [_entry(id: 1, duration: null)],
      albumName: 'Album',
      durationMs: 153000,
    );

    expect(chosen?['id'], 1);
  });

  test('non-object entries in the list are skipped', () {
    expect(
      selectLrclibEntry(
        ['surprise', null, 42, _entry(id: 7)],
        albumName: '',
        durationMs: 0,
      )?['id'],
      7,
    );
  });
}
