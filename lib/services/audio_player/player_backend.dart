abstract interface class PlayerBackend {
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);

  /// Replaces mpv's audio filter chain (`af`).
  ///
  /// mpv has a single chain slot, so callers compose every effect (equalizer,
  /// normalization) into one string; see `buildAudioFilterChain`.
  Future<void> setAudioFilterChain(String chain);

  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<String> get errorStream;

  Future<void> dispose();
}
