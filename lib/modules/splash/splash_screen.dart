import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/utils/theme_converter.dart';

/// Entrance animation for the launch splash.
enum SplashAnimation {
  /// Static logo, no motion.
  none,

  /// Logo fades in with a slight settle-scale.
  fade,

  /// Logo pops from 80% with an ease-out-back curve.
  scale,

  /// Logo rises from below while fading in.
  slide,
}

/// Branded launch splash shown before the app shell builds.
///
/// The native splash has no Linux branding, so this in-app screen owns
/// the launch moment: Spotube logo over the themed background (when a
/// live or cached theme already exists) or a dark neutral otherwise.
class SplashScreen extends StatefulWidget {
  final ThemeDefinition? theme;
  final SplashAnimation animation;
  final Duration duration;
  final bool useThemedBackground;

  /// Absolute path of a custom logo file. Animated formats play natively.
  final String? logoPath;

  /// Absolute path of a custom background file (static or animated
  /// GIF/WebP, decoded natively). Drawn cover-fit behind the logo.
  final String? backgroundPath;

  const SplashScreen({
    super.key,
    this.theme,
    this.animation = SplashAnimation.fade,
    this.duration = const Duration(milliseconds: 900),
    this.useThemedBackground = true,
    this.logoPath,
    this.backgroundPath,
  });

  static const fallbackBackground = Color(0xFF131316);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.animation != SplashAnimation.none) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _background(Brightness brightness) {
    if (!widget.useThemedBackground) return SplashScreen.fallbackBackground;
    final colors = brightness == Brightness.dark
        ? widget.theme?.dark
        : widget.theme?.light;
    if (colors == null) return SplashScreen.fallbackBackground;
    try {
      return ThemeConverter.parseColor(colors.background);
    } catch (_) {
      return SplashScreen.fallbackBackground;
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.logoPath != null
        ? Image.file(
            File(widget.logoPath!),
            width: 128,
            height: 128,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/branding/spotube-logo.png',
              width: 128,
              height: 128,
            ),
          )
        : Image.asset(
            'assets/branding/spotube-logo.png',
            width: 128,
            height: 128,
          );

    final Widget animated;
    switch (widget.animation) {
      case SplashAnimation.none:
        animated = logo;
      case SplashAnimation.fade:
        animated = FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(_fade),
            child: logo,
          ),
        );
      case SplashAnimation.scale:
        animated = ScaleTransition(scale: _scale, child: logo);
      case SplashAnimation.slide:
        animated = SlideTransition(
          position: _slide,
          child: FadeTransition(opacity: _fade, child: logo),
        );
    }

    // This screen renders ABOVE the app widget (before ShadcnApp
    // builds), so no Directionality/MediaQuery exists yet: provide
    // text direction explicitly and read brightness from the
    // dispatcher instead of MediaQuery.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: _background(
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        ),
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.backgroundPath != null)
              Positioned.fill(
                child: Image.file(
                  File(widget.backgroundPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            Center(child: animated),
          ],
        ),
      ),
    );
  }
}
