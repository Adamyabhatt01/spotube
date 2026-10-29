import 'dart:convert';

/// The result of migrating one v3 payload to v4.
///
/// The payload is best-effort: it is always written, even when the report
/// lists nodes that need a human. The report is the contract with the author;
/// silently guessing a replacement for `search` or a removed key would hide
/// the work.
class MigrationReport {
  MigrationReport({
    required this.payload,
    List<String>? renamed,
    List<String>? removed,
    List<String>? manual,
  }) : renamed = renamed ?? <String>[],
       removed = removed ?? <String>[],
       manual = manual ?? <String>[];

  final Map<String, dynamic> payload;
  final List<String> renamed;
  final List<String> removed;
  final List<String> manual;

  bool get needsManual => manual.isNotEmpty;

  void describe(StringSink out) {
    out.writeln('specVersion 3 → 4');
    if (renamed.isNotEmpty) {
      out.writeln('renamed:');
      for (final line in renamed) {
        out.writeln('  - $line');
      }
    }
    if (removed.isNotEmpty) {
      out.writeln('removed:');
      for (final line in removed) {
        out.writeln('  - $line');
      }
    }
    if (manual.isNotEmpty) {
      out.writeln('needs a human:');
      for (final line in manual) {
        out.writeln('  - $line');
      }
    }
  }
}

/// Migrates a v3 payload to the v4 contract.
///
/// This is deliberately conservative: it preserves every key it does not have
/// to change, and records each change. The produced payload is validated by
/// the caller; any remaining v4 finding is a manual item.
MigrationReport migrateV3Theme(Map<String, dynamic> source) {
  final payload = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
  final renamed = <String>[];
  final removed = <String>[];
  final manual = <String>[];

  final version = payload['specVersion'];
  if (version != 3) {
    manual.add(
      'the source declares specVersion $version, not 3 — review the output',
    );
  }
  payload['specVersion'] = 4;

  final uiKit = payload['uiKit'];
  if (uiKit == null) {
    payload['uiKit'] = 'shadcn';
    renamed.add('added uiKit: shadcn (the v4 default)');
  }

  // v4 rejects the v3 `dynamic` block; the host palette is the replacement.
  if (payload.remove('dynamic') != null) {
    removed.add(
      'dynamic — v4 has no dynamic block; a shell palette comes from the host',
    );
  }

  final layout = payload['layout'];
  if (layout is Map) {
    if (layout.remove('enforce') != null) {
      removed.add(
        'layout.enforce — v4 reads presence (non-empty lists), not a gate',
      );
    }
    _migrateDock(layout, renamed);
    _migrateBreakpoints(layout, renamed, manual);
  }

  _migrateComponents(payload['components'], removed, manual);

  final ui = payload['ui'];
  if (ui is Map) {
    final uiVersion = ui['specVersion'];
    if (uiVersion == 3) {
      ui['specVersion'] = 2;
      renamed.add('ui.specVersion 3 → 2 (v4 uses the v2 UI envelope)');
    }

    _migrateNodes(ui['slots'], manual);
    _migrateNodes(ui['screens'], manual);
    _migrateNodes(ui['templates'], manual);

    // A v4 theme page is declared next to the screens, and also at the top
    // level for routed pages. Copy rather than move so the source stays
    // readable while the author finishes the migration.
    final pages = ui['pages'];
    if (pages is List) {
      payload['pages'] = jsonDecode(jsonEncode(pages));
      renamed.add('ui.pages → pages (also kept at ui.pages)');
    }
  }

  return MigrationReport(
    payload: payload,
    renamed: renamed,
    removed: removed,
    manual: manual,
  );
}

void _migrateDock(Map layout, List<String> renamed) {
  final player = layout['player'];
  if (player is! Map) return;
  if (player['dock'] == 'floating') {
    player['dock'] = 'compact';
    renamed.add(
      'layout.player.dock floating → compact (review: v4 has full/compact/stage)',
    );
  }
}

void _migrateBreakpoints(
  Map layout,
  List<String> renamed,
  List<String> manual,
) {
  final responsive = layout['responsive'];
  if (responsive is! Map) return;
  const aliases = <String, String>{
    'xs': 'compact',
    'sm': 'compact',
    'md': 'medium',
    'lg': 'expanded',
    'xl': 'expanded',
    '2xl': 'expanded',
  };
  final migrated = <String, dynamic>{};
  for (final entry in responsive.entries) {
    final key = entry.key as String;
    final target = aliases[key] ?? key;
    if (target != key) {
      renamed.add('layout.responsive.$key → $target');
    }
    final value = entry.value;
    if (migrated.containsKey(target) && value is Map) {
      final existing = migrated[target];
      if (existing is Map) {
        for (final inner in value.entries) {
          existing.putIfAbsent(inner.key, () => inner.value);
        }
        manual.add(
          'layout.responsive.$key merged into $target — check the merged keys',
        );
        continue;
      }
    }
    migrated[target] = value;
  }
  layout['responsive'] = migrated;
}

void _migrateComponents(
  Object? raw,
  List<String> removed,
  List<String> manual,
) {
  if (raw is! Map) return;
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    for (final state in const ['hover', 'focus', 'active', 'disabled']) {
      if (value.remove(state) != null) {
        removed.add(
          'components.${entry.key}.$state — v4 does not define component '
          'sub-states',
        );
      }
    }
  }
}

void _migrateNodes(Object? raw, List<String> manual) {
  if (raw is List) {
    for (final value in raw) {
      _migrateNodes(value, manual);
    }
    return;
  }
  if (raw is! Map) return;

  // A slot/screen/template container is a map of named bodies, not a node.
  if (raw['type'] is! String) {
    for (final value in raw.values) {
      _migrateNodes(value, manual);
    }
    return;
  }

  final type = raw['type'];
  if (type is String) {
    if (type == 'search') {
      raw['type'] = 'textField';
      manual.add(
        'search node → textField — wire bind/action to setQuery/clearQuery',
      );
    }
  }

  final nested = raw['props'];
  if (nested is Map) {
    for (final entry in nested.entries) {
      raw.putIfAbsent(entry.key, () => entry.value);
    }
    raw.remove('props');
    manual.add(
      'node ${raw['type'] ?? 'unknown'}: nested props flattened — review',
    );
  }

  for (final key in const ['children', 'panels']) {
    _migrateNodes(raw[key], manual);
  }
}
