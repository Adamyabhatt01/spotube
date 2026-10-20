import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The submitted search term shared between [HomeSearchBar] and the search
/// result tabs/sections. Empty/blank means "not searching": Browse renders
/// its normal sections. Moved here from the deleted `SearchPage` so the
/// result tabs keep a single source of truth without importing a page.
final searchTermStateProvider = StateProvider<String>((ref) {
  return "";
});

/// Focus-request counter for the Browse search field. The `Ctrl+Shift+2`
/// shortcut (`HomeTabs.search`) navigates home and bumps this; a counter —
/// not a boolean — so repeated presses produce distinct requests.
/// [HomeSearchBar] watches it, scrolls into view and focuses its field.
final homeSearchFocusRequestProvider = StateProvider<int>((ref) => 0);
