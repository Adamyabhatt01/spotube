import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart'
    as np;
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/youtube_engine/newpipe_engine.dart';
import 'package:spotube/services/youtube_engine/yt_dlp_engine.dart';

/// Fixtures below are real rows captured on 2026-09-21 from the two search
/// backends for "Wassup Flawed" (`yt-dlp --print '%()j' --flat-playlist
/// ytsearch10:…` and the bundled NewPipeCLI with `--content-filters videos`).
///
/// The case that matters is the yt-dlp row for `KENf509XTjI`: it is the right
/// video *and* the row where YouTube's flat search page omits `channel_id`,
/// `uploader_id`, `channel_url` and `upload_date`. Parsing it into
/// youtube_explode_dart's `Video` used to throw, which cost the entire page —
/// so the yt-dlp engine failed on the best candidate it had found.
void main() {
  group('YtDlpEngine.parseSearchResult', () {
    const musicUploadRow = {
      'id': 'KENf509XTjI',
      'title': 'Wassup ft. Slay, SIM || Sounds Like Home',
      'channel': 'Flawed and 2 more',
      'uploader': 'Flawed and 2 more',
      'channel_id': null,
      'channel_url': null,
      'uploader_id': null,
      'uploader_url': null,
      'upload_date': null,
      'duration': 274,
      'view_count': 17463,
      'description': 'Wassup” is not just a track — it is a tribute.',
      'url': 'https://www.youtube.com/watch?v=KENf509XTjI',
    };

    const officialAudioRow = {
      'id': 'sKHv6S1y_j0',
      'title': 'Wassup',
      'channel': 'Flawed',
      'uploader': 'Flawed',
      'channel_id': 'UCkMD8d0gBo-yxxjhZMzdj_w',
      'channel_url': 'https://www.youtube.com/channel/UCkMD8d0gBo-yxxjhZMzdj_w',
      'uploader_id': '@FlawedOfficial',
      'upload_date': null,
      'duration': 221,
      'view_count': 5162,
      'description': 'Provided to YouTube by The Orchard Enterprises',
      'url': 'https://www.youtube.com/watch?v=sKHv6S1y_j0',
    };

    test('keeps a row whose channel identity is entirely missing', () {
      final result = YtDlpEngine.parseSearchResult(musicUploadRow);

      expect(result, isNotNull);
      expect(result!.id, 'KENf509XTjI');
      expect(result.author, 'Flawed and 2 more');
      expect(result.duration, const Duration(seconds: 274));
      expect(result.viewCount, 17463);
      expect(result.isLive, false);
    });

    test('keeps a row that does carry a channel id', () {
      final result = YtDlpEngine.parseSearchResult(officialAudioRow);

      expect(result?.id, 'sKHv6S1y_j0');
      expect(result?.author, 'Flawed');
    });

    test('drops rows with no video id or no title, without throwing', () {
      expect(YtDlpEngine.parseSearchResult({...musicUploadRow, 'id': null}),
          isNull);
      expect(
          YtDlpEngine.parseSearchResult({...musicUploadRow, 'id': ''}), isNull);
      expect(
        YtDlpEngine.parseSearchResult({...musicUploadRow, 'title': null}),
        isNull,
      );
      expect(YtDlpEngine.parseSearchResult({'_type': 'playlist'}), isNull);
      expect(YtDlpEngine.parseSearchResult(null), isNull);
    });

    test('a missing duration stays unknown instead of faking one', () {
      final result = YtDlpEngine.parseSearchResult(
        {...musicUploadRow, 'duration': null, 'view_count': null},
      );

      expect(result?.duration, isNull);
      expect(result?.viewCount, isNull);
    });
  });

  group('NewPipeEngine.parseSearchResult', () {
    np.VideoSearchResultItem videoRow({
      String url = 'https://www.youtube.com/watch?v=KENf509XTjI',
      np.StreamInfoType streamType = np.StreamInfoType.videoStream,
      np.DateWrapper? uploadDate,
    }) {
      return np.VideoSearchResultItem(
        infoType: np.SearchResultType.video,
        url: url,
        name: 'Wassup ft. Slay, SIM || Sounds Like Home',
        thumbnails: const [],
        streamType: streamType,
        uploaderName: 'Flawed and 2 more',
        uploaderUrl: 'https://www.youtube.com/channel/UCkMD8d0gBo-yxxjhZMzdj_w',
        uploaderAvatars: const [],
        uploaderVerified: true,
        shortFormContent: false,
        shortDescription: 'Wassup” is not just a track — it is a tribute.',
        uploadDate: uploadDate,
        viewCount: 17463,
        duration: 274,
      );
    }

    test('maps a video row', () {
      final result = NewPipeEngine.parseSearchResult(videoRow());

      expect(result?.id, 'KENf509XTjI');
      expect(result?.author, 'Flawed and 2 more');
      expect(result?.duration, const Duration(seconds: 274));
      expect(result?.isLive, false);
    });

    test('marks live rows as live', () {
      final result = NewPipeEngine.parseSearchResult(
        videoRow(streamType: np.StreamInfoType.liveStream),
      );

      expect(result?.isLive, true);
    });

    test('keeps an approximate upload date', () {
      final result = NewPipeEngine.parseSearchResult(
        videoRow(
          uploadDate: np.DateWrapper(
            offsetDateTime: DateTime.utc(2025, 11, 21),
            isApproximation: true,
          ),
        ),
      );

      expect(result?.uploadDate, DateTime.utc(2025, 11, 21));
    });

    test('drops a row it cannot resolve to a video id', () {
      expect(
        NewPipeEngine.parseSearchResult(
          videoRow(url: 'https://www.youtube.com/nullplayer'),
        ),
        isNull,
      );
    });
  });
}
