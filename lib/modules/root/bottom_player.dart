import 'package:auto_route/auto_route.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/assets.gen.dart';
import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/app_layout/app_layout.dart';
import 'package:spotube/modules/player/player_actions.dart';
import 'package:spotube/modules/player/player_overlay.dart';
import 'package:spotube/modules/player/player_progress.dart';
import 'package:spotube/modules/player/player_track_details.dart';
import 'package:spotube/modules/player/player_controls.dart';
import 'package:spotube/modules/player/volume_slider.dart';
import 'package:spotube/extensions/constrains.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/utils/theme_converter.dart';

import 'package:spotube/provider/volume_provider.dart';
import 'package:spotube/provider/radio/radio_playback.dart';
import 'package:spotube/modules/player/radio/radio_player_bar.dart';
import 'package:spotube/modules/player/radio/radio_player_overlay.dart';
import 'package:spotube/modules/theme_background/real_transparency.dart';
import 'package:spotube/modules/theme_ui/theme_ui_host.dart';

/// The floating player's height, measured after layout.
///
/// Theme player slots can make the bar taller than the host's historic
/// estimate, so the sidebar reserves the real height.
final bottomPlayerHeightProvider = StateProvider<double>((ref) => 0);

/// Reports [BottomPlayer]'s laid-out height to [bottomPlayerHeightProvider].
class MeasuredBottomPlayer extends ConsumerStatefulWidget {
  final Widget child;

  const MeasuredBottomPlayer({required this.child, super.key});

  @override
  ConsumerState<MeasuredBottomPlayer> createState() =>
      _MeasuredBottomPlayerState();
}

class _MeasuredBottomPlayerState extends ConsumerState<MeasuredBottomPlayer> {
  final _key = GlobalKey();
  double? _reported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _report() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final height = box.size.height;
    if (height == _reported) return;
    _reported = height;
    ref.read(bottomPlayerHeightProvider.notifier).state = height;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: KeyedSubtree(key: _key, child: widget.child),
      ),
    );
  }
}

class BottomPlayer extends HookConsumerWidget {
  /// Draws the in-flow bar even where the host would normally swap in the
  /// sliding [PlayerOverlay].
  ///
  /// A shell layout that placed a `player` region has already decided the bar
  /// belongs in flow at that size; the overlay needs the full-window footer
  /// slot and cannot be positioned inside a 72px region.
  final bool forceBar;

  const BottomPlayer({this.forceBar = false, super.key});

  @override
  Widget build(BuildContext context, ref) {
    final activeTrack =
        ref.watch(audioPlayerProvider.select((s) => s.activeTrack));
    final layoutMode =
        ref.watch(userPreferencesProvider.select((s) => s.layoutMode));
    // Context-aware source: while a radio station owns audio focus, the bar
    // swaps to radio content. Everything below stays the untouched music tree.
    final isRadio =
        ref.watch(radioPlaybackControllerProvider.select((s) => s.isRadio));
    // The responsive expression of the player layout, resolved in main.dart.
    final playerLayout = context.layout.player;
    final userVolumeMode =
        ref.watch(userPreferencesProvider.select((s) => s.volumeControlMode));
    // The theme can hide the control; otherwise the user's preference stands.
    final volumeOverride = context.volumeOverride;
    final hasThemeLeading = themeUiSlotExists(ref, 'player.leading');
    final hasThemeControls = themeUiSlotExists(ref, 'player.controls');
    final hasThemeTrailing = themeUiSlotExists(ref, 'player.trailing');
    final hasThemeProgress = themeUiSlotExists(ref, 'player.progress');

    // A theme may give the footer its own surface (Spotify's player is black
    // against a #121212 page). No component means the host surface stands.
    final themeDefinition = ref.watch(themeDefinitionProvider).asData?.value;
    final rawPlayerStyle = themeDefinition?.components['player'];
    final playerStyle = rawPlayerStyle is Map
        ? rawPlayerStyle.cast<String, dynamic>()
        : const <String, dynamic>{};
    final playerBackground =
        _themePlayerColor(context, playerStyle['background']);
    final playerBorderColor =
        _themePlayerColor(context, playerStyle['borderColor']);
    final rawBorderWidth = playerStyle['borderWidth'];
    final playerBorderWidth = rawBorderWidth is num
        ? rawBorderWidth.toDouble().clamp(0.0, 8.0).toDouble()
        : null;

    // The window breakpoint is not the player's breakpoint: a docked player
    // can be only ~700px wide at a 900px window. Volume is the widest optional
    // control, so drop it before the row has to overflow. The full-width
    // footer has no width scope and falls back to the window width.
    final playerWidth =
        PlayerSeekWidth.maybeOf(context) ?? MediaQuery.sizeOf(context).width;
    final showVolume =
        (volumeOverride ?? userVolumeMode != VolumeControlMode.hidden) &&
            playerWidth >= 800;

    String albumArt = useMemoized(
      () => activeTrack?.album.images.isNotEmpty == true
          ? (activeTrack?.album.images).asUrlString(
              index: (activeTrack?.album.images.length ?? 1) - 1,
              placeholder: ImagePlaceholder.albumArt,
            )
          : Assets.images.albumPlaceholder.path,
      [activeTrack?.album.images],
    );

    // returning an empty non spacious Container as the overlay will take
    // place in the global overlay stack aka [_entries]
    if (!forceBar && !bottomPlayerVisibleOf(context, layoutMode)) {
      return isRadio
          ? const RadioPlayerOverlay()
          : PlayerOverlay(albumArt: albumArt);
    }

    // Radio owns audio focus: swap the docked bar to radio content. This is
    // placed before `progressBelow` is read, so the radio bar never touches the
    // music seek-line layout. When `isRadio` is false, the tree below is
    // byte-identical to the original music player.
    if (isRadio) return const RadioBottomPlayer();

    // `progress: below` pulls the seek bar out of the transport column and
    // stretches it across the whole player. The extra wrapper only appears with
    // that switch, so a theme that asks for nothing gets the tree it always had.
    final progressBelow = context.progressBelow;
    final bar = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: hasThemeLeading
              ? const ThemeSlot('player.leading')
              : playerLayout.showTrackDetails
                  ? PlayerTrackDetails(track: activeTrack)
                  : const SizedBox.shrink(),
        ),
        // controls
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: hasThemeControls
                ? const ThemeSlot(
                    'player.controls',
                    crossAxisAlignment: CrossAxisAlignment.center,
                  )
                : PlayerControls(progressInline: !progressBelow),
          ),
        ),
        // add to saved tracks
        if (hasThemeTrailing)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ThemeSlot('player.trailing'),
              if (showVolume) BottomPlayerVolume(forceVisible: volumeOverride),
            ],
          )
        else if (playerLayout.showActions || showVolume)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playerLayout.showActions)
                PlayerActions(
                  extraActions: [
                    if (playerLayout.showLyrics)
                      Tooltip(
                        tooltip: TooltipContainer(
                          child: Text(context.l10n.lyrics),
                        ).call,
                        child: IconButton(
                          variance: ButtonVariance.ghost,
                          icon: const Icon(SpotubeIcons.lyrics),
                          onPressed: activeTrack != null
                              ? () => context.navigateTo(const LyricsRoute())
                              : null,
                        ),
                      ),
                  ],
                ),
              if (showVolume) BottomPlayerVolume(forceVisible: volumeOverride),
            ],
          ),
      ],
    );

    final realTransparent = ref.watch(realTransparencyActiveProvider);
    return SurfaceCard(
      borderRadius: BorderRadius.zero,
      // In-app blur over a transparent window samples nothing (the
      // compositor owns blur here) while still costing a filter per frame —
      // off with it, same rule as the title bar and the nav bar.
      surfaceBlur: realTransparent ? 0 : context.theme.surfaceBlur,
      // Footer chrome, not content: transparent with the ground while real
      // transparency owns the window (`fillColor` only applies with
      // `filled`, so both flip together).
      filled: realTransparent || playerBackground != null ? true : null,
      fillColor: realTransparent ? Colors.transparent : playerBackground,
      borderColor: realTransparent ? null : playerBorderColor,
      borderWidth: realTransparent ? null : playerBorderWidth,
      child: !playerLayout.showProgress
          ? bar
          : hasThemeProgress
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bar,
                    const ThemeSlot('player.progress'),
                  ],
                )
              : !progressBelow
                  ? bar
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        bar,
                        const PlayerProgress(inline: false),
                      ],
                    ),
    );
  }
}

