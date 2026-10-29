import 'dart:io';

import 'package:flutter/foundation.dart';

final kIsDesktop = kIsLinux || kIsWindows || kIsMacOS;

final kIsMobile = kIsAndroid || kIsIOS;

final kIsFlatpak = kIsWeb ? false : Platform.environment["FLATPAK_ID"] != null;

final kIsMacOS = kIsWeb ? false : Platform.isMacOS;
final kIsLinux = kIsWeb ? false : Platform.isLinux;
final kIsAndroid = kIsWeb ? false : Platform.isAndroid;
final kIsIOS = kIsWeb ? false : Platform.isIOS;
final kIsWindows = kIsWeb ? false : Platform.isWindows;

/// True under `flutter test`. Keeps process-backed features (the spectrum
/// capture) out of widget tests.
final kIsTest =
    kIsWeb ? false : Platform.environment.containsKey('FLUTTER_TEST');

/// Whether the libmpv build in use ships FFmpeg's `dynaudnorm` filter.
///
/// The bundled Android and Windows builds compile only the `equalizer` filter;
/// iOS/macOS ship FFmpeg's defaults and Linux uses the system libmpv. An
/// unavailable filter fails the whole `af` chain, so callers must not reference
/// dynaudnorm where it is missing.
final kLibmpvSupportsDynaudnorm = kIsLinux || kIsMacOS || kIsIOS;

/// Whether the libmpv build in use ships FFmpeg's `extrastereo` filter.
///
/// Same bundled builds that omit `dynaudnorm` also omit the stereo widener, so
/// the "Virtual surround" toggle is only offered where the chain can hold it.
final kLibmpvSupportsSpatialAudio = kIsLinux || kIsMacOS || kIsIOS;

/// Whether the libmpv build in use ships FFmpeg's `pan` filter.
///
/// The mono downmix rides the same FFmpeg filter set as the other effects, so
/// the "Mono audio" toggle is only offered on the builds that include it.
final kLibmpvSupportsMonoAudio = kIsLinux || kIsMacOS || kIsIOS;
