// gen-l10n builds each locale's method signature from app_en.arb, but the body
// from the locale's own string — so a translation that drops a placeholder
// compiles fine and silently discards the value at runtime. Korean's
// "error": "에러" over English's "Error {error}" is the archetype: the generated
// override took `Object error` and never used it (upstream PR #3129).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Placeholders as written by translators: `{name}` for a plain argument and
/// `{name, plural, ...}` / `{name, select, ...}` for an ICU one.
final RegExp _placeholder = RegExp(r'\{\s*(\w+)\s*[,}]');

Set<String> _placeholdersOf(String message) =>
    _placeholder.allMatches(message).map((m) => m[1]!).toSet();

/// Message keys only: strips `@key`/`@@info` metadata and non-strings.
Map<String, String> _messagesOf(Map<String, dynamic> arb) => {
      for (final entry in arb.entries)
        if (!entry.key.startsWith('@') && entry.value is String)
          entry.key: entry.value as String,
    };

void main() {
  const dir = 'lib/l10n';

  test('every locale uses exactly the placeholders app_en.arb declares', () {
    final template = _messagesOf(
        jsonDecode(File('$dir/app_en.arb').readAsStringSync())
            as Map<String, dynamic>);

    expect(template, isNotEmpty, reason: 'app_en.arb is the l10n template');

    final locales = Directory(dir)
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((name) => name.startsWith('app_') && name.endsWith('.arb'))
        .where((name) => name != 'app_en.arb')
        .toList()
      ..sort();

    expect(locales, isNotEmpty);

    final violations = <String>[];

    for (final fileName in locales) {
      final messages = _messagesOf(
          jsonDecode(File('$dir/$fileName').readAsStringSync())
              as Map<String, dynamic>);

      for (final entry in template.entries) {
        final translated = messages[entry.key];
        // An absent key is an untranslated message, tracked separately in
        // untranslated_messages.json — not a placeholder problem.
        if (translated == null) continue;

        final declared = _placeholdersOf(entry.value);
        final used = _placeholdersOf(translated);

        final dropped = declared.difference(used);
        final undeclared = used.difference(declared);

        if (dropped.isNotEmpty) {
          violations.add(
            '$fileName: ${entry.key} drops {${dropped.join(', ')}} '
            'from "${entry.value}" — the value is parsed away and never shown',
          );
        }
        if (undeclared.isNotEmpty) {
          violations.add(
            '$fileName: ${entry.key} uses {${undeclared.join(', ')}} which '
            'app_en.arb does not declare',
          );
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
