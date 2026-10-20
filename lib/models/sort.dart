/// The sort order shared by the library, the local-folder view and
/// `ServiceUtils.sortTracks`. Lives in `lib/models/` (not in the local-library
/// page it used to sit in) so the utils and component layers can import it
/// without a utils→pages inversion.
enum SortBy {
  none,
  ascending,
  descending,
  newest,
  oldest,
  duration,
  artist,
  album,
}
