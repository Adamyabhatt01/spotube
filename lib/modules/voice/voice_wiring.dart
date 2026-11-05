// The app-side half of voice commands: subscribes to the controller's event
// stream once, runs every heard command through the executor, and turns the
// report back into navigation, a chooser or a toast — the three things an
// executor deliberately cannot do without a BuildContext. Also owns the
// mic-status pill: the only always-visible sign that the microphone is open.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart'
    hide AlertDialog, Tooltip, showDialog;
import 'package:shadcn_flutter/shadcn_flutter_extension.dart';

import 'package:spotube/collections/routes.gr.dart';
import 'package:spotube/collections/routes.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/voice/voice_config_provider.dart';
import 'package:spotube/provider/voice/voice_controller_provider.dart';
import 'package:spotube/provider/voice/voice_executor.dart';
import 'package:spotube/services/voice/config/voice_config.dart';
import 'package:spotube/services/voice/engine/voice_engine.dart';

class VoiceWiring extends ConsumerStatefulWidget {
  const VoiceWiring({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VoiceWiring> createState() => _VoiceWiringState();
}

class _VoiceWiringState extends ConsumerState<VoiceWiring> {
  StreamSubscription<VoiceEvent>? _events;
  String _partial = '';

  @override
  void initState() {
    super.initState();
    // The controller is a NotifierProvider: reading `.notifier` here builds it
    // once for the app's lifetime, which is what keeps the mic owner singular.
    _events = ref.read(voiceControllerProvider.notifier).events.listen(
          _onEvent,
        );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _onEvent(VoiceEvent event) async {
    switch (event) {
      case TranscriptTickEvent(:final partial):
        if (mounted) setState(() => _partial = partial);
      case CommandHeardEvent():
        if (event.suppressed) return;
        final report = await ref
            .read(voiceExecutorProvider)
            .execute(event);
        if (!mounted) return;
        await _handleReport(report);
      case VoiceWindowClosedEvent():
        if (mounted) setState(() => _partial = '');
      default:
        break;
    }
  }

  Future<void> _handleReport(VoiceCommandReport report) async {
    // This widget sits above AutoRouter, so page navigation goes through the
    // root navigator key — the same path track_options uses for context-free
    // actions. Dialogs and toasts still use this widget's own context.
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !mounted) return;

    if (report.playlistCandidates.isNotEmpty) {
      await _choosePlaylist(report.playlistCandidates);
      return;
    }
    switch (report.page) {
      case VoicePage.searchResults:
        navContext.navigateTo(const SearchRoute());
      case VoicePage.queue:
        navContext.pushRoute(const PlayerQueueRoute());
      case null:
        break;
    }
    if (!report.understood || report.notFound) {
      _toast(
        report.notFound
            ? context.l10n.voice_playlist_not_found
            : context.l10n.voice_not_understood,
      );
    }
  }

  Future<void> _choosePlaylist(
    List<SpotubeSimplePlaylistObject> candidates,
  ) async {
    final picked = await showDialog<SpotubeSimplePlaylistObject>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.voice_choose_playlist),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final playlist in candidates)
                ListTile(
                  dense: true,
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(dialogContext, playlist),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(voiceExecutorProvider).play(picked);
    }
  }

  void _toast(String message) {
    showToast(
      context: context,
      builder: (context, overlay) => SurfaceCard(child: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(voiceConfigProvider);
    final controller = ref.watch(voiceControllerProvider);
    if (!config.enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 16,
          bottom: 96,
          child: _MicPill(
            phase: controller.phase,
            detail: controller.detail,
            partial: _partial,
            mode: config.mode,
            onTap: () => _toggleWindow(config.mode),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleWindow(VoiceMode mode) async {
    final notifier = ref.read(voiceControllerProvider.notifier);
    if (mode == VoiceMode.tapToTalk) {
      final phase = ref.read(voiceControllerProvider).phase;
      if (phase == VoiceControllerPhase.windowOpen) {
        await notifier.endTapWindow();
      } else {
        await notifier.beginTapWindow();
      }
    }
  }
}

class _MicPill extends StatelessWidget {
  const _MicPill({
    required this.phase,
    required this.detail,
    required this.partial,
    required this.mode,
    required this.onTap,
  });

  final VoiceControllerPhase phase;
  final String? detail;
  final String partial;
  final VoiceMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label, active) = switch (phase) {
      VoiceControllerPhase.disabled => (
          SpotubeIcons.micOff,
          context.l10n.voice_status_off,
          false,
        ),
      VoiceControllerPhase.ready => (
          SpotubeIcons.mic,
          context.l10n.voice_status_ready,
          false,
        ),
      VoiceControllerPhase.listening => (
          SpotubeIcons.mic,
          context.l10n.voice_status_listening,
          true,
        ),
      VoiceControllerPhase.windowOpen => (
          SpotubeIcons.mic,
          partial.isEmpty
              ? context.l10n.voice_status_window
              : partial,
          true,
        ),
      VoiceControllerPhase.testing => (
          SpotubeIcons.mic,
          context.l10n.voice_status_testing,
          true,
        ),
      VoiceControllerPhase.missingModels => (
          SpotubeIcons.micOff,
          context.l10n.voice_status_missing_models,
          false,
        ),
      VoiceControllerPhase.noMicrophone => (
          SpotubeIcons.micOff,
          context.l10n.voice_status_no_microphone,
          false,
        ),
      VoiceControllerPhase.failed => (
          SpotubeIcons.micOff,
          context.l10n.voice_status_failed,
          false,
        ),
    };

    return Tooltip(
      message: detail ?? label,
      child: GestureDetector(
        onTap: mode == VoiceMode.tapToTalk ? onTap : null,
        child: SurfaceCard(
          child: Basic(
            leading: Icon(icon),
            title: Text(label, maxLines: 1),
            trailing: active
                ? const _PulseDot()
                : null,
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: context.theme.colorScheme.destructive,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
