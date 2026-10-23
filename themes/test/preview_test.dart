import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tools/preview.dart';

/// The preview is how a theme gets reviewed before the host can draw it.
/// If it silently drops an asset or a screen, the review is a lie, so these
/// tests check that the generated document stands on its own.
void main() {
  late String html;

  setUpAll(() {
    final payload = jsonDecode(
      File('conformance/obsidian.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    html = PreviewBuilder(
      id: 'obsidian',
      themeDir: 'themes/obsidian',
      payload: payload,
    ).build();
  });

  test('is one standalone document', () {
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('data-mode="dark"'));
    expect(html, isNot(contains('asset://')),
        reason: 'every asset has to be inlined, not left as a theme path');
    expect(html, isNot(contains('src="themes/')));
  });

  test('inlines the OFL fonts', () {
    expect(html, contains('@font-face'));
    expect(html, contains("font-family: 'Silkscreen'"));
    expect(html, contains("font-family: 'VT323'"));
    expect(html, contains('data:font/ttf;base64,'));
  });

  test('carries both schemes as CSS variables', () {
    expect(html, contains('--primary: #a855f7;'));
    expect(html, contains('--primary: #6d28d9;'));
    expect(html, contains('DARK · 39 ROLES'));
    expect(html, contains('LIGHT · 39 ROLES'));
  });

  test('renders the stage, its record and the screens', () {
    expect(html, contains('data-screen="stage"'));
    expect(html, contains('data-screen="now-playing"'));
    expect(html, contains('data-screen="colophon"'));
    expect(html, contains('data-screen="palette"'));
    expect(html, contains('obsidian-spin'));
    expect(html, contains('class="spin gated"'));
    expect(html, contains('OBSIDIAN HEARTS'));
  });

  test('tiles the background and keeps the pixel bevel', () {
    expect(html, contains('background-size: 128px 128px'));
    expect(html, contains("background-image: url('data:image/png;base64,"));
    expect(html, contains('card-pixel'));
  });

  test('does not fetch anything from the network', () {
    expect(RegExp(r'(src|href)="https?://').hasMatch(html), isFalse);
    expect(html.length, greaterThan(200000));
  });
}
