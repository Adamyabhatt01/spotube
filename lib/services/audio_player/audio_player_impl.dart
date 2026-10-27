part of 'audio_player.dart';

final AudioPlayerPort audioPlayer = SpotubeAudioPlayer();

class SpotubeAudioPlayer extends AudioPlayerInterface
    with SpotubeAudioPlayersStreams
    implements AudioPlayerPort {
  @override
  Future<void> pause() async {
    await _mkPlayer.pause();
  }

  @override
  Future<void> resume() async {
    await _mkPlayer.play();
  }

  @override
  Future<void> stop() async {
    await _mkPlayer.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    // A seek can land inside the second that was already reported, so the
    // shared tick gate is told to let the next position event through.
    _invalidatePositionTick();
    await _mkPlayer.seek(position);
  }

  /// Volume is between 0 and 1
  @override
  Future<void> setVolume(double volume) async {
    assert(volume >= 0 && volume <= 1);
    await _mkPlayer.setVolume(volume * 100);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _mkPlayer.setRate(speed);
  }

  @override
  Future<void> setAudioDevice(mk.AudioDevice device) async {
    await _mkPlayer.setAudioDevice(device);
  }

  @override
  Future<void> dispose() async {
    await _positionTicker?.dispose();
    _positionTicker = null;
    await _mkPlayer.dispose();
  }

  @override
  Future<void> openPlaylist(
    List<mk.Media> tracks, {
    bool autoPlay = true,
    int initialIndex = 0,
  }) async {
    assert(tracks.isNotEmpty);
    assert(initialIndex <= tracks.length - 1);
    await _mkPlayer.open(
      mk.Playlist(tracks, index: initialIndex),
      play: autoPlay,
    );
  }

  @override
  List<String> get sources {
    return _mkPlayer.state.playlist.medias.map((e) => e.uri).toList();
  }

  @override
  String? get currentSource {
    if (_mkPlayer.state.playlist.index == -1) return null;
    return _mkPlayer.state.playlist.medias
        .elementAtOrNull(_mkPlayer.state.playlist.index)
        ?.uri;
  }

  @override
  String? get nextSource {
    if (loopMode == PlaylistMode.loop &&
        _mkPlayer.state.playlist.index ==
            _mkPlayer.state.playlist.medias.length - 1) {
      return sources.first;
    }

    return _mkPlayer.state.playlist.medias
        .elementAtOrNull(_mkPlayer.state.playlist.index + 1)
        ?.uri;
  }

  @override
  String? get previousSource {
    if (loopMode == PlaylistMode.loop && _mkPlayer.state.playlist.index == 0) {
      return sources.last;
    }

    return _mkPlayer.state.playlist.medias
        .elementAtOrNull(_mkPlayer.state.playlist.index - 1)
        ?.uri;
  }

  @override
  int get currentIndex => _mkPlayer.state.playlist.index;

  @override
  Future<void> skipToNext() async {
    await _mkPlayer.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _mkPlayer.previous();
  }

  @override
  Future<void> jumpTo(int index) async {
    await _mkPlayer.jump(index);
  }

  @override
  Future<void> addTrack(mk.Media media) async {
    await _mkPlayer.add(media);
  }

  @override
  Future<void> addTrackAt(mk.Media media, int index) async {
    await _mkPlayer.insert(index, media);
  }

  @override
  Future<void> removeTrack(int index) async {
    await _mkPlayer.remove(index);
  }

  @override
  Future<void> moveTrack(int from, int to) async {
    await _mkPlayer.move(from, to);
  }

  @override
  Future<void> clearPlaylist() async {
    _mkPlayer.stop();
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    await _mkPlayer.setShuffle(shuffle);
  }

  @override
  Future<void> setLoopMode(PlaylistMode loop) async {
    await _mkPlayer.setPlaylistMode(loop);
  }

  @override
  Future<void> setAudioNormalization(bool normalize) async {
    await _mkPlayer.setAudioNormalization(normalize);
  }

  @override
  Future<void> setDemuxerBufferSize(int sizeInBytes) async {
    await _mkPlayer.setDemuxerBufferSize(sizeInBytes);
  }
}
