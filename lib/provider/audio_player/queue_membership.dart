import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';

/// Queue membership as precomputed sets, rebuilt once per queue revision.
///
/// Previously every mounted track row watched the whole queue list and ran
/// its own O(queue) `.any()` scan, so one queue mutation cost N rows × Q
/// compares plus N provider rebuilds. Now the O(Q) work happens once here
/// and each row selects its own boolean out of it.
///
/// Three sets rather than one, because the predicate is domain-separated
/// ([listContainsTrack]): a local track matches local entries by path and
/// remote entries by id, while a remote track matches everything by id. A
/// single merged set would let a local path collide with a remote id domain.
/// The three sets reproduce that predicate exactly — see
/// [isTrackInQueue] and its equivalence test.
typedef QueueMembership = ({
  /// Ids of every track in the queue, local or remote.
  Set<String> ids,

  /// Ids of the non-local tracks only (the id domain a local row compares).
  Set<String> remoteIds,

  /// File paths of the local tracks only (the path domain).
  Set<String> paths,
});

final queueMembershipProvider = Provider<QueueMembership>((ref) {
  final tracks = ref.watch(audioPlayerProvider.select((s) => s.tracks));
  final ids = <String>{};
  final remoteIds = <String>{};
  final paths = <String>{};
  for (final track in tracks) {
    ids.add(track.id);
    if (track is SpotubeLocalTrackObject) {
      paths.add(track.path);
    } else {
      remoteIds.add(track.id);
    }
  }
  return (ids: ids, remoteIds: remoteIds, paths: paths);
});

/// Whether [track] is in the queue described by [membership].
///
/// Exactly [listContainsTrack] with the loop already run: a local track
/// matches a same-path local entry or a same-id remote entry, anything else
/// matches by id. An empty queue matches nothing.
bool isTrackInQueue(QueueMembership membership, SpotubeTrackObject track) {
  if (track is SpotubeLocalTrackObject) {
    return membership.paths.contains(track.path) ||
        membership.remoteIds.contains(track.id);
  }
  return membership.ids.contains(track.id);
}

/// One row's membership as a subscribable boolean.
///
/// The family instance subscribes to [queueMembershipProvider] through a
/// `select` on this row's predicate, so an unrelated queue mutation rebuilds
/// the shared set once and only rows whose own boolean flips notify.
final trackMembershipOfProvider =
    Provider.autoDispose.family<bool, SpotubeTrackObject>((ref, track) {
  return ref.watch(
    queueMembershipProvider.select((m) => isTrackInQueue(m, track)),
  );
});
