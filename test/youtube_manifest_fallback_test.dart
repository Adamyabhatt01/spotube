// A bot-gated YouTube video is not a missing video.
//
// The selected engine can see a track (search and metadata work) while its
// manifest endpoint is refused with "Sign in to confirm you're not a bot".
// The manifest is the one call where a different extractor can still answer,
// so it is the one call that widens. These tests pin the failure taxonomy:
// a fallback that works is used, empty manifests are skipped, and when every
// engine fails the selected engine's error survives with its stack.
import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/services/youtube_engine/manifest_fallback.dart';
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http_parser/http_parser.dart';

StreamManifest _manifest(String url) {
  return StreamManifest([
    AudioOnlyStreamInfo(
      VideoId('rcmgM9ca3sU'),
      0,
      Uri.parse(url),
      StreamContainer.parse('webm'),
      FileSize.unknown,
      const Bitrate(128000),
      'opus',
      'medium',
      const [],
      MediaType.parse('audio/webm'),
      null,
    ),
  ]);
}

class _FakeEngine implements YouTubeEngine {
  _FakeEngine(this.name, {this.manifest, this.error, this.onCall});

  final String name;
  final StreamManifest? manifest;
  final Object? error;
  final void Function()? onCall;

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    onCall?.call();
    if (error != null) throw error!;
    return manifest!;
  }

  @override
  Future<Video> getVideo(String videoId) => throw UnimplementedError();

  @override
  Future<List<YouTubeSearchResult>> searchVideos(String query) =>
      throw UnimplementedError();
}

void main() {
  test('uses the fallback when the selected engine is bot-gated', () async {
    final blocked = Exception("Sign in to confirm you're not a bot");
    final fallback = _FakeEngine('yt-dlp', manifest: _manifest('a'));

    final result = await streamManifestWithFallback(
      videoId: 'video',
      chain: [_FakeEngine('explode', error: blocked), fallback],
    );

    expect(result.audioOnly.single.url.toString(), 'a');
  });

  test('tries the fallback when the selected engine returns no audio', () async {
    final empty = _FakeEngine('explode', manifest: StreamManifest(const []));
    final fallback = _FakeEngine('yt-dlp', manifest: _manifest('b'));

    final result = await streamManifestWithFallback(
      videoId: 'video',
      chain: [empty, fallback],
    );

    expect(result.audioOnly.single.url.toString(), 'b');
  });

  test('stops at the first engine that answers', () async {
    var laterCalls = 0;
    final result = await streamManifestWithFallback(
      videoId: 'video',
      chain: [
        _FakeEngine('explode', manifest: _manifest('first')),
        _FakeEngine('yt-dlp', manifest: _manifest('later'), onCall: () {
          laterCalls++;
        }),
      ],
    );

    expect(result.audioOnly.single.url.toString(), 'first');
    expect(laterCalls, 0);
  });

  test('rethrows the selected engine error when every engine fails', () async {
    final first = Exception('first failure');
    final second = Exception('second failure');

    await expectLater(
      streamManifestWithFallback(
        videoId: 'video',
        chain: [
          _FakeEngine('explode', error: first),
          _FakeEngine('yt-dlp', error: second),
        ],
      ),
      throwsA(same(first)),
    );
  });

  test('keeps the selected error when fallbacks answer empty', () async {
    final blocked = Exception('bot gate');

    await expectLater(
      streamManifestWithFallback(
        videoId: 'video',
        chain: [
          _FakeEngine('explode', error: blocked),
          _FakeEngine('yt-dlp', manifest: StreamManifest(const [])),
        ],
      ),
      throwsA(same(blocked)),
    );
  });

  test('the selected engine is always first in the chain', () {
    final primary = _FakeEngine('explode');
    expect(manifestFallbackChain(primary).first, same(primary));
  });
}
