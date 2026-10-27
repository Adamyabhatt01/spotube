import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/audio_player_port.dart';

/// Container-scoped access to the music player.
///
/// The value is still the process-wide media_kit player; this is the injection
/// seam, not a second backend. Tests override it with a fake, and a future
/// backend can be swapped in without touching call sites.
final audioPlayerPortProvider =
    Provider<AudioPlayerPort>((_) => audioPlayer);
