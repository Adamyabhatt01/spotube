import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/modules/theme_ui/theme_ui_assets.dart';

/// The names and marks a theme may put on the host's own chrome.
///
/// The About page keeps the host's version, licence and attribution whatever a
/// theme says; everything here is presentation. Every value is clamped and
/// validated at the boundary because it reaches text styles and window titles.
class ThemeBranding {
  final String appName;
  final String shortName;
  final String wordmark;
  final String? wordmarkFont;
  final String? wordmarkAsset;
  final String aboutName;
  final String notificationName;
  final String windowTitle;
  final String? tagline;
  final String? logoAsset;
  final bool showHostAttribution;

  const ThemeBranding({
    this.appName = 'Spotube',
    this.shortName = 'Spotube',
    this.wordmark = 'Spotube',
    this.wordmarkFont = 'Cookie',
    this.wordmarkAsset,
    this.aboutName = 'Spotube',
    this.notificationName = 'Spotube',
    this.windowTitle = 'Spotube',
    this.tagline,
    this.logoAsset,
    this.showHostAttribution = true,
  });

  factory ThemeBranding.from(ThemeDefinition? theme) {
    if (theme == null) return const ThemeBranding();

    final branding = theme.branding;
    final wordmark = _map(branding['wordmark']);
    final typography = theme.typography;

    final appName = _text(branding['appName'], 48) ??
        _text(branding['shortName'], 24) ??
        'Spotube';
    final markText = _text(wordmark['text'], 48);

    return ThemeBranding(
      appName: appName,
      shortName: _text(branding['shortName'], 24) ?? appName,
      wordmark: markText ?? appName,
      wordmarkFont: _family(wordmark['fontFamily']) ??
          _family(typography['brandFamily']) ??
          'Cookie',
      wordmarkAsset: _asset(wordmark['asset']),
      aboutName: _text(branding['aboutName'], 48) ?? appName,
      notificationName:
          _text(branding['notificationName'], 48) ?? appName,
      windowTitle: _text(branding['windowTitle'], 80) ?? appName,
      tagline: _text(branding['tagline'], 120),
      logoAsset: _asset(branding['logo']),
      showHostAttribution: branding['showHostAttribution'] is bool
          ? branding['showHostAttribution'] as bool
          : true,
    );
  }

}

/// The theme's brand file, resolved inside its plugin directory.
final themeBrandAssetFileProvider = Provider.family<File?, String?>(
  (ref, source) {
    final assets = ref.watch(themeUiAssetsProvider).asData?.value;
    final file = assets?.resolve(source);
    if (file == null || !file.existsSync()) return null;
    return file;
  },
);

/// The theme's wordmark: its asset when one resolves, else its text in the
/// theme's own brand family.
class ThemeBrandMark extends ConsumerWidget {
  final ThemeBranding branding;
  final double fontSize;
  final Color? color;
  final TextAlign? textAlign;

  const ThemeBrandMark({
    required this.branding,
    this.fontSize = 30,
    this.color,
    this.textAlign,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(
      themeBrandAssetFileProvider(
        branding.wordmarkAsset ?? branding.logoAsset,
      ),
    );

    if (file != null) {
      return Image.file(
        file,
        height: fontSize * 1.4,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _text(),
      );
    }
    return _text();
  }

  Widget _text() {
    return Text(
      branding.wordmark,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        fontFamily: branding.wordmarkFont,
        fontSize: fontSize,
        letterSpacing: 1.8,
        color: color,
      ),
    );
  }
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is! Map) return const {};
  return raw.cast<String, dynamic>();
}

String? _text(Object? raw, int max) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty || value.length > max) return null;
  return value;
}

String? _family(Object? raw) {
  final value = _text(raw, 64);
  if (value == null) return null;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]*$').hasMatch(value)) return null;
  return value;
}

String? _asset(Object? raw) {
  final value = _text(raw, 512);
  if (value == null || !value.startsWith('asset://')) return null;
  return value;
}
