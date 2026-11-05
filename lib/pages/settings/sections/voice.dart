import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ListTile;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/adaptive/adaptive_select_tile.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/modules/settings/section_card_with_heading.dart';
import 'package:spotube/provider/voice/voice_config_provider.dart';
import 'package:spotube/provider/voice/voice_controller_provider.dart';
import 'package:spotube/services/voice/config/voice_config.dart';
import 'package:spotube/services/voice/matching/text_normalizer.dart';
import 'package:spotube/services/voice/models/voice_model_registry.dart';

class SettingsVoiceSection extends ConsumerWidget {
  const SettingsVoiceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(voiceConfigProvider);
    final controller = ref.watch(voiceControllerProvider);
    final notifier = ref.read(voiceConfigProvider.notifier);
    final controllerNotifier = ref.read(voiceControllerProvider.notifier);

    return SectionCardWithHeading(
      heading: context.l10n.voice_commands,
      children: [
        AdaptiveSelectTile<VoiceMode>(
          secondary: const Icon(SpotubeIcons.mic),
          title: Text(context.l10n.voice_mode),
          subtitle: Text(switch (config.mode) {
            VoiceMode.off => context.l10n.voice_mode_off_description,
            VoiceMode.tapToTalk => context.l10n.voice_mode_tap_description,
            VoiceMode.wake => context.l10n.voice_mode_wake_description,
          }),
          value: config.mode,
          onChanged: (mode) {
            if (mode != null) notifier.setMode(mode);
          },
          options: [
            for (final mode in VoiceMode.values)
              SelectItemButton(
                value: mode,
                child: Text(switch (mode) {
                  VoiceMode.off => context.l10n.voice_mode_off,
                  VoiceMode.tapToTalk => context.l10n.voice_mode_tap,
                  VoiceMode.wake => context.l10n.voice_mode_wake,
                }),
              ),
          ],
        ),
        if (config.enabled) ...[
          AdaptiveSelectTile<VoiceLanguage>(
            secondary: const Icon(SpotubeIcons.language),
            title: Text(context.l10n.voice_language),
            value: config.primaryLanguage,
            onChanged: (lang) {
              if (lang != null) {
                notifier.setPrimaryLanguage(lang);
                // ignore: discarded_futures
                controllerNotifier.pruneUnusedModels();
              }
            },
            options: [
              for (final lang in VoiceLanguage.values)
                SelectItemButton(
                  value: lang,
                  child: Text(_languageLabel(context, lang)),
                ),
            ],
          ),
          AdaptiveSelectTile<VoiceLanguage?>(
            secondary: const Icon(SpotubeIcons.language),
            title: Text(context.l10n.voice_secondary_language),
            subtitle: Text(
              config.secondaryLanguage == null
                  ? context.l10n.voice_language_none
                  : _languageLabel(context, config.secondaryLanguage!),
            ),
            value: config.secondaryLanguage,
            onChanged: notifier.setSecondaryLanguage,
            options: [
              const SelectItemButton<VoiceLanguage?>(
                value: null,
                child: Text('—'),
              ),
              for (final lang in VoiceLanguage.values)
                if (lang != config.primaryLanguage)
                  SelectItemButton<VoiceLanguage?>(
                    value: lang,
                    child: Text(_languageLabel(context, lang)),
                  ),
            ],
          ),
          ListTile(
            leading: const Icon(SpotubeIcons.mic),
            title: Text(context.l10n.voice_listen_minimized),
            subtitle: Text(context.l10n.voice_listen_minimized_description),
            trailing: Switch(
              value: config.listenWhileMinimized,
              onChanged: notifier.setListenWhileMinimized,
            ),
          ),
          _ModelsTile(controller: controller, onInstall: () {
            // ignore: discarded_futures
            controllerNotifier.installModels(
              cancelToken: CancelToken(),
              onProgress: (_) {},
            );
          }),
          if (controller.phase == VoiceControllerPhase.missingModels ||
              controller.phase == VoiceControllerPhase.noMicrophone ||
              controller.phase == VoiceControllerPhase.failed ||
              controller.phase == VoiceControllerPhase.testing)
            ListTile(
              leading: const Icon(SpotubeIcons.error),
              title: Text(_phaseLabel(context, controller.phase)),
              subtitle: controller.detail == null
                  ? null
                  : Text(controller.detail!),
            ),
        ],
      ],
    );
  }

  String _languageLabel(BuildContext context, VoiceLanguage lang) {
    final supported = voiceCommandsSupported(
      primary: lang,
      secondary: null,
    );
    final name = switch (lang) {
      VoiceLanguage.en => context.l10n.voice_lang_en,
      VoiceLanguage.hi => context.l10n.voice_lang_hi,
      VoiceLanguage.es => context.l10n.voice_lang_es,
      VoiceLanguage.fr => context.l10n.voice_lang_fr,
      VoiceLanguage.ar => context.l10n.voice_lang_ar,
    };
    return supported ? name : '$name — ${context.l10n.voice_unavailable}';
  }

  String _phaseLabel(BuildContext context, VoiceControllerPhase phase) =>
      switch (phase) {
        VoiceControllerPhase.missingModels =>
          context.l10n.voice_status_missing_models,
        VoiceControllerPhase.noMicrophone =>
          context.l10n.voice_status_no_microphone,
        VoiceControllerPhase.failed => context.l10n.voice_status_failed,
        VoiceControllerPhase.testing => context.l10n.voice_status_testing,
        _ => context.l10n.voice_status_off,
      };
}

class _ModelsTile extends ConsumerWidget {
  const _ModelsTile({required this.controller, required this.onInstall});

  final VoiceControllerState controller;
  final void Function() onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = controller.phase == VoiceControllerPhase.missingModels;
    return ListTile(
      leading: Icon(missing ? SpotubeIcons.download : SpotubeIcons.done),
      title: Text(context.l10n.voice_models),
      subtitle: Text(
        missing
            ? context.l10n.voice_models_missing
            : context.l10n.voice_models_ready,
      ),
      trailing: missing
          ? TextButton(
              onPressed: onInstall,
              child: Text(context.l10n.voice_models_install),
            )
          : TextButton(
              onPressed: () => ref
                  .read(voiceControllerProvider.notifier)
                  .deleteModels(),
              child: Text(context.l10n.voice_models_delete),
            ),
    );
  }
}