/// The bottom bar's volume control, which is the only part of it whose
/// visibility the user can change. Its own widget so the preference watch and
/// the volume watch stay off [BottomPlayer]'s rebuild path.
class BottomPlayerVolume extends HookConsumerWidget {
  /// Overrides the user's visibility preference when the theme claimed
  /// `volume`: true forces the control, false removes it.
  final bool? forceVisible;

  const BottomPlayerVolume({super.key, this.forceVisible});

  @override
  Widget build(BuildContext context, ref) {
    final mode =
        ref.watch(userPreferencesProvider.select((s) => s.volumeControlMode));
    if (forceVisible == false) return const SizedBox.shrink();
    if (forceVisible == null && mode == VolumeControlMode.hidden) {
      return const SizedBox.shrink();
    }

    final volume = ref.watch(volumeProvider);
    return Container(
      height: 40,
      // The bar's third column sits in the Row's unbounded main axis, so this
      // bound is what lets the slider row resolve a width at all.
      constraints: const BoxConstraints(maxWidth: 250),
      padding: const EdgeInsets.only(right: 10),
      child: VolumeSlider(
        fullWidth: true,
        revealOnHover: mode == VolumeControlMode.hover,
        value: volume,
        onChanged: (value) {
          ref.read(volumeProvider.notifier).setVolume(value);
        },
      ),
    );
  }
}

/// Whether [BottomPlayer] draws the bar at the foot of the window.
///
/// The narrow layouts get a floating [PlayerOverlay] instead, which occupies
/// nothing in the layout — so anything reserving space for this bar has to ask
/// first. The sidebar's bottom reservation is the one that matters: a
/// reservation made for a bar that is not there just lifts the profile row off
/// the bottom edge, while one missing for a bar that is there hides the
/// settings button behind it.
bool bottomPlayerVisibleOf(BuildContext context, LayoutMode layoutMode) {
  if (layoutMode == LayoutMode.compact) return false;
  if (layoutMode != LayoutMode.adaptive) return true;
  return !MediaQuery.sizeOf(context).mdAndDown;
}

/// Resolves the small role subset a player surface may name.
///
/// The theme node renderer has the full role table; the footer only needs the
/// neutral surfaces and the accent, so an unknown role falls back to the
/// host's own fill instead of guessing at a colour.
Color? _themePlayerColor(BuildContext context, Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  if (raw.startsWith('@')) {
    final scheme = Theme.of(context).colorScheme;
    return switch (raw.substring(1)) {
      'background' => scheme.background,
      'foreground' => scheme.foreground,
      'card' => scheme.card,
      'cardForeground' => scheme.cardForeground,
      'sidebar' => scheme.sidebar,
      'sidebarForeground' => scheme.sidebarForeground,
      'primary' => scheme.primary,
      'primaryForeground' => scheme.primaryForeground,
      'border' => scheme.border,
      _ => null,
    };
  }
  try {
    return ThemeConverter.parseColor(raw);
  } catch (_) {
    return null;
  }
}
