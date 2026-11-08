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

import 'package:spotube_themes/v4_validator.dart';
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
        'ui.hostWidgets',
      ]),
    );
  });

  test('the manifest advertises the v4 contract the payload carries', () {
    final manifest =
        jsonDecode(
              File(
                '$repoRoot/themes/spotify-shell-v4/plugin.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    // The plugin format version stays on the app's major; the v4 contract is
    // the payload specVersion, and the manifest advertises it without
    // claiming a format major the installer would reject.
    expect(manifest['pluginApiVersion'], '2.0.0');
    expect(manifest['specVersion'], payload['specVersion']);
    expect(manifest['capabilities'], payload['capabilities']);
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

  test('keeps its core shell layout and navigation targets', () {
    expect(slots.keys.toSet(), {
      'sidebar.content',
      'aside.content',
      'library.content',
      'player.leading',
      'player.controls',
      'player.trailing',
      'home.content',
      'collection.content',
      'artist.content',
      'search.content',
      'queue.content',
      'downloads.content',
      'stats.content',
      'radio.before_sections',
      'radio.after_sections',
      'page.audio',
    });
    expect(layout['sidebar'], 'theme');
    expect(layout['asideWidth'], greaterThan(0));
    expect(layout['sidebarWidth'], greaterThan(0));
    expect(layout['navItems'], ['home', 'search']);
    expect(layout['navbarItems'], ['home', 'search', 'library']);
    expect(layout['libraryItems'], [
      'playlists',
      'albums',
      'artists',
      'local_library',
    ]);
    expect(
      (layout['responsive'] as Map)['compact'],
      containsPair('aside', 'none'),
    );
    expect(
      (layout['responsive'] as Map)['medium'],
      containsPair('aside', 'none'),
    );
  });

  test('pins its host-item context menus and font declarations', () {
    final typedNodes = nodes(slots).toList();
    final contextMenus = typedNodes
        .where((node) => node['type'] == 'contextMenu')
        .toList();
    expect(contextMenus, isNotEmpty);
    expect(contextMenus.every((node) => node['hostItem'] == true), isTrue);

    final assetFonts =
        (((payload['assets'] as Map)['fonts'] as List).cast<Map>()).toList();
    final typographyFonts =
        (((payload['typography'] as Map)['fonts'] as List).cast<Map>())
            .toList();
    final assetPaths = assetFonts
        .map((font) => font['path'] as String)
        .toList();
    final typographyPaths = typographyFonts
        .map((font) => font['asset'] as String)
        .toList();
    expect(assetPaths.toSet(), typographyPaths.toSet());
    expect(assetPaths.toSet(), hasLength(assetPaths.length));
    expect(typographyPaths.toSet(), hasLength(typographyPaths.length));
  });

  test('keeps host widgets inside their documented prop surface', () {
    final widgets = nodes(
      slots,
    ).where((node) => node['type'] == 'hostWidget').toList();

    expect(
      widgets.map((widget) => widget['id']).toSet(),
      {'library.playlists', 'library.artists', 'library.albums'},
    );
    for (final widget in widgets) {
      final allowedProps = v4HostWidgetProps[widget['id']]!;
      final props = (widget['props'] as Map).cast<String, dynamic>();
      expect(
        props.keys.every(allowedProps.contains),
        isTrue,
        reason:
            'reference-theme host-widget props must not drift outside the contract',
      );
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
