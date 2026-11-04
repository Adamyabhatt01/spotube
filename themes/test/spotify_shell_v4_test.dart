// The v4 reference theme.
//
// `themes/spotify-shell-v4` is the contract's acceptance test: it must be a
// real, installable theme that reproduces the Spotify shell while exercising
// the v4-only surface (a routed page, a theme-owned aside, artwork-palette
// tokens and the audio bindings). The generic build/conformance tests already
// prove it compiles, packages and validates; this file pins the parts those
// tests cannot see.

import 'dart:convert';
import 'dart:io';

import 'package:spotube_themes/validator.dart';
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final payload =
      jsonDecode(
            File(
              '$repoRoot/conformance/spotify-shell-v4.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final ui = payload['ui'] as Map<String, dynamic>;
  final slots = ui['slots'] as Map<String, dynamic>;
  final layout = payload['layout'] as Map<String, dynamic>;

  Iterable<Map> nodes(Object? node) sync* {
    if (node is Map) {
      if (node['type'] is String) yield node;
      for (final child in node.values) {
        yield* nodes(child);
      }
    } else if (node is List) {
      for (final child in node) {
        yield* nodes(child);
      }
    }
  }

  test('is a clean v4 payload', () {
    final report = validateThemePayload(payload);
    expect(report.hasErrors, isFalse, reason: report.issues.join('\n'));
    expect(report.warningCount, 0, reason: report.issues.join('\n'));

    expect(payload['specVersion'], 4);
    expect(payload['uiKit'], 'shadcn');
    expect(layout.containsKey('enforce'), isFalse);
  });

  test('declares the capabilities its UI uses', () {
    final capabilities = (payload['capabilities'] as List).cast<String>();
    expect(
      capabilities,
      containsAll([
        'library.read',
        'player.control',
        'audio.effects',
        'ui.pages',
      ]),
    );
  });

  test('ships a routed page and its slot', () {
    final topLevel = (payload['pages'] as List).cast<Map>();
    final document = (ui['pages'] as List).cast<Map>();

    expect(topLevel, isNotEmpty);
    expect(document, isNotEmpty);
    expect(topLevel.map((page) => page['id']), document.map((p) => p['id']));
    expect(document.map((page) => page['parent']), contains('settings'));

    for (final page in document) {
      expect(
        slots,
        contains('page.${page['id']}'),
        reason: 'every routed page needs a slot to render',
      );
    }
  });

  test('owns the aside and uses the artwork palette', () {
    expect(layout['aside'], 'theme');
    expect(slots, contains('aside.content'));
    expect(
      (layout['responsive'] as Map)['medium'],
      containsPair('aside', 'none'),
    );

    final colours = nodes(slots['aside.content'])
        .expand((node) => node.values)
        .whereType<String>()
        .where((value) => value.startsWith('@palette.'))
        .toSet();
    expect(colours, isNotEmpty);
    for (final colour in colours) {
      expect(const {
        '@palette.dominant',
        '@palette.vibrant',
        '@palette.muted',
        '@palette.darkMuted',
        '@palette.lightMuted',
        '@palette.onDominant',
      }, contains(colour));
    }
  });

  test('the audio page edits host state through actions', () {
    final page = slots['page.audio'];
    final bindings = nodes(
      page,
    ).map((node) => node['bind']).whereType<String>().toSet();
    expect(bindings, containsAll(['audio.bass', 'audio.treble']));

    final actions = nodes(page)
        .map((node) => node['action'])
        .whereType<Map>()
        .map((action) => action['type'])
        .toSet();
    expect(actions, containsAll(['setBass', 'setTreble']));
  });
}
