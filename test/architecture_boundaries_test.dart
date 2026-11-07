// Architectural fitness: services must not depend on the provider layer.
//
// `lib/services` is the application core. Where a service needs state owned by
// a Riverpod provider, the dependency is inverted instead: the service defines
// a port (see `services/sourced_track/source_dependencies.dart`) and the
// provider layer supplies the adapter. A direct `provider/` import reverses
// that arrow, couples the core to the provider graph, and makes it impossible
// to exercise the service without a container.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _providerImport = RegExp(
  r'''^\s*import\s+['"]package:spotube/provider/''',
  multiLine: true,
);

final _riverpodImport = RegExp(
  r'''^\s*import\s+['"]package:(hooks_)?riverpod/''',
  multiLine: true,
);

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

List<String> _filesMatching(String directory, RegExp pattern) => [
      for (final file in _dartFiles(directory))
        if (pattern.hasMatch(file.readAsStringSync())) file.path,
    ];

void main() {
  test('services never import the provider layer', () {
    expect(
      _filesMatching('lib/services', _providerImport),
      isEmpty,
      reason: 'Invert the dependency with a port plus a provider-side '
          'adapter instead of importing providers from services/.',
    );
  });

  test('sourced_track stays free of Riverpod', () {
    // The resolution core is driven through SourceDependencies; pulling in
    // Riverpod here would mean the port leaked and the core is no longer
    // testable without a container.
    expect(
      _filesMatching('lib/services/sourced_track', _riverpodImport),
      isEmpty,
    );
  });
}
