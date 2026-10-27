import 'dart:async';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/hooks/controllers/use_shadcn_text_editing_controller.dart';
import 'package:spotube/hooks/utils/use_debounce.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/home/home_search_suggestions.dart';
import 'package:spotube/modules/search/recent_searches.dart';
import 'package:spotube/modules/search/search_term.dart';
import 'package:spotube/provider/metadata_plugin/search/all.dart';

/// Search field pinned to the top of Browse: autocomplete, recent searches,
/// submit-to-history and the shared [searchTermStateProvider], plus a live
/// songs section fed by one debounced search call per pause.
///
/// The suggestion panel is an [OverlayPortal] anchored under the field with
/// a [CompositedTransformFollower], showing grouped rows from
/// [buildSearchSuggestions] computed fresh in build scope. This replaces an
/// earlier `RawAutocomplete` hosting, which could never display results that
/// arrived after typing: a same-text poke notifies nothing (`ValueNotifier`
/// drops equal values), and `RawAutocomplete` discards recomputed options
/// when the field text is unchanged.
///
/// Dismissal is explicit and the panel stays modal: an opaque full-screen
/// barrier absorbs outside taps (nothing behind the panel ever sees them)
/// and every row dismisses itself via [hideAndUnfocus] before acting, so
/// there is no hide timer left to race a row tap.
///
/// Renders a plain box child; `HomePage` mounts it in a `SliverToBoxAdapter`.
/// Deliberately no `autofocus`: focus arrives only via the `Ctrl+Shift+2`
/// shortcut, which bumps [homeSearchFocusRequestProvider].
class HomeSearchBar extends HookConsumerWidget {
  /// A one-line field for a host chrome slot: no Radio button, no outer
  /// gutters, and the dropdown matches the field's own width.
  final bool compact;

  /// Chrome slots name the Spotify placeholder; the page keeps the localized
  /// default.
  final String? placeholder;

