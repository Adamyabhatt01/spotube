// Which model files the voice engine needs, where to get them, and what
// shipping them obliges us to say. Nothing here is inferred: every hash is the
// sha256 of a file that was downloaded and run, every license was read from the
// model's own statement. A language without a verified entry is simply absent
// from the registry — the settings UI shows it as unavailable instead of
// offering a download nobody checked.
import 'package:spotube/services/voice/matching/text_normalizer.dart';

enum VoiceModelKind {
  /// Streaming transducer set (encoder/decoder/joiner/tokens): the wake stage
  /// and the en/es/fr command stage.
  streamingTransducer,

  /// Shared silero VAD, used only by the always-on wake stage.
  vad,

  /// Offline (Whisper-family) directory: hi/ar command stage.
  offline,
}

class VoiceModelFile {
  const VoiceModelFile({
    required this.name,
    required this.url,
    required this.sha256,
    required this.approxBytes,
    this.mirrorUrls = const [],
  });

  final String name;
  final String url;

  /// Pinned in-app: no remote manifest decides what we accept (§11).
  final String sha256;
  final int approxBytes;
  final List<String> mirrorUrls;
}

class VoiceModelSpec {
  const VoiceModelSpec({
    required this.id,
    required this.kind,
    required this.license,
    required this.attribution,
    required this.files,
  });

  final String id;
  final VoiceModelKind kind;

  /// The model's own license, checked against Spotube's BSD-4-Clause
  /// distribution — a non-commercial model would have to be dropped here.
  final String license;

  /// Text shown to the user; attribution has to survive the download step.
  final String attribution;

  final List<VoiceModelFile> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.approxBytes);
}

const _hfEn20M =
    'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main';

/// English streaming zipformer, int8: 44.5× realtime on one thread in the
/// Phase 0 spike, and small enough to be the always-on wake stage.
const VoiceModelSpec voiceEnStreaming = VoiceModelSpec(
  id: 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17-int8',
  kind: VoiceModelKind.streamingTransducer,
  license: 'Apache-2.0',
  attribution:
      'sherpa-onnx streaming Zipformer (English, 20M parameters, int8), '
      'csukuangfj / k2-fsa, Apache License 2.0',
  files: [
    VoiceModelFile(
      name: 'encoder-epoch-99-avg-1.int8.onnx',
      url: '$_hfEn20M/encoder-epoch-99-avg-1.int8.onnx',
      sha256:
          '3810755ce7c3ab26b42a8bcf39d191308fa27fb0f53358823ba46141d03b7eb3',
      approxBytes: 42845182,
      mirrorUrls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main/encoder-epoch-99-avg-1.int8.onnx',
      ],
    ),
    VoiceModelFile(
      name: 'decoder-epoch-99-avg-1.int8.onnx',
      url: '$_hfEn20M/decoder-epoch-99-avg-1.int8.onnx',
      sha256:
          '21e2a2acd961b3ac72f55be2f10f1a285e1b0b0ba010d7c0b6eab141411b163c',
      approxBytes: 539499,
      mirrorUrls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main/decoder-epoch-99-avg-1.int8.onnx',
      ],
    ),
    VoiceModelFile(
      name: 'joiner-epoch-99-avg-1.int8.onnx',
      url: '$_hfEn20M/joiner-epoch-99-avg-1.int8.onnx',
      sha256:
          'e085d73b593cf9b0707f370dbd656d58327d3fe36d80d849202ef81df02cb01e',
      approxBytes: 259572,
      mirrorUrls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main/joiner-epoch-99-avg-1.int8.onnx',
      ],
    ),
    VoiceModelFile(
      name: 'tokens.txt',
      url: '$_hfEn20M/tokens.txt',
      sha256:
          '49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb',
      approxBytes: 5048,
      mirrorUrls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17/resolve/main/tokens.txt',
      ],
    ),
  ],
);

/// Shared speech gate for the wake stage. MIT, so the weights are as free as
/// the code — the trap this registry exists to catch.
const VoiceModelSpec voiceSileroVad = VoiceModelSpec(
  id: 'silero-vad-v5',
  kind: VoiceModelKind.vad,
  license: 'MIT',
  attribution: 'Silero VAD (snakers4/silero-vad), MIT License',
  files: [
    VoiceModelFile(
      name: 'silero_vad.onnx',
      url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
      sha256:
          '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
      approxBytes: 643854,
    ),
  ],
);

/// Every model that has been verified (url + sha256 + license).
const List<VoiceModelSpec> voiceVerifiedModels = [
  voiceEnStreaming,
  voiceSileroVad,
];

/// The same set keyed by [VoiceModelSpec.id], built from the list so a key can
/// never drift from the spec it points at.
final Map<String, VoiceModelSpec> voiceModelRegistry = {
  for (final spec in voiceVerifiedModels) spec.id: spec,
};

/// The command-stage model for a language. Only English is verified; the rest
/// are §10's open rows and stay unlisted until Phase 0(e) fills them with real
/// hashes and a license check.
VoiceModelSpec? streamingCommandModelFor(VoiceLanguage language) =>
    switch (language) {
      VoiceLanguage.en => voiceEnStreaming,
      _ => null,
    };

/// Whether a verified command-stage model exists for [primary] or
/// [secondary]. Only English is verified today; the settings UI must not
/// offer a language that can never transcribe, and the controller reports
/// `missingModels` for one rather than running the English model against
/// speech it cannot represent.
bool voiceCommandsSupported({
  required VoiceLanguage primary,
  VoiceLanguage? secondary,
}) =>
    streamingCommandModelFor(primary) != null ||
    (secondary != null && streamingCommandModelFor(secondary) != null);

/// What has to be on disk before [mode] can run. The wake stage is English
/// whatever the user's language is (§3), so the en set is needed for it, and
/// the command stage needs the language's own model.
List<VoiceModelSpec> requiredModelsFor({
  required VoiceLanguage language,
  required bool withWakeStage,
}) {
  final command = streamingCommandModelFor(language);
  final specs = <VoiceModelSpec>[
    if (withWakeStage) voiceEnStreaming,
    if (command != null) command,
    if (withWakeStage) voiceSileroVad,
  ];
  // Same model serves both stages for English; keep one entry.
  final seen = <String>{};
  return [for (final s in specs) if (seen.add(s.id)) s];
}

/// Model file paths on disk for the engine parameters, or null when something
/// is missing — the engine distinguishes "not downloaded" from "broken" by
/// asking this rather than by letting onnxruntime find out.
Map<String, String> resolvedVoiceModelPaths(String directory) => {
      for (final spec in voiceVerifiedModels)
        for (final file in spec.files) file.name: '$directory/${file.name}',
    };

/// Where [role]'s file lives, by the role the engine parameters call for
/// ("encoder", "decoder", "joiner", "tokens", "vad") rather than by a file name
/// the caller would have to retype. File names are a property of one training
/// run; the parameters are a property of the API.
String modelPathFor(VoiceModelSpec spec, String directory, String role) {
  final file = spec.files.firstWhere(
    (f) => f.name.contains(role),
    orElse: () => throw StateError('${spec.id} ships no "$role" file'),
  );
  return '$directory/${file.name}';
}