  const HomeSearchBar({
    super.key,
    this.compact = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useShadcnTextEditingController();
    final focusNode = useFocusNode();

    final searchTerm = ref.watch(searchTermStateProvider);

    useEffect(() {
      controller.text = searchTerm;

      return null;
    }, []);

    // Shortcut-driven focus: reveal the bar in the enclosing scroll view,
    // then hand it keyboard focus. Deferred a frame so the shortcut's own
    // navigation settles first; a counter (not a bool) so repeated presses
    // re-fire.
    ref.listen(homeSearchFocusRequestProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
        );
        focusNode.requestFocus();
      });
    });

    // Anchor + portal for the dropdown. Dismissal is explicit: rows and the
    // barrier call hideAndUnfocus before acting, so hiding never races a tap.
    final layerLink = useMemoized(() => LayerLink());
    final portalController = useMemoized(() => OverlayPortalController());
    // Measured only so the dropdown can be as tall as the room under the
    // field instead of a fixed 360px that clips the last row.
    final fieldKey = useMemoized(() => GlobalKey());

    void hideAndUnfocus() {
      if (portalController.isShowing) portalController.hide();
      focusNode.unfocus();
    }

    // Keyboard selection. `null` means no row is highlighted yet, so the first
    // ArrowDown lands on the first row and Enter still submits the term.
    final activeIndex = useState<int?>(null);
    // The rows are computed further down, but Enter reaches the field's
    // onSubmitted, which is defined above them — same ref idiom as `showRef`.
    final rowsRef = useRef<List<HomeSearchSuggestion>>(const []);

    void submitTerm(String value) {
      ref.read(searchTermStateProvider.notifier).state = value;
      hideAndUnfocus();
      if (value.trim().isEmpty) {
        return;
      }
      ref.read(recentSearchesProvider.notifier).add(value);
      // A chrome field is the whole search affordance: clicking it must focus
      // in place, while submitting is what opens the results page.
      if (compact) {
        context.navigateTo(const SearchRoute());
      }
    }

    /// The single activation path: tapping a row and pressing Enter on a
    /// highlighted row have to do exactly the same thing.
    void activateSuggestion(HomeSearchSuggestion option) {
      activeIndex.value = null;
      switch (option) {
        case RecentSearchSuggestion(:final term):
        case SeeAllSearchSuggestion(:final term):
          submitTerm(term);
        case LibrarySearchSuggestion():
          hideAndUnfocus();
          openLibrarySuggestion(context, focusNode, option);
      }
    }

    void onSubmitted(String value) {
      final highlighted = activeIndex.value;
      final rows = rowsRef.value;
      if (highlighted != null && highlighted < rows.length) {
        activateSuggestion(rows[highlighted]);
        return;
      }
      submitTerm(value);
    }

    void onCleared() {
      controller.clear();
      // Restoring Browse is part of clearing here (the old page kept the
      // submitted term until the next submit); an empty submit is a no-op
      // for history.
      ref.read(searchTermStateProvider.notifier).state = "";
      focusNode.unfocus();
    }

    // Mirror the field into state so the panel (below) and the debounce
    // recompute on every keystroke.
    final fieldText = useState(controller.text);
    useEffect(() {
      void listener() {
        fieldText.value = controller.text;
        // The rows are about to change, so a highlight kept across a
        // keystroke would point at a different suggestion.
        activeIndex.value = null;
      }

      controller.addListener(listener);
      return () => controller.removeListener(listener);
    }, [controller]);

    final focused = useState(focusNode.hasFocus);
    useEffect(() {
      void listener() => focused.value = focusNode.hasFocus;
      focusNode.addListener(listener);
      return () => focusNode.removeListener(listener);
    }, [focusNode]);

    // A real mouse press on a row moves primary focus off the field at
    // pointer-down; with a mouse, down and up arrive across frames. Without
    // this pin the focus-loss would hide the panel mid-gesture, unmounting
    // the row's button before pointer-up, so the tap never completes and
    // every row click does nothing (widget tests miss it: tester.tap
    // delivers down and up within one frame).
    final panelPointerDown = useState(false);

    // The panel is "on screen" while either holds. Everything that decides
    // which rows exist must read this, not `focused` alone: a desktop press
    // takes focus off the field at pointer-down, and a group gated on focus
    // would delete the rows under the pointer before pointer-up arrives.
    final panelVisible = focused.value || panelPointerDown.value;

    // One gated network call per pause in typing, only while the panel is
    // open (focused) and the query is worth sending. `autoDispose.family`
    // caches repeats; only the current term's instance is rendered.
    // Clear-path guard: a cleared field kills live immediately instead of
    // showing the stale debounce value for a beat.
    final debounced = useDebounce(fieldText.value);
    final fieldEmpty = fieldText.value.trim().isEmpty;
    final liveQuery =
        !fieldEmpty && panelVisible && debounced.trim().length >= 2
            ? debounced.trim()
            : null;
    final liveSnapshot = liveQuery == null
        ? null
        : ref.watch(metadataPluginSearchAllProvider(liveQuery));
    final liveTracks =
        liveSnapshot?.asData?.value.tracks ?? const <SpotubeFullTrackObject>[];
    final liveLoading =
        liveSnapshot != null && liveSnapshot.isLoading && liveTracks.isEmpty;

    // A chrome field starts unfocused; don't wake the four library providers
    // until someone actually opens the panel.
    final (:tracks, :playlists, :albums, :artists) = panelVisible
        ? readLibrarySnapshot(ref)
        : (
            tracks: const <SpotubeFullTrackObject>[],
            playlists: const <SpotubeSimplePlaylistObject>[],
            albums: const <SpotubeSimpleAlbumObject>[],
            artists: const <SpotubeFullArtistObject>[],
          );
    final recents = ref.watch(recentSearchesProvider);
    final options = buildSearchSuggestions(
      text: fieldText.value,
      // Library fuzzy match runs on the debounce cadence, not per keystroke
      // (same pause as the live call); recents above stay instant.
      libraryQueryText: debounced,
      recents: recents,
      liveTracks: liveTracks,
      tracks: tracks,
      playlists: playlists,
      albums: albums,
      artists: artists,
    );
    // A query that matches nothing still gets the see-all footer, so typing
    // never looks like a dead field.
    final trimmedQuery = fieldText.value.trim();
    final seeAllTerm = trimmedQuery.isEmpty ? null : trimmedQuery;
    final rows = suggestionRowsInPaintOrder(
      options,
      seeAllTerm: seeAllTerm,
    );
    rowsRef.value = rows;

    KeyEventResult onFieldKeyEvent(FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        hideAndUnfocus();
        return KeyEventResult.handled;
      }
      if (rows.isEmpty) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        activeIndex.value = ((activeIndex.value ?? -1) + 1) % rows.length;
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        // Dart's % keeps the result non-negative, so -1 wraps to the last row.
        activeIndex.value = ((activeIndex.value ?? 0) - 1) % rows.length;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // `panelPointerDown` pins the panel through an in-flight gesture: a real
    // press on a row unfocuses the field at pointer-down, and without this the
    // overlay entry would detach before pointer-up, cancelling the tap.
    final showPanel = panelVisible && (rows.isNotEmpty || liveLoading);

    final showRef = useRef(showPanel);
    showRef.value = showPanel;
    useEffect(() {
      // Keyed effects re-run synchronously inside build when the keys
      // change (flutter_hooks framework.dart:473-483 → initHook →
      // scheduleEffect → effect()), i.e. during persistentCallbacks —
      // and both OverlayPortalController.show() and .hide() assert
      // against exactly that phase (Flutter overlay.dart:1966-1979).
      // So both branches defer a frame and re-check the ref: focus may
      // have moved on (or back) before the callback runs.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (showRef.value && !portalController.isShowing) {
          portalController.show();
        } else if (!showRef.value && portalController.isShowing) {
          portalController.hide();
        }
      });
      return null;
    }, [showPanel]);

    // One width for the field and the panel, so the dropdown reads as the
    // field's own shadow instead of a differently-sized card under it. Capped
    // to the viewport rather than to Browse's content column, and applied as a
    // maximum so a narrow window shrinks the field instead of overflowing.
    //
    // A phone is a single full-width column: the desktop Radio button is
    // redundant next to the bottom navigation / Search scope chips, so it is
    // dropped and the field gets 16px gutters instead of the desktop row's
    // 20px + button + gaps.
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = viewportWidth < 640;
    final horizontalGutter = isNarrow ? 16.0 : 20.0;
    final panelWidth =
        min(520.0, viewportWidth - (isNarrow ? 32.0 : 24.0)).toDouble();

    // Spotify-inspired field: pill shape, muted fill for separation from the
    // Browse content below, and extra vertical padding for a comfortable
    // click/touch target. Height comes from the field's own padding, so the
    // suggestion panel's CompositedTransformFollower keeps tracking its
    // bottom edge without any anchor changes.
    final scale = context.theme.scaling;

    Widget buildField(double width) {
      return CompositedTransformTarget(
        key: fieldKey,
        link: layerLink,
        child: OverlayPortal(
          controller: portalController,
          // The pin is not built with `context` on purpose: the navigation
          // callbacks below keep using the bar's own context, which outlives
          // the entry's detach on hide.
          overlayChildBuilder: (overlayContext) => Listener(
            onPointerDown: (_) => panelPointerDown.value = true,
            // Cleared a frame later so the button's tap (which resolves after
            // this up is dispatched) still has its widget tree to complete in.
            onPointerUp: (_) =>
                WidgetsBinding.instance.addPostFrameCallback((_) {
              panelPointerDown.value = false;
            }),
            onPointerCancel: (_) =>
                WidgetsBinding.instance.addPostFrameCallback((_) {
              panelPointerDown.value = false;
            }),
            child: Stack(
              children: [
                // Opaque: absorbs every outside tap so nothing behind the
                // panel ever sees it (modal dismiss, never pass-through).
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: hideAndUnfocus,
                    child: Container(
                      color: const Color(0x0D000000),
                    ),
                  ),
                ),
                CompositedTransformFollower(
                  link: layerLink,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: HomeSearchSuggestionsPanel(
                      maxHeight: suggestionPanelMaxHeight(
                        overlayContext,
                        fieldKey,
                      ),
                      recents: options.recents,
                      live: options.live,
                      library: options.library,
                      query: fieldText.value,
                      seeAllTerm: seeAllTerm,
                      activeIndex: activeIndex.value,
                      liveLoading: liveLoading,
                      onActivate: activateSuggestion,
                      // A cover does both jobs at once: the queue starts on
                      // the row's content and the panel takes the user to its
                      // page. Playback is given the root navigator's context
                      // rather than this bar's, so the route push below cannot
                      // leave it talking to a disposed widget mid-fetch.
                      onPlay: (option) {
                        hideAndUnfocus();
                        unawaited(
                          playLibrarySuggestion(
                            rootNavigatorKey.currentContext!,
                            ref,
                            option,
                          ),
                        );
                        openLibrarySuggestion(context, focusNode, option);
                      },
                      // The cover plays and stops there: the listener asked
                      // for the sound, not a page.
                      onPlayOnly: (option) {
                        hideAndUnfocus();
                        unawaited(
                          playLibrarySuggestion(
                            rootNavigatorKey.currentContext!,
                            ref,
                            option,
                          ),
                        );
                      },
                      // The album named under a song row opens on its own,
                      // without disturbing the queue.
                      onOpenAlbum: (album) {
                        hideAndUnfocus();
                        openLibrarySuggestion(
                          context,
                          focusNode,
                          AlbumSearchSuggestion(album),
                        );
                      },
                      // So does the artist beside it. Credits name a simpler
                      // artist model than a search hit does, so this pushes
                      // the route directly.
                      onOpenArtist: (artist) {
                        hideAndUnfocus();
                        openCreditedArtist(context, focusNode, artist);
                      },
                      onRemoveRecent: (term) {
                        ref.read(recentSearchesProvider.notifier).remove(term);
                      },
                      onClearRecents: () {
                        ref.read(recentSearchesProvider.notifier).clear();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          child: Focus(
            // An ancestor of the field, so it sees the keys the field leaves
            // alone: arrows and Escape. Enter never arrives here — the field
            // consumes it and [onSubmitted] reads the highlight instead.
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onFieldKeyEvent,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  padding: compact
                      ? EdgeInsets.symmetric(horizontal: 14 * scale)
                      : EdgeInsets.symmetric(
                          horizontal: 16 * scale,
                          vertical: 12 * scale,
                        ),
                  borderRadius: compact
                      ? BorderRadius.circular(999)
                      : context.theme.borderRadiusXxl,
                  filled: !compact,
                  // A chrome card owns the pill fill and its hover hue; the
                  // field itself stays transparent so that fill is visible.
                  decoration: compact
                      ? BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        )
                      : null,
                  features: [
                    InputFeature.leading(
                      Icon(
                        SpotubeIcons.search,
                        size: compact ? 18 : null,
                        color: compact
                            ? context.theme.colorScheme.mutedForeground
                            : null,
                      ),
                    ),
                    InputFeature.trailing(
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: controller.text.isNotEmpty
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        firstChild: IconButton.ghost(
                          size: ButtonSize.small,
                          icon: const Icon(SpotubeIcons.close),
                          onPressed: onCleared,
                        ),
                        secondChild: const SizedBox.square(dimension: 28),
                      ),
                    )
                  ],
                  textInputAction: TextInputAction.search,
                  placeholder: Text(placeholder ?? context.l10n.search),
                  onSubmitted: onSubmitted,
                );
              },
            ),
          ),
        ),
      );
    }

    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: 40,
            child: buildField(constraints.maxWidth),
          );
        },
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!isNarrow) ...[
          const Gap(8),
          Button.outline(
            leading: const Icon(SpotubeIcons.radio),
            onPressed: () => context.navigateTo(const RadioRoute()),
            child: const Text('Radio'),
          ),
          const Gap(8),
        ],
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalGutter,
              vertical: isNarrow ? 8 : 12,
            ),
            // Align, not just ConstrainedBox: Expanded hands down a tight
            // width and only loosening it lets the field stop at panelWidth.
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: panelWidth),
                child: buildField(panelWidth),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How tall the suggestion dropdown may grow.
///
/// The portal is a follower anchored to the field's bottom edge, so the panel
/// hangs from there and can only use the space between that edge and the
/// bottom of the window. Measuring the field itself — instead of guessing from
/// the viewport height — is what lets a long result list open at full length,
/// and a short one stay short, without ever running past the window.
double suggestionPanelMaxHeight(
    BuildContext overlayContext, GlobalKey fieldKey) {
  final media = MediaQuery.of(overlayContext);
  // The follower anchors to the field's bottom in global coordinates, so the
  // bottom inset (system nav bar) and the on-screen keyboard have to come off
  // the window height too. Without the keyboard inset the panel grows behind
  // the keyboard on a phone.
  final windowBottom =
      media.size.height - media.padding.bottom - media.viewInsets.bottom;

  final box = fieldKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) {
    // Nothing laid out yet: the conservative default keeps the panel on screen.
    return min(searchSuggestionPanelMaxHeight, windowBottom);
  }

  final fieldBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
  final room = windowBottom - fieldBottom - searchSuggestionPanelBottomGutter;
  // A window shorter than the field still has to render something; clamping at
  // zero hands the panel a scrollable sliver rather than overflowing the view.
  return room.clamp(0.0, windowBottom).toDouble();
}
